// Tests CreateResumeFromProfileUseCase
// (lib/features/career/resume/create_resume_from_profile_use_case.dart) -
// the "MASTER PROFILE -> CREATE RESUME" step (Product Validation phase,
// docs/v3/implementation/03-decisions.md). Real Sqflite repositories
// against a throwaway in-memory database, no mocks - mirrors
// resume_compiler_service_test.dart's own style.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/create_resume_from_profile_use_case.dart';
import 'package:offline_mom/models/custom_section_block.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/project_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceRepository;
  late ProjectBlockRepository projectRepository;
  late SkillEntryRepository skillEntryRepository;
  late CustomSectionBlockRepository customSectionRepository;
  late CreateResumeFromProfileUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceRepository = SqfliteExperienceBlockRepository(db);
    projectRepository = SqfliteProjectBlockRepository(db);
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    customSectionRepository = SqfliteCustomSectionBlockRepository(db);
    useCase = CreateResumeFromProfileUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
    );
  });

  tearDown(() => db.close());

  Future<int> setUpProfileWithContent() async {
    final now = DateTime(2026, 1, 1);
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

    for (var i = 1; i <= 5; i++) {
      final expId = await experienceRepository.insert(ExperienceBlock(
        id: null,
        role: 'Role $i',
        company: 'Company $i',
        startDate: '2020-01',
        bullets: const ['Did the thing'],
        createdAt: now,
        updatedAt: now,
      ));
      await resumeBlockRepository.attach(profileId, ResumeBlockType.experience, expId);
    }
    for (var i = 1; i <= 5; i++) {
      final projId = await projectRepository.insert(ProjectBlock(
        id: null,
        name: 'Project $i',
        bullets: const ['Built it'],
        createdAt: now,
        updatedAt: now,
      ));
      await resumeBlockRepository.attach(profileId, ResumeBlockType.project, projId);
    }
    for (final name in ['Kubernetes', 'Azure', 'Terraform', 'Docker', 'Jenkins', 'Python']) {
      final skillId =
          await skillEntryRepository.insert(SkillEntry(id: null, name: name, category: SkillCategory.technical, createdAt: now));
      await resumeBlockRepository.attach(profileId, ResumeBlockType.skill, skillId);
    }
    final sectionId = await customSectionRepository.insert(CustomSectionBlock(
      id: null,
      title: 'Awards',
      entries: const ['Employee of the Year'],
      createdAt: now,
      updatedAt: now,
    ));
    await resumeBlockRepository.attach(profileId, ResumeBlockType.customSection, sectionId);

    return profileId;
  }

  test('throws NoProfileException when no profile has been set up yet', () async {
    await expectLater(
      useCase(title: 'New Resume', selectedRefs: const []),
      throwsA(isA<NoProfileException>()),
    );
  });

  test('creates a new, non-profile resume copying the profile Profile fields', () async {
    final profileId = await setUpProfileWithContent();
    final refs = await resumeBlockRepository.getForResume(profileId);

    final newId = await useCase(title: 'DevOps Resume', selectedRefs: refs);
    final newResume = (await resumeRepository.getById(newId))!;

    expect(newResume.id, isNot(profileId));
    expect(newResume.title, 'DevOps Resume');
    expect(newResume.fullName, 'Jane Doe');
    expect(newResume.email, 'jane@example.com');
    expect(newResume.isProfile, isFalse);
  });

  test('selecting every ref preserves ALL projects, ALL skills, and the custom '
      'section - no data disappears', () async {
    final profileId = await setUpProfileWithContent();
    final refs = await resumeBlockRepository.getForResume(profileId);

    final newId = await useCase(title: 'DevOps Resume', selectedRefs: refs);
    final newRefs = await resumeBlockRepository.getForResume(newId);

    expect(newRefs.where((r) => r.blockType == ResumeBlockType.experience), hasLength(5));
    expect(newRefs.where((r) => r.blockType == ResumeBlockType.project), hasLength(5));
    expect(newRefs.where((r) => r.blockType == ResumeBlockType.skill), hasLength(6));
    expect(newRefs.where((r) => r.blockType == ResumeBlockType.customSection), hasLength(1));
  });

  test('a partial selection includes only the chosen blocks - the rest are '
      'simply not attached, never deleted from the profile', () async {
    final profileId = await setUpProfileWithContent();
    final allRefs = await resumeBlockRepository.getForResume(profileId);
    final onlyProjects = allRefs.where((r) => r.blockType == ResumeBlockType.project).toList();

    final newId = await useCase(title: 'Projects Only', selectedRefs: onlyProjects);
    final newRefs = await resumeBlockRepository.getForResume(newId);

    expect(newRefs, hasLength(5));
    expect(newRefs.every((r) => r.blockType == ResumeBlockType.project), isTrue);

    // The profile itself is completely untouched.
    final profileRefsAfter = await resumeBlockRepository.getForResume(profileId);
    expect(profileRefsAfter, hasLength(allRefs.length));
  });

  test('the new resume reuses the SAME underlying blocks as the profile - '
      'not a duplicated copy', () async {
    final profileId = await setUpProfileWithContent();
    final refs = await resumeBlockRepository.getForResume(profileId);

    final newId = await useCase(title: 'DevOps Resume', selectedRefs: refs);
    final newRefs = await resumeBlockRepository.getForResume(newId);

    final profileBlockIds = refs.map((r) => (r.blockType, r.blockId)).toSet();
    final newBlockIds = newRefs.map((r) => (r.blockType, r.blockId)).toSet();
    expect(newBlockIds, profileBlockIds);

    // Confirm no duplicate library rows were created.
    expect(await experienceRepository.getAll(), hasLength(5));
    expect(await projectRepository.getAll(), hasLength(5));
  });

  test('preserves relative order from the profile', () async {
    final profileId = await setUpProfileWithContent();
    final refs = await resumeBlockRepository.getForResume(profileId);
    final projectRefs = refs.where((r) => r.blockType == ResumeBlockType.project).toList();

    final newId = await useCase(title: 'DevOps Resume', selectedRefs: refs);
    final newProjectRefs = (await resumeBlockRepository.getForResume(newId))
        .where((r) => r.blockType == ResumeBlockType.project)
        .toList();

    for (var i = 0; i < projectRefs.length; i++) {
      final originalBlock = await projectRepository.getById(projectRefs[i].blockId);
      final newBlock = await projectRepository.getById(newProjectRefs[i].blockId);
      expect(newBlock!.name, originalBlock!.name);
    }
  });
}
