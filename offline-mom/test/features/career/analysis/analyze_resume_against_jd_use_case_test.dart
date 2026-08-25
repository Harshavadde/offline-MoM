// Tests AnalyzeResumeAgainstJdUseCase against real repositories
// (openTestDatabase()) and the real, unmodified ResumeCompilerService -
// mirrors save_resume_version_use_case_test.dart's precedent for composing
// a real compiler with real repositories rather than mocking either.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/analysis/analyze_resume_against_jd_use_case.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/job_description.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/career/resume_jd_analyzer.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late AnalyzeResumeAgainstJdUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);

    useCase = AnalyzeResumeAgainstJdUseCase(
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
      analyzer: const ResumeJdAnalyzer(),
    );
  });

  tearDown(() => db.close());

  Future<int> insertResumeWithExperience() async {
    final now = DateTime(2026, 1, 1);
    final resumeId = await resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
    final experienceId = await experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: 'Engineer',
      company: 'Acme',
      startDate: '2020-01',
      endDate: '2023-01',
      bullets: const ['Worked with Python and SQL.'],
      createdAt: now,
      updatedAt: now,
    ));
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    return resumeId;
  }

  ParsedJobDescription buildJd() {
    return const ParsedJobDescription(
      rawText: 'raw',
      requirements: ['Python', 'Kubernetes'],
    );
  }

  test('compiles the selected resume via the real ResumeCompilerService and '
      'runs a real, deterministic analysis', () async {
    final resumeId = await insertResumeWithExperience();

    final result = await useCase.call(resumeId, buildJd());

    expect(result.skillMatches, hasLength(2));
    expect(result.exactSkillMatches.single.jdRequirement, 'Python');
    expect(result.missingSkillMatches.single.jdRequirement, 'Kubernetes');
  });

  test('throws ResumeNotFoundForAnalysisException for a deleted/unknown resume id', () async {
    await expectLater(
      useCase.call(999999, buildJd()),
      throwsA(isA<ResumeNotFoundForAnalysisException>()),
    );
  });

  test('never re-reads the database beyond the one selected resume - a '
      'second, unrelated resume\'s data never leaks into the result', () async {
    final resumeId = await insertResumeWithExperience();
    final now = DateTime(2026, 1, 1);
    await resumeRepository.insert(
      Resume(id: null, title: 'Other Resume', fullName: 'John Smith', createdAt: now, updatedAt: now),
    );

    final result = await useCase.call(resumeId, buildJd());

    // Only this resume's own experience (Python) should ever surface as
    // evidence - nothing from the unrelated second resume.
    expect(result.exactSkillMatches.single.resumeEvidence, isNot(contains('John Smith')));
  });
}
