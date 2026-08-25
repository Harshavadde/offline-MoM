// Tests CreateBeginnerResumeUseCase
// (lib/features/career/resume/create_beginner_resume_use_case.dart) - R-10.
// Real Sqflite repositories against a throwaway in-memory database, no
// mocks - mirrors create_resume_from_profile_use_case_test.dart's own
// style.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/create_beginner_resume_use_case.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/career/beginner/role_category.dart';
import 'package:offline_mom/services/career/beginner/role_category_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late EducationBlockRepository educationBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late CertificationBlockRepository certificationBlockRepository;
  late ProjectBlockRepository projectBlockRepository;
  late SkillEntryRepository skillEntryRepository;
  late CustomSectionBlockRepository customSectionBlockRepository;
  late CreateBeginnerResumeUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    educationBlockRepository = SqfliteEducationBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    certificationBlockRepository = SqfliteCertificationBlockRepository(db);
    projectBlockRepository = SqfliteProjectBlockRepository(db);
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    useCase = CreateBeginnerResumeUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      educationBlockRepository: educationBlockRepository,
      experienceBlockRepository: experienceBlockRepository,
      certificationBlockRepository: certificationBlockRepository,
      skillEntryRepository: skillEntryRepository,
      customSectionBlockRepository: customSectionBlockRepository,
    );
  });

  tearDown(() => db.close());

  test('minimum input (name + role only) still creates a real, usable resume', () async {
    final resumeId = await useCase(
      const BeginnerResumeInput(
        fullName: 'Asha Rao',
        roleCategory: RoleCategoryCatalog.salesExecutive,
      ),
    );

    final resume = (await resumeRepository.getById(resumeId))!;
    expect(resume.fullName, 'Asha Rao');
    expect(resume.targetRole, 'Sales Executive');
    expect(resume.isProfile, isFalse);

    final refs = await resumeBlockRepository.getForResume(resumeId);
    // Only the Professional Summary custom section - no education (no
    // degree given), no experience, no skills, no certifications, no
    // languages.
    expect(refs, hasLength(1));
    expect(refs.single.blockType, ResumeBlockType.customSection);

    final summary = await customSectionBlockRepository.getById(refs.single.blockId);
    expect(summary!.title, 'Professional Summary');
    expect(summary.entries.single, contains('sales and customer relationship-building'));
    // Never claims a degree that was never given.
    expect(summary.entries.single, isNot(contains('graduate')));
  });

  test('a degree creates a real Education block; leaving it blank creates none', () async {
    final withDegree = await useCase(
      const BeginnerResumeInput(
        fullName: 'Ravi Kumar',
        roleCategory: RoleCategoryCatalog.dataEntryOperator,
        degree: 'B.Com',
        institution: 'Delhi University',
        graduationYear: '2024',
      ),
    );
    final refsWithDegree = await resumeBlockRepository.getForResume(withDegree);
    final educationRef = refsWithDegree.singleWhere((r) => r.blockType == ResumeBlockType.education);
    final education = await educationBlockRepository.getById(educationRef.blockId);
    expect(education!.degree, 'B.Com');
    expect(education.institution, 'Delhi University');

    final withoutDegree = await useCase(
      const BeginnerResumeInput(
        fullName: 'Priya Singh',
        roleCategory: RoleCategoryCatalog.dataEntryOperator,
      ),
    );
    final refsWithoutDegree = await resumeBlockRepository.getForResume(withoutDegree);
    expect(refsWithoutDegree.where((r) => r.blockType == ResumeBlockType.education), isEmpty);
  });

  group('no fabrication', () {
    test('no experience given -> no Experience block is ever created', () async {
      final resumeId = await useCase(
        const BeginnerResumeInput(
          fullName: 'Neha Verma',
          roleCategory: RoleCategoryCatalog.customerSupportExecutive,
          experienceEntries: [],
        ),
      );
      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.where((r) => r.blockType == ResumeBlockType.experience), isEmpty);
      final summary = await customSectionBlockRepository
          .getById(refs.singleWhere((r) => r.blockType == ResumeBlockType.customSection).blockId);
      expect(summary!.entries.single, isNot(contains('practical experience')));
    });

    test('a blank experience entry (both fields empty) is silently skipped, not stored', () async {
      final resumeId = await useCase(
        const BeginnerResumeInput(
          fullName: 'Karan Mehta',
          roleCategory: RoleCategoryCatalog.retailExecutive,
          experienceEntries: [BeginnerExperienceEntryInput(title: '', organization: '')],
        ),
      );
      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.where((r) => r.blockType == ResumeBlockType.experience), isEmpty);
    });

    test('a real experience entry is stored exactly as given, and the summary mentions it '
        'only generically - never inventing specifics', () async {
      final resumeId = await useCase(
        const BeginnerResumeInput(
          fullName: 'Divya Nair',
          roleCategory: RoleCategoryCatalog.marketingExecutive,
          experienceEntries: [
            BeginnerExperienceEntryInput(
              title: 'Marketing Intern',
              organization: 'Acme Co',
              when: 'Summer 2023',
              description: 'Helped with social media posts\nAssisted with event coordination',
            ),
          ],
        ),
      );
      final refs = await resumeBlockRepository.getForResume(resumeId);
      final experienceRef = refs.singleWhere((r) => r.blockType == ResumeBlockType.experience);
      final experience = await experienceBlockRepository.getById(experienceRef.blockId);
      expect(experience!.role, 'Marketing Intern');
      expect(experience.company, 'Acme Co');
      expect(experience.startDate, 'Summer 2023');
      expect(experience.bullets, ['Helped with social media posts', 'Assisted with event coordination']);

      final summary = await customSectionBlockRepository
          .getById(refs.singleWhere((r) => r.blockType == ResumeBlockType.customSection).blockId);
      expect(summary!.entries.single, contains('practical experience through internship'));
    });

    test('this use case never creates a Project block under any circumstances - "no projects" '
        'means no fake ones are added to pad the resume', () async {
      final resumeId = await useCase(
        const BeginnerResumeInput(
          fullName: 'Rohit Sharma',
          roleCategory: RoleCategoryCatalog.softwareItFresher,
          degree: 'B.Sc Computer Science',
          experienceEntries: [
            BeginnerExperienceEntryInput(title: 'Trainee', organization: 'Some Co'),
          ],
        ),
      );
      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.where((r) => r.blockType == ResumeBlockType.project), isEmpty);
      expect(await projectBlockRepository.getAll(), isEmpty);
    });

    test('certifications get an honest empty issuer, never an invented organization', () async {
      final resumeId = await useCase(
        const BeginnerResumeInput(
          fullName: 'Anjali Gupta',
          roleCategory: RoleCategoryCatalog.accountsAssistant,
          certifications: ['Tally Certification'],
        ),
      );
      final refs = await resumeBlockRepository.getForResume(resumeId);
      final certRef = refs.singleWhere((r) => r.blockType == ResumeBlockType.certification);
      final cert = await certificationBlockRepository.getById(certRef.blockId);
      expect(cert!.name, 'Tally Certification');
      expect(cert.issuer, isEmpty);
    });
  });

  group('skills - suggested vs. confirmed', () {
    test('only skills explicitly passed as confirmed are attached - a role\'s other suggested '
        'skills the caller did not include are never added on their own', () async {
      final resumeId = await useCase(
        BeginnerResumeInput(
          fullName: 'Sanya Kapoor',
          roleCategory: RoleCategoryCatalog.salesExecutive,
          // Only 2 of Sales Executive's several suggested skills confirmed -
          // simulates the screen already having removed the rest.
          confirmedSkills: RoleCategoryCatalog.salesExecutive.suggestedSkills.take(2).toList(),
        ),
      );
      final refs = await resumeBlockRepository.getForResume(resumeId);
      final skillRefs = refs.where((r) => r.blockType == ResumeBlockType.skill).toList();
      expect(skillRefs, hasLength(2));
    });

    test('a user\'s own typed skill is attached alongside confirmed suggestions', () async {
      final resumeId = await useCase(
        const BeginnerResumeInput(
          fullName: 'Farhan Ali',
          roleCategory: RoleCategoryCatalog.itTechnicalSupport,
          confirmedSkills: [
            SuggestedSkill('Basic troubleshooting', SkillCategory.technical),
            SuggestedSkill('Photoshop', SkillCategory.technical), // user's own, not in the catalog
          ],
        ),
      );
      final refs = await resumeBlockRepository.getForResume(resumeId);
      final skillRefs = refs.where((r) => r.blockType == ResumeBlockType.skill).toList();
      final allSkills = await skillEntryRepository.getAll();
      final skillNames = [
        for (final ref in skillRefs) allSkills.firstWhere((s) => s.id == ref.blockId).name,
      ];
      expect(skillNames, containsAll(['Basic troubleshooting', 'Photoshop']));
    });

    test('reuses an existing skill by case-insensitive name instead of creating a duplicate row',
        () async {
      final first = await useCase(
        const BeginnerResumeInput(
          fullName: 'A',
          roleCategory: RoleCategoryCatalog.generalFresher,
          confirmedSkills: [SuggestedSkill('Communication', SkillCategory.soft)],
        ),
      );
      final second = await useCase(
        const BeginnerResumeInput(
          fullName: 'B',
          roleCategory: RoleCategoryCatalog.generalFresher,
          confirmedSkills: [SuggestedSkill('communication', SkillCategory.soft)],
        ),
      );

      final allSkills = await skillEntryRepository.getAll();
      expect(allSkills.where((s) => s.name.toLowerCase() == 'communication'), hasLength(1));

      final firstRefs = await resumeBlockRepository.getForResume(first);
      final secondRefs = await resumeBlockRepository.getForResume(second);
      final firstSkillId = firstRefs.firstWhere((r) => r.blockType == ResumeBlockType.skill).blockId;
      final secondSkillId = secondRefs.firstWhere((r) => r.blockType == ResumeBlockType.skill).blockId;
      expect(firstSkillId, secondSkillId);
    });
  });

  test('languages are stored via the existing CustomSectionBlock mechanism', () async {
    final resumeId = await useCase(
      const BeginnerResumeInput(
        fullName: 'Meera Iyer',
        roleCategory: RoleCategoryCatalog.hrRecruitmentAssistant,
        languages: ['English', 'Hindi'],
      ),
    );
    final refs = await resumeBlockRepository.getForResume(resumeId);
    final customSectionRefs = refs.where((r) => r.blockType == ResumeBlockType.customSection).toList();
    // Summary + Languages, both CustomSectionBlock.
    expect(customSectionRefs, hasLength(2));
    final customSections = <String, List<String>>{};
    for (final ref in customSectionRefs) {
      final block = (await customSectionBlockRepository.getById(ref.blockId))!;
      customSections[block.title] = block.entries;
    }
    expect(customSections['Languages'], ['English', 'Hindi']);
  });

  test('achievements are stored on Resume.achievements, never invented if omitted', () async {
    final withAchievement = await useCase(
      const BeginnerResumeInput(
        fullName: 'Ibrahim Khan',
        roleCategory: RoleCategoryCatalog.operationsExecutive,
        achievements: ['College quiz winner'],
      ),
    );
    final resume = (await resumeRepository.getById(withAchievement))!;
    expect(resume.achievements, ['College quiz winner']);

    final withoutAchievement = await useCase(
      const BeginnerResumeInput(fullName: 'Zara Khan', roleCategory: RoleCategoryCatalog.operationsExecutive),
    );
    final resume2 = (await resumeRepository.getById(withoutAchievement))!;
    expect(resume2.achievements, isEmpty);
  });

  test('summaryOverride is stored verbatim instead of the deterministic default - the R-10 §14 '
      'AI-polish hand-off point', () async {
    final resumeId = await useCase(
      const BeginnerResumeInput(
        fullName: 'Ola Benson',
        roleCategory: RoleCategoryCatalog.generalFresher,
        summaryOverride: 'A hand-polished summary the review step produced.',
      ),
    );
    final refs = await resumeBlockRepository.getForResume(resumeId);
    final summary = await customSectionBlockRepository
        .getById(refs.singleWhere((r) => r.blockType == ResumeBlockType.customSection).blockId);
    expect(summary!.entries.single, 'A hand-polished summary the review step produced.');
  });

  test('optional/required fields: only fullName and roleCategory are ever required - every '
      'other field genuinely omittable with no error', () async {
    // Whole point of this test: this call must not throw.
    final resumeId = await useCase(
      const BeginnerResumeInput(fullName: 'Solo Name', roleCategory: RoleCategoryCatalog.generalFresher),
    );
    expect(resumeId, isPositive);
  });
}
