// Tests GenerateResumeSuggestionsUseCase against real repositories
// (openTestDatabase()), the real ResumeCompilerService/ResumeJdAnalyzer,
// and a FakeLlmEngine - mirrors analyze_resume_against_jd_use_case_test.dart's
// precedent for composing real repositories with a real compiler rather
// than mocking either, plus the established fake-AI-engine pattern for the
// one genuinely external dependency (the model).
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/analysis/generate_resume_suggestions_use_case.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/job_description.dart';
import 'package:offline_mom/models/project_block.dart';
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
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';
import 'package:offline_mom/services/career/resume_jd_analyzer.dart';
import 'package:offline_mom/services/device/device_capability_service.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/fake_ai_engines.dart';
import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late ProjectBlockRepository projectBlockRepository;
  late SuggestedEditRepository suggestedEditRepository;
  late ResumeCompilerService compilerService;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    projectBlockRepository = SqfliteProjectBlockRepository(db);
    suggestedEditRepository = SqfliteSuggestedEditRepository(db);
    compilerService = ResumeCompilerService(
      experienceBlockRepository: experienceBlockRepository,
      educationBlockRepository: SqfliteEducationBlockRepository(db),
      projectBlockRepository: projectBlockRepository,
      certificationBlockRepository: SqfliteCertificationBlockRepository(db),
      skillEntryRepository: SqfliteSkillEntryRepository(db),
      customSectionBlockRepository: SqfliteCustomSectionBlockRepository(db),
    );
  });

  tearDown(() => db.close());

  GenerateResumeSuggestionsUseCase buildUseCase({
    String? answer,
    Object? errorToThrow,
    int? deviceRamMb,
  }) {
    return GenerateResumeSuggestionsUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      compilerService: compilerService,
      analyzer: const ResumeJdAnalyzer(),
      llmEngine: FakeLlmEngine(answer: answer, errorToThrow: errorToThrow),
      llmRequestQueue: DefaultLlmRequestQueue(),
      suggestedEditRepository: suggestedEditRepository,
      // Defaults to a high-RAM device so every pre-existing test in this
      // file keeps its exact original behavior - the RAM-sequencing tests
      // below are the only ones that pass a low/unknown deviceRamMb.
      deviceCapabilityService: FakeDeviceCapabilityService(ramMb: deviceRamMb ?? 8000),
      modelLifecycleManager: ModelLifecycleManager(),
    );
  }

  Future<int> insertResumeWithExperienceBullet(String bullet) async {
    final now = DateTime(2026, 1, 1);
    final resumeId = await resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
    final experienceId = await experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: 'Backend Engineer',
      company: 'Acme Corp',
      startDate: '2020-01',
      endDate: '2023-01',
      bullets: [bullet],
      createdAt: now,
      updatedAt: now,
    ));
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    return resumeId;
  }

  ParsedJobDescription buildJd({List<String> requirements = const ['Docker orchestration']}) {
    return ParsedJobDescription(rawText: 'raw', requirements: requirements);
  }

  group('valid structured output', () {
    test('a partial-match entry produces a persisted, correctly-populated pending suggestion', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final useCase = buildUseCase(answer: 'Orchestrated Docker container deployments.');

      final created = await useCase.call(resumeId, buildJd());

      expect(created, hasLength(1));
      final edit = created.single;
      expect(edit.id, isNotNull);
      expect(edit.resumeId, resumeId);
      expect(edit.targetBlockType, ResumeBlockType.experience);
      expect(edit.fieldName, 'bullets');
      expect(edit.originalValue, 'Deployed services using Docker containers.');
      expect(edit.suggestedValue, 'Orchestrated Docker container deployments.');
      expect(edit.sourceRequirement, 'Docker orchestration');
      expect(edit.status, SuggestedEditStatus.pending);
      expect(edit.resolvedAt, isNull);
    });

    test('an exact-match-only entry (no partial match) produces no suggestion', () async {
      final resumeId = await insertResumeWithExperienceBullet('Docker orchestration expert.');

      final created = await buildUseCase(answer: 'Anything').call(
        resumeId,
        buildJd(requirements: const ['Docker orchestration']),
      );

      // "Docker orchestration" appears verbatim - an exact match, not
      // partial - so nothing is bounded-scope-eligible for a rewrite.
      expect(created, isEmpty);
    });
  });

  group(
    'Part H (JD tailoring re-verification): sub-project scope boundary '
    '(D-M9-01)',
    () {
      test(
        'a partial match whose only evidence is a sub-project bullet produces no suggestion for '
        "that entry - sub-projects have no write-back path through SuggestedEdit's override "
        'mechanism, so generating one here would create an edit with no safe way to apply on accept',
        () async {
          final now = DateTime(2026, 1, 1);
          final resumeId = await resumeRepository.insert(
            Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
          );
          final experienceId = await experienceBlockRepository.insert(ExperienceBlock(
            id: null,
            role: 'Software Engineer',
            company: 'Acme Corp',
            startDate: '2020-01',
            endDate: '2023-01',
            bullets: const ['Led the platform team.'],
            subProjects: const [
              ExperienceSubProject(name: 'SciLab', bullets: ['Worked with Azure services.']),
            ],
            createdAt: now,
            updatedAt: now,
          ));
          await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);

          final created = await buildUseCase(answer: 'Anything').call(
            resumeId,
            buildJd(requirements: const ['Azure DevOps']),
          );

          expect(created, isEmpty);
        },
      );
    },
  );

  group('malformed output', () {
    test('an empty model response produces no suggestion, never a crash', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');

      final created = await buildUseCase(answer: '').call(resumeId, buildJd());

      expect(created, isEmpty);
    });

    test('a whitespace-only model response produces no suggestion', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');

      final created = await buildUseCase(answer: '   \n  \n').call(resumeId, buildJd());

      expect(created, isEmpty);
    });

    test('a model response identical to the original text produces no suggestion - nothing to '
        'propose', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');

      final created =
          await buildUseCase(answer: 'Deployed services using Docker containers.').call(
        resumeId,
        buildJd(),
      );

      expect(created, isEmpty);
    });
  });

  group('model unavailable', () {
    test('a model-load failure produces zero suggestions rather than throwing (AC3-05 graceful '
        'degradation)', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final useCase = buildUseCase(errorToThrow: StateError('model not downloaded'));

      final created = await useCase.call(resumeId, buildJd());

      expect(created, isEmpty);
    });
  });

  group('generation failure', () {
    test('a mid-generation failure (e.g. a stall timeout) produces zero suggestions rather than '
        'throwing', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final useCase = buildUseCase(errorToThrow: Exception('generation stalled'));

      final created = await useCase.call(resumeId, buildJd());

      expect(created, isEmpty);
    });
  });

  group('fabricated suggestion', () {
    test('a suggestion introducing unsupported new content is still persisted - the fabrication '
        'guard is a review-time flag (AC3-03/D-08), never a generation-time filter', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      // The model introduces "Kubernetes" and "40%" - neither present in
      // the original bullet.
      final useCase =
          buildUseCase(answer: 'Orchestrated Kubernetes deployments, improving uptime by 40%.');

      final created = await useCase.call(resumeId, buildJd());

      expect(created, hasLength(1));
      expect(created.single.suggestedValue, contains('Kubernetes'));
    });
  });

  group('multiple suggestions', () {
    test('two independently-eligible entries each produce their own suggestion', () async {
      final now = DateTime(2026, 1, 1);
      final resumeId = await resumeRepository.insert(
        Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
      );
      final experienceId = await experienceBlockRepository.insert(ExperienceBlock(
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
      final projectId = await projectBlockRepository.insert(ProjectBlock(
        id: null,
        name: 'Internal Tooling',
        bullets: const ['Built a CLI using Python scripting.'],
        createdAt: now,
        updatedAt: now,
      ));
      await resumeBlockRepository.attach(resumeId, ResumeBlockType.project, projectId);

      final useCase = buildUseCase(answer: 'A rewritten bullet with different wording.');
      final created = await useCase.call(
        resumeId,
        buildJd(requirements: const ['Docker orchestration', 'Python automation scripting']),
      );

      expect(created, hasLength(2));
      expect(created.map((e) => e.targetBlockType), containsAll([
        ResumeBlockType.experience,
        ResumeBlockType.project,
      ]));
    });
  });

  group('persistence', () {
    test('a generated suggestion is genuinely persisted - re-fetched independently from the '
        'database, not just returned in-memory', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final useCase = buildUseCase(answer: 'Orchestrated Docker container deployments.');

      final created = await useCase.call(resumeId, buildJd());

      final refetched = await suggestedEditRepository.getById(created.single.id!);
      expect(refetched, isNotNull);
      expect(refetched!.suggestedValue, 'Orchestrated Docker container deployments.');
      expect(refetched.status, SuggestedEditStatus.pending);
    });
  });

  group('resume remains unchanged during generation (AC3-02)', () {
    test('no resume block override is ever set as a side effect of generation - the resume\'s '
        'own live composition is byte-identical before and after', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final refsBefore = await resumeBlockRepository.getForResume(resumeId);
      final useCase = buildUseCase(answer: 'Orchestrated Docker container deployments.');

      await useCase.call(resumeId, buildJd());

      final refsAfter = await resumeBlockRepository.getForResume(resumeId);
      expect(refsAfter, hasLength(refsBefore.length));
      for (var i = 0; i < refsBefore.length; i++) {
        expect(refsAfter[i].overrideJson, refsBefore[i].overrideJson);
        expect(refsAfter[i].overrideJson, isNull);
      }

      final snapshotAfter = await compilerService.compile(
        (await resumeRepository.getById(resumeId))!,
        refsAfter,
      );
      expect(snapshotAfter.experience.single.bullets, ['Deployed services using Docker containers.']);
    });
  });

  group('RAM sequencing on low-tier devices (docs/v3/01-prd.md §13 D-11, RV3-04, Milestone 5)', () {
    test('releases the embedding model before the LLM-backed rewrite pass on a low-RAM device',
        () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final lifecycleManager = ModelLifecycleManager();
      var unloadCalled = false;
      lifecycleManager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalled = true,
        statusOf: () => ModelStatus.loaded,
      );
      final useCase = GenerateResumeSuggestionsUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
        compilerService: compilerService,
        analyzer: const ResumeJdAnalyzer(),
        llmEngine: FakeLlmEngine(answer: 'Orchestrated Docker container deployments.'),
        llmRequestQueue: DefaultLlmRequestQueue(),
        suggestedEditRepository: suggestedEditRepository,
        deviceCapabilityService: FakeDeviceCapabilityService(ramMb: 3000), // low tier
        modelLifecycleManager: lifecycleManager,
      );

      await useCase.call(resumeId, buildJd());

      expect(unloadCalled, isTrue);
    });

    test('does not release the embedding model on a high-RAM device - the existing idle-timeout '
        'is already sufficient there (docs/v3/01-prd.md §13)', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final lifecycleManager = ModelLifecycleManager();
      var unloadCalled = false;
      lifecycleManager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalled = true,
        statusOf: () => ModelStatus.loaded,
      );
      final useCase = GenerateResumeSuggestionsUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
        compilerService: compilerService,
        analyzer: const ResumeJdAnalyzer(),
        llmEngine: FakeLlmEngine(answer: 'Orchestrated Docker container deployments.'),
        llmRequestQueue: DefaultLlmRequestQueue(),
        suggestedEditRepository: suggestedEditRepository,
        deviceCapabilityService: FakeDeviceCapabilityService(ramMb: 8000), // high tier
        modelLifecycleManager: lifecycleManager,
      );

      await useCase.call(resumeId, buildJd());

      expect(unloadCalled, isFalse);
    });

    test('an unknown RAM reading (device read failure) degrades to the low-tier, more-cautious '
        'behavior - releases the embedding model rather than silently skipping it', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final lifecycleManager = ModelLifecycleManager();
      var unloadCalled = false;
      lifecycleManager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalled = true,
        statusOf: () => ModelStatus.loaded,
      );
      final useCase = GenerateResumeSuggestionsUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
        compilerService: compilerService,
        analyzer: const ResumeJdAnalyzer(),
        llmEngine: FakeLlmEngine(answer: 'Orchestrated Docker container deployments.'),
        llmRequestQueue: DefaultLlmRequestQueue(),
        suggestedEditRepository: suggestedEditRepository,
        deviceCapabilityService: FakeDeviceCapabilityService(), // ramMb: null
        modelLifecycleManager: lifecycleManager,
      );

      await useCase.call(resumeId, buildJd());

      expect(unloadCalled, isTrue);
    });

    test('never releases the embedding model while it is still genuinely in use by another '
        'in-flight caller - unmanagedUnload is a safe no-op, never a forced interrupt', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      final lifecycleManager = ModelLifecycleManager();
      var unloadCalled = false;
      lifecycleManager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalled = true,
        statusOf: () => ModelStatus.loaded,
      );
      lifecycleManager.beginUse(ModelKind.embedding); // still in use by another caller
      final useCase = GenerateResumeSuggestionsUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
        compilerService: compilerService,
        analyzer: const ResumeJdAnalyzer(),
        llmEngine: FakeLlmEngine(answer: 'Orchestrated Docker container deployments.'),
        llmRequestQueue: DefaultLlmRequestQueue(),
        suggestedEditRepository: suggestedEditRepository,
        deviceCapabilityService: FakeDeviceCapabilityService(ramMb: 3000), // low tier
        modelLifecycleManager: lifecycleManager,
      );

      await useCase.call(resumeId, buildJd());

      expect(unloadCalled, isFalse);
    });

    test('does not run the sequencing step at all when there is nothing eligible to generate '
        '(requirementByEvidence empty) - never a pointless unload before an early return', () async {
      final resumeId = await insertResumeWithExperienceBullet('Docker orchestration expert.');
      final lifecycleManager = ModelLifecycleManager();
      var unloadCalled = false;
      lifecycleManager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalled = true,
        statusOf: () => ModelStatus.loaded,
      );
      final useCase = GenerateResumeSuggestionsUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
        compilerService: compilerService,
        analyzer: const ResumeJdAnalyzer(),
        llmEngine: FakeLlmEngine(answer: 'Anything'),
        llmRequestQueue: DefaultLlmRequestQueue(),
        suggestedEditRepository: suggestedEditRepository,
        deviceCapabilityService: FakeDeviceCapabilityService(ramMb: 3000), // low tier
        modelLifecycleManager: lifecycleManager,
      );

      // "Docker orchestration" appears verbatim - an exact match only, no
      // partial-match evidence, so call() returns before ever reaching the
      // sequencing step.
      final created = await useCase.call(resumeId, buildJd(requirements: const ['Docker orchestration']));

      expect(created, isEmpty);
      expect(unloadCalled, isFalse);
    });
  });

  group('My Profile protection (Product Validation phase)', () {
    test('generating suggestions for "My Profile" throws CannotTailorProfileException '
        'and persists no SuggestedEdit row', () async {
      final resumeId =
          await insertResumeWithExperienceBullet('Deployed services using Docker containers.');
      await resumeRepository.setAsProfile(resumeId);
      final useCase = buildUseCase(answer: 'Orchestrated Docker container deployments.');

      await expectLater(
        useCase.call(resumeId, buildJd()),
        throwsA(isA<CannotTailorProfileException>()),
      );

      expect(await suggestedEditRepository.getForResume(resumeId), isEmpty);
    });
  });
}
