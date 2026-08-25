// Tests AcceptSuggestedEditUseCase against real repositories
// (openTestDatabase()) and the real, unmodified ResumeCompilerService -
// mirrors analyze_resume_against_jd_use_case_test.dart's precedent.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/accept_suggested_edit_use_case.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/suggested_edit.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/repositories/suggested_edit_repository.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late SuggestedEditRepository suggestedEditRepository;
  late AcceptSuggestedEditUseCase useCase;
  late int resumeId;
  late int experienceId;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    suggestedEditRepository = SqfliteSuggestedEditRepository(db);

    useCase = AcceptSuggestedEditUseCase(
      suggestedEditRepository: suggestedEditRepository,
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      compilerService: ResumeCompilerService(
        experienceBlockRepository: experienceBlockRepository,
        educationBlockRepository: SqfliteEducationBlockRepository(db),
        projectBlockRepository: SqfliteProjectBlockRepository(db),
        certificationBlockRepository: SqfliteCertificationBlockRepository(db),
        skillEntryRepository: SqfliteSkillEntryRepository(db),
        customSectionBlockRepository: SqfliteCustomSectionBlockRepository(db),
      ),
    );

    final now = DateTime(2026, 1, 1);
    resumeId = await resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
    experienceId = await experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: 'Backend Engineer',
      company: 'Acme Corp',
      startDate: '2020-01',
      endDate: '2023-01',
      bullets: const ['Deployed services using Docker containers.'],
      createdAt: now,
      updatedAt: now,
    ));
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
  });

  tearDown(() => db.close());

  Future<int> insertPendingSuggestion({String originalValue = 'Deployed services using Docker containers.'}) {
    return suggestedEditRepository.insert(
      SuggestedEdit(
        id: null,
        resumeId: resumeId,
        targetBlockType: ResumeBlockType.experience,
        targetBlockId: experienceId,
        fieldName: 'bullets',
        originalValue: originalValue,
        suggestedValue: 'Orchestrated Docker container deployments.',
        sourceRequirement: 'Docker orchestration',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  }

  group('valid suggestion applied', () {
    test('accepting merges the suggested text into the live draft via setOverride, the same '
        'path a manual edit would take', () async {
      final editId = await insertPendingSuggestion();

      await useCase.call(editId);

      final resume = (await resumeRepository.getById(resumeId))!;
      final refs = await resumeBlockRepository.getForResume(resumeId);
      final snapshot = await ResumeCompilerService(
        experienceBlockRepository: experienceBlockRepository,
        educationBlockRepository: SqfliteEducationBlockRepository(db),
        projectBlockRepository: SqfliteProjectBlockRepository(db),
        certificationBlockRepository: SqfliteCertificationBlockRepository(db),
        skillEntryRepository: SqfliteSkillEntryRepository(db),
        customSectionBlockRepository: SqfliteCustomSectionBlockRepository(db),
      ).compile(resume, refs);
      expect(snapshot.experience.single.bullets, ['Orchestrated Docker container deployments.']);
    });

    test('the underlying library block itself is never modified - only a per-resume override is '
        'set', () async {
      final editId = await insertPendingSuggestion();

      await useCase.call(editId);

      final block = await experienceBlockRepository.getById(experienceId);
      expect(block!.bullets, ['Deployed services using Docker containers.']);
    });
  });

  group('correct suggestion state', () {
    test('the returned and persisted suggestion is marked accepted with resolvedAt set', () async {
      final editId = await insertPendingSuggestion();

      final result = await useCase.call(editId);

      expect(result.status, SuggestedEditStatus.accepted);
      expect(result.resolvedAt, isNotNull);
      final refetched = await suggestedEditRepository.getById(editId);
      expect(refetched!.status, SuggestedEditStatus.accepted);
      expect(refetched.resolvedAt, isNotNull);
    });
  });

  group('duplicate acceptance protection', () {
    test('accepting an already-accepted suggestion throws and does not re-apply', () async {
      final editId = await insertPendingSuggestion();
      await useCase.call(editId);

      await expectLater(
        useCase.call(editId),
        throwsA(isA<SuggestedEditNotPendingException>()),
      );
    });
  });

  group('invalid suggestion rejected', () {
    test('an unknown suggestion id throws SuggestedEditNotFoundException', () async {
      await expectLater(
        useCase.call(999999),
        throwsA(isA<SuggestedEditNotFoundException>()),
      );
    });

    test('a suggestion whose target block was detached since generation is no longer applicable',
        () async {
      final editId = await insertPendingSuggestion();
      await resumeBlockRepository.detach(resumeId, ResumeBlockType.experience, experienceId);

      await expectLater(
        useCase.call(editId),
        throwsA(isA<SuggestedEditNoLongerApplicableException>()),
      );
    });

    test('a suggestion whose original content has changed since generation is no longer '
        'applicable - it must not silently overwrite the user\'s newer edit', () async {
      final editId = await insertPendingSuggestion(originalValue: 'A stale, no-longer-current bullet.');

      await expectLater(
        useCase.call(editId),
        throwsA(isA<SuggestedEditNoLongerApplicableException>()),
      );

      // Confirm nothing was applied - the live content is untouched.
      final block = await experienceBlockRepository.getById(experienceId);
      expect(block!.bullets, ['Deployed services using Docker containers.']);
    });

    test('a profile-level suggestion (no target block) is not supported by this milestone and '
        'is rejected as not applicable', () async {
      final editId = await suggestedEditRepository.insert(
        SuggestedEdit(
          id: null,
          resumeId: resumeId,
          fieldName: 'summary',
          originalValue: 'Some profile text.',
          suggestedValue: 'Some rewritten profile text.',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      await expectLater(
        useCase.call(editId),
        throwsA(isA<SuggestedEditNoLongerApplicableException>()),
      );
    });
  });

  group('resume version/persistence behavior', () {
    test('the override survives an independent re-fetch of the resume\'s composition', () async {
      final editId = await insertPendingSuggestion();

      await useCase.call(editId);

      final refetchedRefs = await resumeBlockRepository.getForResume(resumeId);
      final ref = refetchedRefs.single;
      expect(ref.overrideJson, isNotNull);
      expect(jsonDecode(ref.overrideJson!), ['Orchestrated Docker container deployments.']);
    });
  });

  group('My Profile protection (Product Validation phase)', () {
    test('accepting a suggestion targeting "My Profile" throws '
        'CannotTailorProfileException and never writes an override', () async {
      await resumeRepository.setAsProfile(resumeId);
      final editId = await insertPendingSuggestion();

      await expectLater(useCase.call(editId), throwsA(isA<CannotTailorProfileException>()));

      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.single.overrideJson, isNull);
    });
  });
}
