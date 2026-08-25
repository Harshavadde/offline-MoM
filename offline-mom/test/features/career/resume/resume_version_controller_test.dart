// Tests ResumeVersionController (features/career/resume/presentation/
// providers/resume_version_providers.dart) - mirrors
// resume_editor_controller_test.dart's exact ProviderContainer + real
// repository pattern. Extended (V3 Milestone 0) with full block-library
// repository wiring so restoreToDraft() - which reads/writes every library
// table - can be exercised the same way.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/resume_version_providers.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/resume_link.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/resume_version.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/resume_version_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late EducationBlockRepository educationBlockRepository;
  late ProjectBlockRepository projectBlockRepository;
  late CertificationBlockRepository certificationBlockRepository;
  late SkillEntryRepository skillEntryRepository;
  late ResumeVersionRepository resumeVersionRepository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    educationBlockRepository = SqfliteEducationBlockRepository(db);
    projectBlockRepository = SqfliteProjectBlockRepository(db);
    certificationBlockRepository = SqfliteCertificationBlockRepository(db);
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    resumeVersionRepository = SqfliteResumeVersionRepository(db);

    container = ProviderContainer(
      overrides: [
        resumeRepositoryProvider.overrideWithValue(resumeRepository),
        resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
        experienceBlockRepositoryProvider.overrideWithValue(experienceBlockRepository),
        educationBlockRepositoryProvider.overrideWithValue(educationBlockRepository),
        projectBlockRepositoryProvider.overrideWithValue(projectBlockRepository),
        certificationBlockRepositoryProvider.overrideWithValue(certificationBlockRepository),
        skillEntryRepositoryProvider.overrideWithValue(skillEntryRepository),
        resumeVersionRepositoryProvider.overrideWithValue(resumeVersionRepository),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> insertResume({String fullName = 'Jane Doe', String? email}) {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: fullName, email: email, createdAt: now, updatedAt: now),
    );
  }

  ResumeSnapshot emptySnapshot(int resumeId, {ResumeSnapshotProfile? profile}) {
    return ResumeSnapshot(
      resumeId: resumeId,
      compiledAt: DateTime(2026, 1, 1),
      profile: profile ?? const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      experience: const [],
      education: const [],
      projects: const [],
      certifications: const [],
      skills: const [],
    );
  }

  Future<int> insertVersion(int resumeId, {String label = 'v1', ResumeSnapshot? snapshot}) {
    return resumeVersionRepository.insert(ResumeVersion(
      id: null,
      resumeId: resumeId,
      versionLabel: label,
      compiledSnapshot: snapshot ?? emptySnapshot(resumeId),
      createdAt: DateTime(2026, 1, 1),
    ));
  }

  Future<int> insertExperience({String role = 'Engineer'}) {
    final now = DateTime(2026, 1, 1);
    return experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: role,
      company: 'Acme',
      startDate: '2020-01',
      endDate: '2022-01',
      bullets: const ['Did the thing.'],
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> insertSkill({String name = 'Flutter'}) {
    return skillEntryRepository.insert(
      SkillEntry(id: null, name: name, category: SkillCategory.technical, createdAt: DateTime(2026, 1, 1)),
    );
  }

  test('rename() persists the new label and clears busy/error state', () async {
    final resumeId = await insertResume();
    final versionId = await insertVersion(resumeId);

    await container
        .read(resumeVersionControllerProvider(resumeId).notifier)
        .rename(versionId, 'Applied to Acme');

    final persisted = await resumeVersionRepository.getById(versionId);
    expect(persisted!.versionLabel, 'Applied to Acme');
    final state = container.read(resumeVersionControllerProvider(resumeId));
    expect(state.isBusy, isFalse);
    expect(state.error, isNull);
  });

  test('delete() removes the version row', () async {
    final resumeId = await insertResume();
    final versionId = await insertVersion(resumeId);

    await container.read(resumeVersionControllerProvider(resumeId).notifier).delete(versionId);

    expect(await resumeVersionRepository.getById(versionId), isNull);
  });

  test('family + autoDispose scoping: two different resumeIds keep '
      'independent busy/error state', () async {
    final resumeIdA = await insertResume();
    final resumeIdB = await insertResume();

    // Force resumeIdA's controller into an error state; resumeIdB's own
    // controller instance must remain untouched.
    await db.close();
    await container
        .read(resumeVersionControllerProvider(resumeIdA).notifier)
        .rename(999999, 'will fail');

    expect(container.read(resumeVersionControllerProvider(resumeIdA)).error, isNotNull);
    expect(container.read(resumeVersionControllerProvider(resumeIdB)).error, isNull);
  });

  test('a repository failure sets a friendly error and resets isBusy to false', () async {
    final resumeId = await insertResume();
    final versionId = await insertVersion(resumeId);
    await db.close();

    await container
        .read(resumeVersionControllerProvider(resumeId).notifier)
        .delete(versionId);

    final state = container.read(resumeVersionControllerProvider(resumeId));
    expect(state.isBusy, isFalse);
    expect(state.error, isNotNull);
  });

  group('restoreToDraft()', () {
    test('restores Profile fields from the frozen snapshot, including clearing a field '
        'the snapshot has as null', () async {
      final resumeId = await insertResume(fullName: 'Current Name', email: 'current@example.com');
      final versionId = await insertVersion(
        resumeId,
        snapshot: emptySnapshot(
          resumeId,
          profile: const ResumeSnapshotProfile(
            fullName: 'Restored Name',
            location: 'Restored City',
            links: [ResumeLink(label: 'GitHub', url: 'https://github.com/example')],
          ),
        ),
      );

      await container
          .read(resumeVersionControllerProvider(resumeId).notifier)
          .restoreToDraft(versionId);

      final restored = await resumeRepository.getById(resumeId);
      expect(restored!.fullName, 'Restored Name');
      expect(restored.location, 'Restored City');
      expect(restored.links.single.label, 'GitHub');
      // The snapshot's profile has no email - restore must clear the
      // resume's current one, not silently keep it.
      expect(restored.email, isNull);
    });

    test('replaces the live composition with the version\'s blocks, in order', () async {
      final resumeId = await insertResume();
      final keptExperienceId = await insertExperience(role: 'Kept Role');
      final currentOnlyExperienceId = await insertExperience(role: 'Current-Only Role');
      // What's live right now, before restoring - must not survive.
      await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, currentOnlyExperienceId);

      final versionId = await insertVersion(
        resumeId,
        snapshot: ResumeSnapshot(
          resumeId: resumeId,
          compiledAt: DateTime(2026, 1, 1),
          profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
          experience: [
            ResolvedExperienceEntry(
              sourceBlockId: keptExperienceId,
              role: 'Kept Role',
              company: 'Acme',
              startDate: '2020-01',
              bullets: const ['Did the thing.'],
            ),
          ],
        ),
      );

      await container
          .read(resumeVersionControllerProvider(resumeId).notifier)
          .restoreToDraft(versionId);

      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.map((r) => r.blockId), [keptExperienceId]);
    });

    test('re-attaches skills by resolving them through getAll() (no getById on that repository)',
        () async {
      final resumeId = await insertResume();
      final skillId = await insertSkill(name: 'Dart');

      final versionId = await insertVersion(
        resumeId,
        snapshot: ResumeSnapshot(
          resumeId: resumeId,
          compiledAt: DateTime(2026, 1, 1),
          profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
          skills: [
            ResolvedSkillEntry(sourceBlockId: skillId, name: 'Dart', category: SkillCategory.technical),
          ],
        ),
      );

      await container
          .read(resumeVersionControllerProvider(resumeId).notifier)
          .restoreToDraft(versionId);

      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.single.blockType, ResumeBlockType.skill);
      expect(refs.single.blockId, skillId);
    });

    test('silently skips a sourceBlockId whose library block was deleted since the version was saved',
        () async {
      final resumeId = await insertResume();
      final deletedExperienceId = await insertExperience(role: 'Now Deleted');
      final survivingExperienceId = await insertExperience(role: 'Still Here');

      final versionId = await insertVersion(
        resumeId,
        snapshot: ResumeSnapshot(
          resumeId: resumeId,
          compiledAt: DateTime(2026, 1, 1),
          profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
          experience: [
            ResolvedExperienceEntry(
              sourceBlockId: deletedExperienceId,
              role: 'Now Deleted',
              company: 'Acme',
              startDate: '2020-01',
            ),
            ResolvedExperienceEntry(
              sourceBlockId: survivingExperienceId,
              role: 'Still Here',
              company: 'Acme',
              startDate: '2021-01',
            ),
          ],
        ),
      );
      await experienceBlockRepository.delete(deletedExperienceId);

      await container
          .read(resumeVersionControllerProvider(resumeId).notifier)
          .restoreToDraft(versionId);

      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.map((r) => r.blockId), [survivingExperienceId]);
      final state = container.read(resumeVersionControllerProvider(resumeId));
      expect(state.error, isNull, reason: 'a dangling reference must not surface as an error');
    });

    test('sets a friendly error when the version does not exist, and touches nothing', () async {
      final resumeId = await insertResume(fullName: 'Untouched Name');
      // Pins the autoDispose provider alive across restoreToDraft's many
      // awaits - matches resume_editor_controller_test.dart's waitForReady
      // precedent for the same reason (a plain read() alone doesn't count
      // as an active listener, so nothing stops autoDispose from tearing
      // the controller down - and its in-flight state with it - between
      // event-loop turns).
      container.listen(resumeVersionControllerProvider(resumeId), (previous, next) {});

      await container
          .read(resumeVersionControllerProvider(resumeId).notifier)
          .restoreToDraft(999999);

      final state = container.read(resumeVersionControllerProvider(resumeId));
      expect(state.error, contains('could not be found'));
      expect((await resumeRepository.getById(resumeId))!.fullName, 'Untouched Name');
    });

    test('sets a friendly error when the resume itself no longer exists', () async {
      final resumeId = await insertResume();
      final versionId = await insertVersion(resumeId);
      await resumeRepository.delete(resumeId);
      container.listen(resumeVersionControllerProvider(resumeId), (previous, next) {});

      await container
          .read(resumeVersionControllerProvider(resumeId).notifier)
          .restoreToDraft(versionId);

      final state = container.read(resumeVersionControllerProvider(resumeId));
      expect(state.error, contains('could not be found'));
    });
  });
}
