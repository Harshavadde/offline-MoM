// Tests ResumeEditorController (features/career/resume/presentation/
// providers/resume_editor_providers.dart) through a ProviderContainer with
// every leaf repository/use-case/service provider it transitively reads
// overridden to point at a throwaway in-memory database - mirrors
// notes_controller_test.dart's exact pattern (real repositories, no mocks,
// since appDatabaseProvider/AppDatabase itself cannot run in a test
// environment). saveResumeVersionUseCaseProvider is overridden on its own,
// the same way save_resume_version_use_case_test.dart already does, since
// its default wiring calls path_provider's newCareerOutputPath, which needs
// a platform channel this environment doesn't have.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/delete_library_block_use_case.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/resume_editor_providers.dart';
import 'package:offline_mom/features/career/resume/save_resume_version_use_case.dart';
import 'package:offline_mom/models/education_block.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/resume_version_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:offline_mom/services/resume/resume_pdf_export_service.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  // Post-Milestone-5 visual-quality redesign pass: the renderer now loads
  // the bundled Inter font via rootBundle, which requires the Flutter
  // services binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late EducationBlockRepository educationBlockRepository;
  late ProjectBlockRepository projectBlockRepository;
  late CertificationBlockRepository certificationBlockRepository;
  late SkillEntryRepository skillEntryRepository;
  late CustomSectionBlockRepository customSectionBlockRepository;
  late ResumeVersionRepository resumeVersionRepository;
  late Directory tempDir;
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
    customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    resumeVersionRepository = SqfliteResumeVersionRepository(db);
    tempDir = await Directory.systemTemp.createTemp('resume_editor_controller_test_');

    container = ProviderContainer(
      overrides: [
        resumeRepositoryProvider.overrideWithValue(resumeRepository),
        resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
        experienceBlockRepositoryProvider.overrideWithValue(experienceBlockRepository),
        educationBlockRepositoryProvider.overrideWithValue(educationBlockRepository),
        projectBlockRepositoryProvider.overrideWithValue(projectBlockRepository),
        certificationBlockRepositoryProvider.overrideWithValue(certificationBlockRepository),
        skillEntryRepositoryProvider.overrideWithValue(skillEntryRepository),
        customSectionBlockRepositoryProvider.overrideWithValue(customSectionBlockRepository),
        resumeVersionRepositoryProvider.overrideWithValue(resumeVersionRepository),
        saveResumeVersionUseCaseProvider.overrideWithValue(
          SaveResumeVersionUseCase(
            compilerService: ResumeCompilerService(
              experienceBlockRepository: experienceBlockRepository,
              educationBlockRepository: educationBlockRepository,
              projectBlockRepository: projectBlockRepository,
              certificationBlockRepository: certificationBlockRepository,
              skillEntryRepository: skillEntryRepository,
              customSectionBlockRepository: customSectionBlockRepository,
            ),
            resumeVersionRepository: resumeVersionRepository,
            pdfExportService: const PwResumePdfExportService(),
            outputPathProvider: (ext) async =>
                '${tempDir.path}/resume_${DateTime.now().microsecondsSinceEpoch}.$ext',
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> insertResume({String title = 'Backend-Focused', String fullName = 'Jane Doe', String? templateId}) {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: title, fullName: fullName, templateId: templateId, createdAt: now, updatedAt: now),
    );
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

  Future<int> insertEducation() {
    final now = DateTime(2026, 1, 1);
    return educationBlockRepository.insert(EducationBlock(
      id: null,
      institution: 'State University',
      degree: 'B.S. Computer Science',
      startDate: '2016-08',
      endDate: '2020-05',
      createdAt: now,
      updatedAt: now,
    ));
  }

  ResumeEditorReady readyState(int resumeId) {
    final state = container.read(resumeEditorControllerProvider(resumeId));
    return state as ResumeEditorReady;
  }

  // `resumeEditorControllerProvider` is `.autoDispose` (by design - see its
  // own doc comment). Plain `container.read()` alone does not keep an
  // autoDispose provider alive between event-loop turns, so a polling loop
  // built only on `read()` would let Riverpod dispose and re-`build()` (and
  // therefore re-`_load()`) the controller on every iteration - the exact
  // cause of the "database has been locked" warnings and hangs seen before
  // this fix. `container.listen(...)`, left open for the test's lifetime
  // and cleaned up by `container.dispose()` in `tearDown`, pins the
  // provider alive, matching Riverpod's own documented pattern for testing
  // autoDispose providers.
  Future<void> waitForReady(int resumeId) async {
    container.listen(resumeEditorControllerProvider(resumeId), (previous, next) {});
    while (container.read(resumeEditorControllerProvider(resumeId)) is ResumeEditorLoading) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('attachBlock() keeps each block type in its own section - an '
      'education block never leaks into refsOf(experience) or vice versa', () async {
    final resumeId = await insertResume();
    final experienceId = await insertExperience();
    final educationId = await insertEducation();
    await waitForReady(resumeId);
    final notifier = container.read(resumeEditorControllerProvider(resumeId).notifier);

    await notifier.attachBlock(ResumeBlockType.experience, experienceId);
    await notifier.attachBlock(ResumeBlockType.education, educationId);

    final state = readyState(resumeId);
    expect(state.refsOf(ResumeBlockType.experience).single.blockId, experienceId);
    expect(state.refsOf(ResumeBlockType.education).single.blockId, educationId);
  });

  test('build() loads the resume identity and its live composition', () async {
    final resumeId = await insertResume(title: 'My Resume');
    final experienceId = await insertExperience();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);

    await waitForReady(resumeId);
    final state = readyState(resumeId);

    expect(state.resume.title, 'My Resume');
    expect(state.refsOf(ResumeBlockType.experience), hasLength(1));
    expect(state.refsOf(ResumeBlockType.experience).single.blockId, experienceId);
  });

  test('build() with a resume id that does not exist produces a specific, '
      'friendly load error', () async {
    await waitForReady(999999);
    final state = container.read(resumeEditorControllerProvider(999999));

    expect(state, isA<ResumeEditorLoadError>());
    expect((state as ResumeEditorLoadError).message, contains('could not be found'));
  });

  test('updateProfile() persists Profile fields and is reflected on reload', () async {
    final resumeId = await insertResume();
    await waitForReady(resumeId);

    await container.read(resumeEditorControllerProvider(resumeId).notifier).updateProfile(
          fullName: 'Updated Name',
          email: 'updated@example.com',
        );

    expect(readyState(resumeId).resume.fullName, 'Updated Name');
    final persisted = await resumeRepository.getById(resumeId);
    expect(persisted!.fullName, 'Updated Name');
    expect(persisted.email, 'updated@example.com');
  });

  test('updateProfile() persists targetRole and is reflected on reload '
      '(V3 Milestone 0 - closes the previously-dead field)', () async {
    final resumeId = await insertResume();
    await waitForReady(resumeId);

    await container.read(resumeEditorControllerProvider(resumeId).notifier).updateProfile(
          targetRole: 'Senior Backend Engineer',
        );

    expect(readyState(resumeId).resume.targetRole, 'Senior Backend Engineer');
    final persisted = await resumeRepository.getById(resumeId);
    expect(persisted!.targetRole, 'Senior Backend Engineer');
  });

  test('attachBlock() appends a library block to this resume\'s composition', () async {
    final resumeId = await insertResume();
    final experienceId = await insertExperience();
    await waitForReady(resumeId);

    await container
        .read(resumeEditorControllerProvider(resumeId).notifier)
        .attachBlock(ResumeBlockType.experience, experienceId);

    final refs = readyState(resumeId).refsOf(ResumeBlockType.experience);
    expect(refs, hasLength(1));
    expect(refs.single.blockId, experienceId);
  });

  test('detachBlock() removes the reference from this resume only - the '
      'shared library block and a sibling resume\'s reference survive', () async {
    final resumeIdA = await insertResume(title: 'Resume A');
    final resumeIdB = await insertResume(title: 'Resume B');
    final experienceId = await insertExperience();
    await resumeBlockRepository.attach(resumeIdA, ResumeBlockType.experience, experienceId);
    await resumeBlockRepository.attach(resumeIdB, ResumeBlockType.experience, experienceId);
    await waitForReady(resumeIdA);

    await container
        .read(resumeEditorControllerProvider(resumeIdA).notifier)
        .detachBlock(ResumeBlockType.experience, experienceId);

    expect(readyState(resumeIdA).refsOf(ResumeBlockType.experience), isEmpty);
    expect(await experienceBlockRepository.getById(experienceId), isNotNull);
    expect(await resumeBlockRepository.getForResume(resumeIdB), hasLength(1));
  });

  test('reorderSection() persists the new order, reflected on the next read', () async {
    final resumeId = await insertResume();
    final firstId = await insertExperience(role: 'First');
    final secondId = await insertExperience(role: 'Second');
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, firstId);
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, secondId);
    await waitForReady(resumeId);

    final current = readyState(resumeId).refsOf(ResumeBlockType.experience);
    final reversed = current.reversed.toList();

    await container
        .read(resumeEditorControllerProvider(resumeId).notifier)
        .reorderSection(reversed);

    final reordered = readyState(resumeId).refsOf(ResumeBlockType.experience);
    expect(reordered.first.blockId, current.last.blockId);
    expect(reordered.last.blockId, current.first.blockId);
  });

  test('setBlockOverride() stores a per-resume bullet override without '
      'touching the shared library block, and can be cleared back to null', () async {
    final resumeId = await insertResume();
    final experienceId = await insertExperience();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    await waitForReady(resumeId);
    final notifier = container.read(resumeEditorControllerProvider(resumeId).notifier);

    await notifier.setBlockOverride(
      ResumeBlockType.experience,
      experienceId,
      ['Trimmed bullet only.'],
    );

    var ref = readyState(resumeId).refsOf(ResumeBlockType.experience).single;
    expect(ref.overrideJson, isNotNull);
    expect(ref.overrideJson, contains('Trimmed bullet only.'));
    final block = await experienceBlockRepository.getById(experienceId);
    expect(block!.bullets, ['Did the thing.']);

    await notifier.setBlockOverride(ResumeBlockType.experience, experienceId, null);
    ref = readyState(resumeId).refsOf(ResumeBlockType.experience).single;
    expect(ref.overrideJson, isNull);
  });

  test('saveVersion() compiles the live draft into a new, persisted '
      'ResumeVersion and invalidates the version list', () async {
    final resumeId = await insertResume(fullName: 'Version Test');
    final experienceId = await insertExperience();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    await waitForReady(resumeId);

    final version = await container
        .read(resumeEditorControllerProvider(resumeId).notifier)
        .saveVersion('v1');

    expect(version.versionLabel, 'v1');
    expect(version.compiledSnapshot.profile.fullName, 'Version Test');
    final persisted = await resumeVersionRepository.getForResume(resumeId);
    expect(persisted, hasLength(1));
  });

  test('preview() renders the current live draft directly and never '
      'requires a saved ResumeVersion', () async {
    final resumeId = await insertResume();
    await waitForReady(resumeId);

    // No version has ever been saved for this resume - preview() must
    // still succeed, compiling straight from the in-memory draft.
    expect(await resumeVersionRepository.getForResume(resumeId), isEmpty);

    final bytes = await container
        .read(resumeEditorControllerProvider(resumeId).notifier)
        .preview();

    expect(bytes, isNotEmpty);
  });

  test('preview() reflects an unsaved edit made after the last saved '
      'version, proving it never falls back to reading a version', () async {
    final resumeId = await insertResume();
    final experienceId = await insertExperience();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    await waitForReady(resumeId);
    final notifier = container.read(resumeEditorControllerProvider(resumeId).notifier);

    final savedVersion = await notifier.saveVersion('Before extra block');
    final secondExperienceId = await insertExperience(role: 'Second Role');
    await notifier.attachBlock(ResumeBlockType.experience, secondExperienceId);

    final livePreviewBytes = await notifier.preview();
    final savedVersionBytes =
        await const PwResumePdfExportService().render(savedVersion.compiledSnapshot);

    expect(livePreviewBytes.length, isNot(equals(savedVersionBytes.length)));
  });

  test('preview() renders using the resume\'s own selected template, never silently '
      'falling back to Classic - regression test for a previously-shipped bug where '
      'preview() called render() without passing templateSpec at all, so every '
      'in-app preview silently ignored the user\'s chosen template', () async {
    const selectedTemplateId = 'minimalist-monochrome-cool';
    final resumeId = await insertResume(templateId: selectedTemplateId);
    final experienceId = await insertExperience();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    await waitForReady(resumeId);

    final previewBytes =
        await container.read(resumeEditorControllerProvider(resumeId).notifier).preview();

    final snapshot = await container.read(resumeEditorControllerProvider(resumeId).notifier).compileSnapshot();
    const exportService = PwResumePdfExportService();
    final correctTemplateBytes = await exportService.render(
      snapshot,
      templateSpec: ResumeTemplateCatalog.specById(selectedTemplateId),
    );
    final classicDefaultBytes = await exportService.render(
      snapshot,
      templateSpec: ResumeTemplateCatalog.specById('classic-single-column-warm'),
    );

    // Same length as a direct render with the resume's own actual
    // template - proves preview() is threading the real templateSpec
    // through, not just "some non-default template."
    expect(previewBytes.length, correctTemplateBytes.length);
    // And distinctly different from what silently defaulting to Classic
    // would have produced - the exact symptom of the original bug.
    expect(previewBytes.length, isNot(equals(classicDefaultBytes.length)));
  });

  test('deleteBlockFromLibrary() deletes an unreferenced block via '
      'DeleteLibraryBlockUseCase', () async {
    final resumeId = await insertResume();
    final experienceId = await insertExperience();
    await waitForReady(resumeId);

    await container
        .read(resumeEditorControllerProvider(resumeId).notifier)
        .deleteBlockFromLibrary(ResumeBlockType.experience, experienceId);

    expect(await experienceBlockRepository.getById(experienceId), isNull);
  });

  test('deleteBlockFromLibrary() throws BlockInUseException and leaves the '
      'block intact when this resume still references it', () async {
    final resumeId = await insertResume(title: 'Still Using It');
    final experienceId = await insertExperience();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    await waitForReady(resumeId);

    await expectLater(
      container
          .read(resumeEditorControllerProvider(resumeId).notifier)
          .deleteBlockFromLibrary(ResumeBlockType.experience, experienceId),
      throwsA(isA<BlockInUseException>()),
    );

    expect(await experienceBlockRepository.getById(experienceId), isNotNull);
    expect(readyState(resumeId).actionError, contains('Still Using It'));
  });

  test('family + autoDispose scoping: two different resumeIds never share '
      'state - attaching a block to one leaves the other untouched', () async {
    final resumeIdA = await insertResume(title: 'Resume A');
    final resumeIdB = await insertResume(title: 'Resume B');
    final experienceId = await insertExperience();
    await waitForReady(resumeIdA);
    await waitForReady(resumeIdB);

    await container
        .read(resumeEditorControllerProvider(resumeIdA).notifier)
        .attachBlock(ResumeBlockType.experience, experienceId);

    expect(readyState(resumeIdA).refsOf(ResumeBlockType.experience), hasLength(1));
    expect(readyState(resumeIdB).refsOf(ResumeBlockType.experience), isEmpty);
  });

  test('a repository failure during an action sets a friendly actionError '
      'and clears isSaving, without crashing the controller', () async {
    final resumeId = await insertResume();
    await waitForReady(resumeId);
    final notifier = container.read(resumeEditorControllerProvider(resumeId).notifier);

    // Force a genuine write failure by closing the underlying connection -
    // mirrors the "closed connection" forced-failure trick already used
    // elsewhere in this test suite for cases a real repository can't
    // otherwise be made to fail deterministically.
    await db.close();

    await notifier.attachBlock(ResumeBlockType.experience, 1);

    final state = readyState(resumeId);
    expect(state.isSaving, isFalse);
    expect(state.actionError, isNotNull);
  });
}
