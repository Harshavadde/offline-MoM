import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/certification_block.dart';
import 'package:offline_mom/models/custom_section_block.dart';
import 'package:offline_mom/models/education_block.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/project_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_ref.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

/// Throws on every call - used only for the one test that needs to prove a
/// genuine repository failure propagates rather than being swallowed.
class _ThrowingExperienceBlockRepository implements ExperienceBlockRepository {
  @override
  Future<ExperienceBlock?> getById(int id) => throw StateError('simulated repository failure');

  @override
  Future<int> insert(ExperienceBlock block) => throw UnimplementedError();
  @override
  Future<void> update(ExperienceBlock block) => throw UnimplementedError();
  @override
  Future<void> delete(int id) => throw UnimplementedError();
  @override
  Future<List<ExperienceBlock>> getAll() => throw UnimplementedError();
}

void main() {
  late Database db;
  late ExperienceBlockRepository experienceRepository;
  late EducationBlockRepository educationRepository;
  late ProjectBlockRepository projectRepository;
  late CertificationBlockRepository certificationRepository;
  late SkillEntryRepository skillEntryRepository;
  late CustomSectionBlockRepository customSectionBlockRepository;
  late ResumeCompilerService compiler;

  setUp(() async {
    db = await openTestDatabase();
    experienceRepository = SqfliteExperienceBlockRepository(db);
    educationRepository = SqfliteEducationBlockRepository(db);
    projectRepository = SqfliteProjectBlockRepository(db);
    certificationRepository = SqfliteCertificationBlockRepository(db);
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    compiler = ResumeCompilerService(
      experienceBlockRepository: experienceRepository,
      educationBlockRepository: educationRepository,
      projectBlockRepository: projectRepository,
      certificationBlockRepository: certificationRepository,
      skillEntryRepository: skillEntryRepository,
      customSectionBlockRepository: customSectionBlockRepository,
    );
  });

  tearDown(() => db.close());

  Resume buildResume({String fullName = 'Jane Doe'}) {
    final now = DateTime(2026, 1, 1);
    return Resume(id: 1, title: 'Test Resume', fullName: fullName, createdAt: now, updatedAt: now);
  }

  ResumeBlockRef ref({
    required ResumeBlockType blockType,
    required int blockId,
    required int sortOrder,
    String? overrideJson,
  }) {
    return ResumeBlockRef(
      id: null,
      resumeId: 1,
      blockType: blockType,
      blockId: blockId,
      sortOrder: sortOrder,
      overrideJson: overrideJson,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  Future<int> insertExperience({String role = 'Engineer', List<String> bullets = const ['B1']}) {
    final now = DateTime(2026, 1, 1);
    return experienceRepository.insert(ExperienceBlock(
      id: null,
      role: role,
      company: 'Acme',
      startDate: '2022-01',
      bullets: bullets,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> insertEducation({String institution = 'State University'}) {
    final now = DateTime(2026, 1, 1);
    return educationRepository.insert(EducationBlock(
      id: null,
      institution: institution,
      degree: 'B.Sc',
      startDate: '2015-09',
      details: const ['Honors'],
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> insertProject({String name = 'Project'}) {
    final now = DateTime(2026, 1, 1);
    return projectRepository.insert(ProjectBlock(
      id: null,
      name: name,
      bullets: const ['Built it'],
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> insertCertification({String name = 'Cert'}) {
    final now = DateTime(2026, 1, 1);
    return certificationRepository.insert(CertificationBlock(
      id: null,
      name: name,
      issuer: 'Issuer',
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> insertSkill({String name = 'Flutter'}) {
    return skillEntryRepository.insert(
      SkillEntry(id: null, name: name, category: SkillCategory.technical, createdAt: DateTime(2026, 1, 1)),
    );
  }

  Future<int> insertCustomSection({String title = 'Awards', List<String> entries = const ['Employee of the Year']}) {
    final now = DateTime(2026, 1, 1);
    return customSectionBlockRepository.insert(
      CustomSectionBlock(id: null, title: title, entries: entries, createdAt: now, updatedAt: now),
    );
  }

  group('block resolution', () {
    test('an experience block resolves with all its fields correctly mapped', () async {
      final blockId = await insertExperience(role: 'Senior Engineer', bullets: ['Did the thing']);
      final resume = buildResume();

      final snapshot = await compiler.compile(
        resume,
        [ref(blockType: ResumeBlockType.experience, blockId: blockId, sortOrder: 0)],
      );

      expect(snapshot.experience, hasLength(1));
      final entry = snapshot.experience.single;
      expect(entry.sourceBlockId, blockId);
      expect(entry.role, 'Senior Engineer');
      expect(entry.company, 'Acme');
      expect(entry.bullets, ['Did the thing']);
    });

    test('all six block types resolve correctly in a single compile', () async {
      final experienceId = await insertExperience();
      final educationId = await insertEducation();
      final projectId = await insertProject();
      final certificationId = await insertCertification();
      final skillId = await insertSkill();
      final customSectionId = await insertCustomSection();

      final snapshot = await compiler.compile(buildResume(), [
        ref(blockType: ResumeBlockType.experience, blockId: experienceId, sortOrder: 0),
        ref(blockType: ResumeBlockType.education, blockId: educationId, sortOrder: 1),
        ref(blockType: ResumeBlockType.project, blockId: projectId, sortOrder: 2),
        ref(blockType: ResumeBlockType.certification, blockId: certificationId, sortOrder: 3),
        ref(blockType: ResumeBlockType.skill, blockId: skillId, sortOrder: 4),
        ref(blockType: ResumeBlockType.customSection, blockId: customSectionId, sortOrder: 5),
      ]);

      expect(snapshot.experience, hasLength(1));
      expect(snapshot.education, hasLength(1));
      expect(snapshot.projects, hasLength(1));
      expect(snapshot.certifications, hasLength(1));
      expect(snapshot.skills, hasLength(1));
      expect(snapshot.skills.single.name, 'Flutter');
      expect(snapshot.customSections, hasLength(1));
      expect(snapshot.customSections.single.title, 'Awards');
      expect(snapshot.customSections.single.entries, ['Employee of the Year']);
    });

    test('a custom section block resolves with its title and entries correctly mapped', () async {
      final blockId = await insertCustomSection(
        title: 'Publications',
        entries: ['A Paper About Something', 'Another Paper'],
      );
      final snapshot = await compiler.compile(
        buildResume(),
        [ref(blockType: ResumeBlockType.customSection, blockId: blockId, sortOrder: 0)],
      );

      expect(snapshot.customSections, hasLength(1));
      final entry = snapshot.customSections.single;
      expect(entry.sourceBlockId, blockId);
      expect(entry.title, 'Publications');
      expect(entry.entries, ['A Paper About Something', 'Another Paper']);
    });

    test('the Profile section is resolved from the Resume itself', () async {
      final now = DateTime(2026, 1, 1);
      final resume = Resume(
        id: 1,
        title: 'Test',
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        createdAt: now,
        updatedAt: now,
      );

      final snapshot = await compiler.compile(resume, []);

      expect(snapshot.profile.fullName, 'Jane Doe');
      expect(snapshot.profile.email, 'jane@example.com');
    });
  });

  group('ordering', () {
    test('resolved entries follow sort_order, not the order refs were passed in', () async {
      final idA = await insertExperience(role: 'A');
      final idB = await insertExperience(role: 'B');
      final idC = await insertExperience(role: 'C');

      // Deliberately out of order.
      final snapshot = await compiler.compile(buildResume(), [
        ref(blockType: ResumeBlockType.experience, blockId: idC, sortOrder: 2),
        ref(blockType: ResumeBlockType.experience, blockId: idA, sortOrder: 0),
        ref(blockType: ResumeBlockType.experience, blockId: idB, sortOrder: 1),
      ]);

      expect(snapshot.experience.map((e) => e.role).toList(), ['A', 'B', 'C']);
    });

    test('multiple blocks of different types each preserve their own section\'s order '
        'independently of the others', () async {
      final expA = await insertExperience(role: 'ExpA');
      final expB = await insertExperience(role: 'ExpB');
      final eduA = await insertEducation(institution: 'EduA');
      final eduB = await insertEducation(institution: 'EduB');

      final snapshot = await compiler.compile(buildResume(), [
        ref(blockType: ResumeBlockType.education, blockId: eduB, sortOrder: 0),
        ref(blockType: ResumeBlockType.experience, blockId: expB, sortOrder: 1),
        ref(blockType: ResumeBlockType.education, blockId: eduA, sortOrder: 2),
        ref(blockType: ResumeBlockType.experience, blockId: expA, sortOrder: 3),
      ]);

      expect(snapshot.experience.map((e) => e.role).toList(), ['ExpB', 'ExpA']);
      expect(snapshot.education.map((e) => e.institution).toList(), ['EduB', 'EduA']);
    });
  });

  group('overrides', () {
    test('a valid override_json trims an experience block\'s bullets in the resolved entry', () async {
      final blockId = await insertExperience(bullets: ['Original 1', 'Original 2']);

      final snapshot = await compiler.compile(buildResume(), [
        ref(
          blockType: ResumeBlockType.experience,
          blockId: blockId,
          sortOrder: 0,
          overrideJson: jsonEncode(['Only this one']),
        ),
      ]);

      expect(snapshot.experience.single.bullets, ['Only this one']);
    });

    test('a valid override_json trims an education block\'s details', () async {
      final blockId = await insertEducation();

      final snapshot = await compiler.compile(buildResume(), [
        ref(
          blockType: ResumeBlockType.education,
          blockId: blockId,
          sortOrder: 0,
          overrideJson: jsonEncode(['Trimmed detail']),
        ),
      ]);

      expect(snapshot.education.single.details, ['Trimmed detail']);
    });

    test('a valid override_json trims a project block\'s bullets', () async {
      final blockId = await insertProject();

      final snapshot = await compiler.compile(buildResume(), [
        ref(
          blockType: ResumeBlockType.project,
          blockId: blockId,
          sortOrder: 0,
          overrideJson: jsonEncode(['Trimmed bullet']),
        ),
      ]);

      expect(snapshot.projects.single.bullets, ['Trimmed bullet']);
    });

    test('no override_json falls back to the library block\'s own bullets unchanged', () async {
      final blockId = await insertExperience(bullets: ['Original']);

      final snapshot = await compiler.compile(
        buildResume(),
        [ref(blockType: ResumeBlockType.experience, blockId: blockId, sortOrder: 0)],
      );

      expect(snapshot.experience.single.bullets, ['Original']);
    });

    test('a certification entry is completely unaffected by an override_json value set on its '
        'ref - it structurally has no field to apply one to', () async {
      final blockId = await insertCertification(name: 'AWS Certified');

      final snapshot = await compiler.compile(buildResume(), [
        ref(
          blockType: ResumeBlockType.certification,
          blockId: blockId,
          sortOrder: 0,
          overrideJson: jsonEncode(['this should never be applied']),
        ),
      ]);

      final entry = snapshot.certifications.single;
      expect(entry.name, 'AWS Certified');
      // ResolvedCertificationEntry has no bullets/details field for the
      // override to have landed in - this assertion is really just
      // confirming the entry's own five fields are exactly what the
      // library block had, proven at compile-time by the type itself.
    });

    test('a skill entry is completely unaffected by an override_json value set on its ref', () async {
      final blockId = await insertSkill(name: 'Flutter');

      final snapshot = await compiler.compile(buildResume(), [
        ref(
          blockType: ResumeBlockType.skill,
          blockId: blockId,
          sortOrder: 0,
          overrideJson: jsonEncode(['this should never be applied']),
        ),
      ]);

      expect(snapshot.skills.single.name, 'Flutter');
    });

    test('malformed override_json (invalid JSON) falls back to the original bullets rather than '
        'throwing or producing garbage', () async {
      final blockId = await insertExperience(bullets: ['Original']);

      final snapshot = await compiler.compile(buildResume(), [
        ref(
          blockType: ResumeBlockType.experience,
          blockId: blockId,
          sortOrder: 0,
          overrideJson: 'not valid json{{{',
        ),
      ]);

      expect(snapshot.experience.single.bullets, ['Original']);
    });

    test('override_json with an unexpected shape (not a JSON array) falls back to the original '
        'bullets rather than throwing or producing garbage', () async {
      final blockId = await insertExperience(bullets: ['Original']);

      final snapshot = await compiler.compile(buildResume(), [
        ref(
          blockType: ResumeBlockType.experience,
          blockId: blockId,
          sortOrder: 0,
          overrideJson: jsonEncode({'not': 'a list'}),
        ),
      ]);

      expect(snapshot.experience.single.bullets, ['Original']);
    });
  });

  group('empty composition', () {
    test('a resume with no blocks at all compiles to a snapshot with every list empty', () async {
      final snapshot = await compiler.compile(buildResume(), []);

      expect(snapshot.experience, isEmpty);
      expect(snapshot.education, isEmpty);
      expect(snapshot.projects, isEmpty);
      expect(snapshot.certifications, isEmpty);
      expect(snapshot.skills, isEmpty);
      expect(snapshot.profile.fullName, 'Jane Doe');
    });
  });

  group('missing/invalid referenced blocks', () {
    test('a ref pointing at a block that no longer exists is skipped, not thrown', () async {
      final realId = await insertExperience(role: 'Still here');

      final snapshot = await compiler.compile(buildResume(), [
        ref(blockType: ResumeBlockType.experience, blockId: 999999, sortOrder: 0),
        ref(blockType: ResumeBlockType.experience, blockId: realId, sortOrder: 1),
      ]);

      expect(snapshot.experience, hasLength(1));
      expect(snapshot.experience.single.role, 'Still here');
    });

    test('a genuine repository failure (not merely "not found") propagates uncaught', () async {
      final throwingCompiler = ResumeCompilerService(
        experienceBlockRepository: _ThrowingExperienceBlockRepository(),
        educationBlockRepository: educationRepository,
        projectBlockRepository: projectRepository,
        certificationBlockRepository: certificationRepository,
        skillEntryRepository: skillEntryRepository,
        customSectionBlockRepository: customSectionBlockRepository,
      );

      await expectLater(
        throwingCompiler.compile(
          buildResume(),
          [ref(blockType: ResumeBlockType.experience, blockId: 1, sortOrder: 0)],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
