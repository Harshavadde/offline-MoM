// Beta Product Validation phase - full JD-tailoring workflow, end-to-end,
// against real repositories: My Profile -> Create Resume from Profile ->
// paste/parse a Job Description -> analyze -> generate suggestions ->
// accept one and reject another -> verify My Profile is completely
// unchanged at every step, including a simulated "reopen the app" (a fresh
// read straight from the database, never anything cached in memory).
//
// The existing "My Profile protection" groups in
// generate_resume_suggestions_use_case_test.dart and
// accept_suggested_edit_use_case_test.dart only prove a use case refuses to
// act *directly on* a profile resume. This file proves the more subtle
// case Product Validation actually cares about: the profile and a resume
// derived from it share the exact same underlying library blocks (the
// polymorphic ResumeBlockRef architecture never duplicates library data -
// see CreateResumeFromProfileUseCase's own doc comment) - tailoring the
// derived resume must never leak back into the profile's own
// ResumeBlockRef row, the shared library block row, or the profile's own
// compiled ResumeSnapshot.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/analysis/generate_resume_suggestions_use_case.dart';
import 'package:offline_mom/features/career/resume/accept_suggested_edit_use_case.dart' hide CannotTailorProfileException;
import 'package:offline_mom/features/career/resume/create_resume_from_profile_use_case.dart';
import 'package:offline_mom/features/career/resume/reject_suggested_edit_use_case.dart';
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
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';
import 'package:offline_mom/services/career/jd_parser.dart';
import 'package:offline_mom/services/career/resume_jd_analyzer.dart';
import 'package:offline_mom/services/device/device_capability_service.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/fake_ai_engines.dart';
import '../../../test_helpers/test_database.dart';

const _jdText = '''
Cloud Platform Engineer

Requirements:
- Docker orchestration
- Terraform provisioning
- Kubernetes cluster management
''';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late SuggestedEditRepository suggestedEditRepository;
  late ResumeCompilerService compilerService;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    suggestedEditRepository = SqfliteSuggestedEditRepository(db);
    compilerService = ResumeCompilerService(
      experienceBlockRepository: experienceBlockRepository,
      educationBlockRepository: SqfliteEducationBlockRepository(db),
      projectBlockRepository: SqfliteProjectBlockRepository(db),
      certificationBlockRepository: SqfliteCertificationBlockRepository(db),
      skillEntryRepository: SqfliteSkillEntryRepository(db),
      customSectionBlockRepository: SqfliteCustomSectionBlockRepository(db),
    );
  });

  tearDown(() => db.close());

  test(
    'profile -> create resume from profile -> paste a JD -> analyze -> generate suggestions -> '
    'accept one, reject another -> My Profile is untouched, including after a simulated app reopen',
    () async {
      final now = DateTime(2026, 1, 1);

      // 1. My Profile, with two experience bullets that will each become
      // eligible for a suggestion once analyzed against the JD below.
      final profileId = await resumeRepository.insert(Resume(
        id: null,
        title: 'My Profile',
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        isProfile: true,
        createdAt: now,
        updatedAt: now,
      ));
      await resumeRepository.setAsProfile(profileId);

      final dockerExperienceId = await experienceBlockRepository.insert(ExperienceBlock(
        id: null,
        role: 'Backend Engineer',
        company: 'Acme Corp',
        startDate: '2020-01',
        endDate: '2023-01',
        bullets: const ['Deployed services using Docker containers.'],
        createdAt: now,
        updatedAt: now,
      ));
      await resumeBlockRepository.attach(profileId, ResumeBlockType.experience, dockerExperienceId);

      final terraformExperienceId = await experienceBlockRepository.insert(ExperienceBlock(
        id: null,
        role: 'Platform Engineer',
        company: 'Acme Corp',
        startDate: '2018-01',
        endDate: '2020-01',
        bullets: const ['Wrote Terraform scripts for provisioning.'],
        createdAt: now,
        updatedAt: now,
      ));
      await resumeBlockRepository.attach(profileId, ResumeBlockType.experience, terraformExperienceId);

      // 2. "Create Resume from Profile" - both blocks are shared, not
      // duplicated: the derived resume's ResumeBlockRef rows point at the
      // exact same experience_blocks rows as the profile's own refs.
      final profileRefs = await resumeBlockRepository.getForResume(profileId);
      final createResumeFromProfile = CreateResumeFromProfileUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
      );
      final derivedResumeId = await createResumeFromProfile(
        title: 'Tailored for Cloud Platform Role',
        selectedRefs: profileRefs,
      );

      // 3. Paste and parse a real Job Description.
      final jd = const JdParser().parse(_jdText);
      expect(jd.requirements, hasLength(3));

      // 4. Analyze the DERIVED resume (never the profile) against the JD.
      const analyzer = ResumeJdAnalyzer();
      final derivedRefs = await resumeBlockRepository.getForResume(derivedResumeId);
      final derivedResume = (await resumeRepository.getById(derivedResumeId))!;
      final derivedSnapshotBeforeTailoring = await compilerService.compile(derivedResume, derivedRefs);
      final analysis = await analyzer.analyze(derivedSnapshotBeforeTailoring, jd);
      expect(analysis.partialSkillMatches, isNotEmpty, reason: 'the Docker/Terraform bullets should partially match');
      expect(
        analysis.missingSkillMatches.any((m) => m.jdRequirement.contains('Kubernetes')),
        isTrue,
        reason: 'the profile genuinely has no Kubernetes experience - the analyzer must say so, not invent it',
      );

      // 5. Generate suggestions for the derived resume.
      final generateSuggestions = GenerateResumeSuggestionsUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
        compilerService: compilerService,
        analyzer: analyzer,
        llmEngine: FakeLlmEngine(
          responseFromPrompt: (system, user) => user.contains('Docker')
              ? 'Orchestrated Docker container deployments across a multi-region cluster.'
              : 'Provisioned cloud infrastructure using Terraform modules.',
        ),
        llmRequestQueue: DefaultLlmRequestQueue(),
        suggestedEditRepository: suggestedEditRepository,
        deviceCapabilityService: FakeDeviceCapabilityService(ramMb: 8000),
        modelLifecycleManager: ModelLifecycleManager(),
      );
      final suggestions = await generateSuggestions.call(derivedResumeId, jd);
      expect(suggestions, hasLength(2), reason: 'both the Docker and Terraform bullets are partial matches');
      final dockerSuggestion = suggestions.firstWhere((s) => s.targetBlockId == dockerExperienceId);
      final terraformSuggestion = suggestions.firstWhere((s) => s.targetBlockId == terraformExperienceId);

      // 6. Accept one suggestion, reject the other - both scoped to the
      // derived resume only.
      final acceptEdit = AcceptSuggestedEditUseCase(
        suggestedEditRepository: suggestedEditRepository,
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
        compilerService: compilerService,
      );
      final rejectEdit = RejectSuggestedEditUseCase(suggestedEditRepository: suggestedEditRepository);

      final accepted = await acceptEdit.call(dockerSuggestion.id!);
      expect(accepted.status, SuggestedEditStatus.accepted);
      final rejected = await rejectEdit.call(terraformSuggestion.id!);
      expect(rejected.status, SuggestedEditStatus.rejected);

      // 7. The derived resume's own bullet DID change for the accepted
      // suggestion, and did NOT change for the rejected one - tailoring
      // genuinely happened where it was supposed to.
      final derivedRefsAfter = await resumeBlockRepository.getForResume(derivedResumeId);
      final derivedResumeAfter = (await resumeRepository.getById(derivedResumeId))!;
      final derivedSnapshotAfter = await compilerService.compile(derivedResumeAfter, derivedRefsAfter);
      final dockerEntryAfter =
          derivedSnapshotAfter.experience.firstWhere((e) => e.sourceBlockId == dockerExperienceId);
      final terraformEntryAfter =
          derivedSnapshotAfter.experience.firstWhere((e) => e.sourceBlockId == terraformExperienceId);
      expect(dockerEntryAfter.bullets, ['Orchestrated Docker container deployments across a multi-region cluster.']);
      expect(
        terraformEntryAfter.bullets,
        ['Wrote Terraform scripts for provisioning.'],
        reason: 'the rejected suggestion must leave the derived resume\'s own bullet untouched too',
      );

      // 8. THE CRUX: My Profile must be completely unaffected by any of
      // this, even though it shares the exact same two library blocks.
      final profileRefsAfter = await resumeBlockRepository.getForResume(profileId);
      for (final ref in profileRefsAfter) {
        expect(
          ref.overrideJson,
          isNull,
          reason: 'the profile\'s own ResumeBlockRef row is a different row from the derived resume\'s - '
              'accepting an edit on the derived resume must never set an override on the profile\'s row',
        );
      }
      final dockerBlockAfter = await experienceBlockRepository.getById(dockerExperienceId);
      expect(
        dockerBlockAfter!.bullets,
        ['Deployed services using Docker containers.'],
        reason: 'the shared library block itself must never be mutated - only a per-resume override may change',
      );

      final profileAfter = (await resumeRepository.getById(profileId))!;
      expect(profileAfter.fullName, 'Jane Doe');
      expect(profileAfter.email, 'jane@example.com');
      expect(profileAfter.updatedAt, now, reason: 'nothing about the profile row itself was ever re-saved');

      // 9. Simulate reopening the app: a completely fresh read straight
      // from the database (nothing here is an in-memory reference carried
      // over from any step above) must still show the profile's original
      // content, never the tailored/accepted rewrite.
      final reopenedProfile = (await resumeRepository.getById(profileId))!;
      final reopenedProfileRefs = await resumeBlockRepository.getForResume(profileId);
      final reopenedProfileSnapshot = await compilerService.compile(reopenedProfile, reopenedProfileRefs);
      final reopenedDockerEntry =
          reopenedProfileSnapshot.experience.firstWhere((e) => e.sourceBlockId == dockerExperienceId);
      final reopenedTerraformEntry =
          reopenedProfileSnapshot.experience.firstWhere((e) => e.sourceBlockId == terraformExperienceId);
      expect(
        reopenedDockerEntry.bullets,
        ['Deployed services using Docker containers.'],
        reason: 'reopening the app and recompiling My Profile must never show the tailored/accepted text',
      );
      expect(reopenedTerraformEntry.bullets, ['Wrote Terraform scripts for provisioning.']);
    },
  );

  test('generating suggestions directly against My Profile itself is refused outright - the guard this whole '
      'workflow depends on', () async {
    final now = DateTime(2026, 1, 1);
    final profileId = await resumeRepository.insert(Resume(
      id: null,
      title: 'My Profile',
      fullName: 'Jane Doe',
      isProfile: true,
      createdAt: now,
      updatedAt: now,
    ));
    await resumeRepository.setAsProfile(profileId);
    final experienceId = await experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: 'Backend Engineer',
      company: 'Acme Corp',
      startDate: '2020-01',
      bullets: const ['Deployed services using Docker containers.'],
      createdAt: now,
      updatedAt: now,
    ));
    await resumeBlockRepository.attach(profileId, ResumeBlockType.experience, experienceId);

    final generateSuggestions = GenerateResumeSuggestionsUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      compilerService: compilerService,
      analyzer: const ResumeJdAnalyzer(),
      llmEngine: FakeLlmEngine(answer: 'Orchestrated Docker container deployments.'),
      llmRequestQueue: DefaultLlmRequestQueue(),
      suggestedEditRepository: suggestedEditRepository,
      deviceCapabilityService: FakeDeviceCapabilityService(ramMb: 8000),
      modelLifecycleManager: ModelLifecycleManager(),
    );

    await expectLater(
      generateSuggestions.call(profileId, const JdParser().parse(_jdText)),
      throwsA(isA<CannotTailorProfileException>()),
    );
  });
}
