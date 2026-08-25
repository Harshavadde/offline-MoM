import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/delete_library_block_use_case.dart';
import 'package:offline_mom/models/certification_block.dart';
import 'package:offline_mom/models/education_block.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/project_block.dart';
import 'package:offline_mom/models/resume.dart';
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeBlockRepository resumeBlockRepository;
  late ResumeRepository resumeRepository;
  late ExperienceBlockRepository experienceRepository;
  late EducationBlockRepository educationRepository;
  late ProjectBlockRepository projectRepository;
  late CertificationBlockRepository certificationRepository;
  late SkillEntryRepository skillEntryRepository;
  late CustomSectionBlockRepository customSectionBlockRepository;
  late DeleteLibraryBlockUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    resumeRepository = SqfliteResumeRepository(db);
    experienceRepository = SqfliteExperienceBlockRepository(db);
    educationRepository = SqfliteEducationBlockRepository(db);
    projectRepository = SqfliteProjectBlockRepository(db);
    certificationRepository = SqfliteCertificationBlockRepository(db);
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    useCase = DeleteLibraryBlockUseCase(
      resumeBlockRepository: resumeBlockRepository,
      resumeRepository: resumeRepository,
      experienceBlockRepository: experienceRepository,
      educationBlockRepository: educationRepository,
      projectBlockRepository: projectRepository,
      certificationBlockRepository: certificationRepository,
      skillEntryRepository: skillEntryRepository,
      customSectionBlockRepository: customSectionBlockRepository,
    );
  });

  tearDown(() => db.close());

  Future<int> createResume({String title = 'Backend-Focused'}) {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: title, fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
  }

  Future<int> createExperienceBlock() {
    final now = DateTime(2026, 1, 1);
    return experienceRepository.insert(ExperienceBlock(
      id: null,
      role: 'Engineer',
      company: 'Acme',
      startDate: '2022-01',
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> createEducationBlock() {
    final now = DateTime(2026, 1, 1);
    return educationRepository.insert(EducationBlock(
      id: null,
      institution: 'State University',
      degree: 'B.Sc',
      startDate: '2015-09',
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> createProjectBlock() {
    final now = DateTime(2026, 1, 1);
    return projectRepository.insert(
      ProjectBlock(id: null, name: 'Project', createdAt: now, updatedAt: now),
    );
  }

  Future<int> createCertificationBlock() {
    final now = DateTime(2026, 1, 1);
    return certificationRepository.insert(
      CertificationBlock(id: null, name: 'Cert', issuer: 'Issuer', createdAt: now, updatedAt: now),
    );
  }

  Future<int> createSkillBlock() {
    return skillEntryRepository.insert(
      SkillEntry(id: null, name: 'Flutter', category: SkillCategory.technical, createdAt: DateTime(2026, 1, 1)),
    );
  }

  group('unreferenced blocks delete successfully, for every block type', () {
    test('experience', () async {
      final id = await createExperienceBlock();
      await useCase(ResumeBlockType.experience, id);
      expect(await experienceRepository.getById(id), isNull);
    });

    test('education', () async {
      final id = await createEducationBlock();
      await useCase(ResumeBlockType.education, id);
      expect(await educationRepository.getById(id), isNull);
    });

    test('project', () async {
      final id = await createProjectBlock();
      await useCase(ResumeBlockType.project, id);
      expect(await projectRepository.getById(id), isNull);
    });

    test('certification', () async {
      final id = await createCertificationBlock();
      await useCase(ResumeBlockType.certification, id);
      expect(await certificationRepository.getById(id), isNull);
    });

    test('skill', () async {
      final id = await createSkillBlock();
      await useCase(ResumeBlockType.skill, id);
      expect(await skillEntryRepository.getAll(), isEmpty);
    });
  });

  test('deleting a referenced block throws BlockInUseException naming the referencing resume, '
      'and does not delete the block', () async {
    final blockId = await createExperienceBlock();
    final resumeId = await createResume(title: 'Backend-Focused');
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, blockId);

    await expectLater(
      useCase(ResumeBlockType.experience, blockId),
      throwsA(isA<BlockInUseException>().having(
        (e) => e.resumeTitles,
        'resumeTitles',
        ['Backend-Focused'],
      )),
    );
    expect(await experienceRepository.getById(blockId), isNotNull);
  });

  test('a block referenced by two resumes lists both titles in the exception', () async {
    final blockId = await createExperienceBlock();
    final resumeIdA = await createResume(title: 'Backend-Focused');
    final resumeIdB = await createResume(title: 'Full-Stack');
    await resumeBlockRepository.attach(resumeIdA, ResumeBlockType.experience, blockId);
    await resumeBlockRepository.attach(resumeIdB, ResumeBlockType.experience, blockId);

    await expectLater(
      useCase(ResumeBlockType.experience, blockId),
      throwsA(isA<BlockInUseException>().having(
        (e) => e.resumeTitles.toSet(),
        'resumeTitles',
        {'Backend-Focused', 'Full-Stack'},
      )),
    );
  });

  test('once detached from every resume, a previously-referenced block can be deleted', () async {
    final blockId = await createExperienceBlock();
    final resumeId = await createResume();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, blockId);
    await resumeBlockRepository.detach(resumeId, ResumeBlockType.experience, blockId);

    await useCase(ResumeBlockType.experience, blockId);

    expect(await experienceRepository.getById(blockId), isNull);
  });

  test('deleting one block type never touches the wrong repository', () async {
    final experienceId = await createExperienceBlock();
    final educationId = await createEducationBlock();

    await useCase(ResumeBlockType.experience, experienceId);

    expect(await experienceRepository.getById(experienceId), isNull);
    expect(await educationRepository.getById(educationId), isNotNull);
  });

  test('the same numeric id referenced under one block type does not block deletion of a '
      'different block type using that same id', () async {
    // block_type + block_id together identify a reference - block_id
    // alone is only unique within its own library table, so an
    // experience block and a certification block can validly share the
    // same numeric id without one being mistaken for the other.
    final experienceId = await createExperienceBlock();
    final certificationId = await createCertificationBlock();
    expect(certificationId, isNot(0));
    final resumeId = await createResume();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);

    // Deleting the certification block (unreferenced) must succeed even
    // though an experience block IS referenced - the two are never
    // conflated just because they might share an id space numerically.
    await useCase(ResumeBlockType.certification, certificationId);

    expect(await certificationRepository.getById(certificationId), isNull);
    expect(
      await experienceRepository.getById(experienceId),
      isNotNull,
      reason: 'the referenced experience block must remain untouched and undeleted',
    );
  });
}
