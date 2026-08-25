// Tests ResumeJdAnalysisController through a ProviderContainer with every
// leaf repository provider it transitively reads overridden to a
// throwaway in-memory database - mirrors resume_editor_controller_test.dart's
// exact pattern (this controller reaches the database only through the
// already-tested AnalyzeResumeAgainstJdUseCase/ResumeCompilerService chain).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/analysis/presentation/providers/resume_jd_analysis_providers.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/job_description.dart';
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
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);

    container = ProviderContainer(
      overrides: [
        resumeRepositoryProvider.overrideWithValue(resumeRepository),
        resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
        experienceBlockRepositoryProvider.overrideWithValue(experienceBlockRepository),
        educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
        projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
        certificationBlockRepositoryProvider
            .overrideWithValue(SqfliteCertificationBlockRepository(db)),
        skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
        customSectionBlockRepositoryProvider.overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> insertResume() async {
    final now = DateTime(2026, 1, 1);
    final resumeId = await resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
    final experienceId = await experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: 'Engineer',
      company: 'Acme',
      startDate: '2020-01',
      bullets: const ['Python developer.'],
      createdAt: now,
      updatedAt: now,
    ));
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    return resumeId;
  }

  const jd = ParsedJobDescription(rawText: 'raw', requirements: ['Python']);

  // `resumeJdAnalysisControllerProvider` is `.autoDispose` (by design). A
  // bare `container.read(provider(arg).notifier)` does not keep an
  // autoDispose provider alive across an `await` - without an active
  // listener, Riverpod can dispose and rebuild the provider between the
  // call that starts `analyze()` and the later `container.read()` that
  // checks its result, silently returning a *new* instance still in its
  // initial state. `container.listen(...)`, left open for the test's
  // lifetime, pins the provider alive - the same fix
  // resume_editor_controller_test.dart already applies for the identical
  // reason.
  void pin(ParsedJobDescription jd) {
    container.listen(resumeJdAnalysisControllerProvider(jd), (previous, next) {});
  }

  test('build() starts in ResumeJdAnalysisSelectingResume with the given JD', () {
    pin(jd);
    final state = container.read(resumeJdAnalysisControllerProvider(jd));
    expect(state, isA<ResumeJdAnalysisSelectingResume>());
    expect(state.jd, jd);
  });

  test('analyze() transitions through Running to Succeeded with a real result', () async {
    pin(jd);
    final resumeId = await insertResume();

    await container.read(resumeJdAnalysisControllerProvider(jd).notifier).analyze(resumeId);

    final state = container.read(resumeJdAnalysisControllerProvider(jd));
    expect(state, isA<ResumeJdAnalysisSucceeded>());
    final succeeded = state as ResumeJdAnalysisSucceeded;
    expect(succeeded.resumeId, resumeId);
    expect(succeeded.result.exactSkillMatches, isNotEmpty);
  });

  test('analyze() with an unknown resume id transitions to Failed', () async {
    pin(jd);
    await container.read(resumeJdAnalysisControllerProvider(jd).notifier).analyze(999999);

    final state = container.read(resumeJdAnalysisControllerProvider(jd));
    expect(state, isA<ResumeJdAnalysisFailed>());
  });

  test('reset() returns to SelectingResume with the same JD, allowing retry', () async {
    pin(jd);
    final resumeId = await insertResume();
    final notifier = container.read(resumeJdAnalysisControllerProvider(jd).notifier);
    await notifier.analyze(resumeId);
    expect(container.read(resumeJdAnalysisControllerProvider(jd)), isA<ResumeJdAnalysisSucceeded>());

    notifier.reset();

    final state = container.read(resumeJdAnalysisControllerProvider(jd));
    expect(state, isA<ResumeJdAnalysisSelectingResume>());
    expect(state.jd, jd);
  });

  test('family scoping: two different JD instances never share state', () async {
    const otherJd = ParsedJobDescription(rawText: 'other raw', requirements: ['SQL']);
    pin(jd);
    pin(otherJd);
    final resumeId = await insertResume();

    await container.read(resumeJdAnalysisControllerProvider(jd).notifier).analyze(resumeId);

    expect(container.read(resumeJdAnalysisControllerProvider(jd)), isA<ResumeJdAnalysisSucceeded>());
    expect(container.read(resumeJdAnalysisControllerProvider(otherJd)), isA<ResumeJdAnalysisSelectingResume>());
  });
}
