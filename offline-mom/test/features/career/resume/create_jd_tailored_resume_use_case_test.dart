// Tests CreateJdTailoredResumeUseCase
// (lib/features/career/resume/create_jd_tailored_resume_use_case.dart) -
// AI-Tailored-Resume-from-JD feature. Real Sqflite repositories against a
// throwaway in-memory database, no mocks - mirrors
// create_beginner_resume_use_case_test.dart's own style exactly.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/create_jd_tailored_resume_use_case.dart';
import 'package:offline_mom/models/project_block.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/career/beginner/role_category.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late EducationBlockRepository educationBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late ProjectBlockRepository projectBlockRepository;
  late SkillEntryRepository skillEntryRepository;
  late CustomSectionBlockRepository customSectionBlockRepository;
  late CreateJdTailoredResumeUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    educationBlockRepository = SqfliteEducationBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    projectBlockRepository = SqfliteProjectBlockRepository(db);
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    useCase = CreateJdTailoredResumeUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      educationBlockRepository: educationBlockRepository,
      experienceBlockRepository: experienceBlockRepository,
      projectBlockRepository: projectBlockRepository,
      skillEntryRepository: skillEntryRepository,
      customSectionBlockRepository: customSectionBlockRepository,
    );
  });

  tearDown(() => db.close());

  test('minimum input still creates a real resume with just a summary section', () async {
    final resumeId = await useCase(
      const JdTailoredResumeInput(
        fullName: 'Rahul Kumar',
        targetRoleLabel: 'Data Entry Operator',
        summaryText: 'Motivated candidate seeking to build a career as a Data Entry Operator.',
      ),
    );

    final resume = (await resumeRepository.getById(resumeId))!;
    expect(resume.fullName, 'Rahul Kumar');
    expect(resume.targetRole, 'Data Entry Operator');
    expect(resume.isProfile, isFalse);

    final refs = await resumeBlockRepository.getForResume(resumeId);
    expect(refs, hasLength(1));
    expect(refs.single.blockType, ResumeBlockType.customSection);

    final summary = await customSectionBlockRepository.getById(refs.single.blockId);
    expect(summary!.title, 'Professional Summary');
    expect(summary.entries.single, contains('Data Entry Operator'));
  });

  test('no experience/projects given -> no corresponding blocks are created at all', () async {
    final resumeId = await useCase(
      const JdTailoredResumeInput(
        fullName: 'Rahul Kumar',
        targetRoleLabel: 'Data Entry Operator',
        summaryText: 'Summary.',
      ),
    );

    final refs = await resumeBlockRepository.getForResume(resumeId);
    expect(refs.where((r) => r.blockType == ResumeBlockType.experience), isEmpty);
    expect(refs.where((r) => r.blockType == ResumeBlockType.project), isEmpty);
    expect(refs.where((r) => r.blockType == ResumeBlockType.education), isEmpty);
  });

  group('skills - confirm/reject roundtrip', () {
    test('only accepted skills attach - a rejected recommendation never appears anywhere', () async {
      // The caller (the review screen) is responsible for only including
      // what the user explicitly accepted - this use case just persists
      // exactly what it's given, so passing only "Django" here simulates
      // the user accepting Django but leaving PostgreSQL unaccepted.
      final resumeId = await useCase(
        const JdTailoredResumeInput(
          fullName: 'Rahul Kumar',
          targetRoleLabel: 'Python Developer',
          summaryText: 'Summary.',
          confirmedSkills: [
            SuggestedSkill('Python', SkillCategory.technical),
            SuggestedSkill('Django', SkillCategory.technical),
          ],
        ),
      );

      final refs = await resumeBlockRepository.getForResume(resumeId);
      final skillRefs = refs.where((r) => r.blockType == ResumeBlockType.skill).toList();
      expect(skillRefs, hasLength(2));

      final allSkills = await skillEntryRepository.getAll();
      final attachedSkills = [
        for (final ref in skillRefs) allSkills.firstWhere((s) => s.id == ref.blockId).name,
      ];
      expect(attachedSkills, containsAll(['Python', 'Django']));
      expect(attachedSkills, isNot(contains('PostgreSQL')));
    });

    test('reuses an existing skill library entry by case-insensitive name instead of duplicating', () async {
      await skillEntryRepository.insert(
        SkillEntry(id: null, name: 'python', category: SkillCategory.technical, createdAt: DateTime(2026)),
      );

      await useCase(
        const JdTailoredResumeInput(
          fullName: 'Rahul Kumar',
          targetRoleLabel: 'Python Developer',
          summaryText: 'Summary.',
          confirmedSkills: [SuggestedSkill('Python', SkillCategory.technical)],
        ),
      );

      final allSkills = await skillEntryRepository.getAll();
      expect(allSkills.where((s) => s.name.toLowerCase() == 'python'), hasLength(1));
    });
  });

  group('projects', () {
    test("the user's own existing project persists with status: completed", () async {
      final resumeId = await useCase(
        const JdTailoredResumeInput(
          fullName: 'Rahul Kumar',
          targetRoleLabel: 'Python Developer',
          summaryText: 'Summary.',
          projectEntries: [
            JdTailoredProjectEntryInput(
              name: 'Inventory Tracker',
              bullets: ['Built a small inventory tool'],
              status: ProjectBlockStatus.completed,
            ),
          ],
        ),
      );

      final refs = await resumeBlockRepository.getForResume(resumeId);
      final projectRef = refs.singleWhere((r) => r.blockType == ResumeBlockType.project);
      final project = await projectBlockRepository.getById(projectRef.blockId);
      expect(project!.name, 'Inventory Tracker');
      expect(project.status, ProjectBlockStatus.completed);
    });

    test('a confirmed project idea persists as status: planned with the user-edited bullets, not raw AI text',
        () async {
      final resumeId = await useCase(
        const JdTailoredResumeInput(
          fullName: 'Rahul Kumar',
          targetRoleLabel: 'Python Developer',
          summaryText: 'Summary.',
          projectEntries: [
            JdTailoredProjectEntryInput(
              name: 'Job Application Tracker',
              bullets: ['My own edited plan for this project'],
              status: ProjectBlockStatus.planned,
            ),
          ],
        ),
      );

      final refs = await resumeBlockRepository.getForResume(resumeId);
      final projectRef = refs.singleWhere((r) => r.blockType == ResumeBlockType.project);
      final project = await projectBlockRepository.getById(projectRef.blockId);
      expect(project!.status, ProjectBlockStatus.planned);
      expect(project.bullets.single, 'My own edited plan for this project');
    });

    test('a project idea confirmed as "I\'ve Actually Completed This" persists as status: completed', () async {
      final resumeId = await useCase(
        const JdTailoredResumeInput(
          fullName: 'Rahul Kumar',
          targetRoleLabel: 'Python Developer',
          summaryText: 'Summary.',
          projectEntries: [
            JdTailoredProjectEntryInput(
              name: 'Job Application Tracker',
              bullets: ['What I actually built'],
              status: ProjectBlockStatus.completed,
            ),
          ],
        ),
      );

      final refs = await resumeBlockRepository.getForResume(resumeId);
      final projectRef = refs.singleWhere((r) => r.blockType == ResumeBlockType.project);
      final project = await projectBlockRepository.getById(projectRef.blockId);
      expect(project!.status, ProjectBlockStatus.completed);
    });

    test('an unconfirmed project idea (never passed in) never appears in the resume', () async {
      final resumeId = await useCase(
        const JdTailoredResumeInput(
          fullName: 'Rahul Kumar',
          targetRoleLabel: 'Python Developer',
          summaryText: 'Summary.',
          // No projectEntries at all - simulates the user declining every
          // suggested idea.
        ),
      );

      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.where((r) => r.blockType == ResumeBlockType.project), isEmpty);
    });
  });

  test('an experience entry is only created from real input', () async {
    final resumeId = await useCase(
      const JdTailoredResumeInput(
        fullName: 'Rahul Kumar',
        targetRoleLabel: 'Data Entry Operator',
        summaryText: 'Summary.',
        experienceEntries: [
          JdTailoredExperienceEntryInput(
            title: 'Data Entry Clerk',
            organization: 'Local Shop',
            description: 'Entered data into spreadsheets',
          ),
        ],
      ),
    );

    final refs = await resumeBlockRepository.getForResume(resumeId);
    final experienceRef = refs.singleWhere((r) => r.blockType == ResumeBlockType.experience);
    final experience = await experienceBlockRepository.getById(experienceRef.blockId);
    expect(experience!.role, 'Data Entry Clerk');
    expect(experience.company, 'Local Shop');
  });
}
