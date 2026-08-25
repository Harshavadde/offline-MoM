import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/save_resume_version_use_case.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_ref.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_version_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:offline_mom/services/resume/resume_pdf_export_service.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

/// Throws on every call - used only for the one test that needs to prove
/// a compiler-stage failure propagates and persists nothing.
class _ThrowingExperienceBlockRepository implements ExperienceBlockRepository {
  @override
  Future<ExperienceBlock?> getById(int id) => throw StateError('simulated compiler failure');
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
  // Post-Milestone-5 visual-quality redesign pass: the renderer now loads
  // the bundled Inter font via rootBundle, which requires the Flutter
  // services binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ExperienceBlockRepository experienceRepository;
  late EducationBlockRepository educationRepository;
  late ProjectBlockRepository projectRepository;
  late CertificationBlockRepository certificationRepository;
  late SkillEntryRepository skillEntryRepository;
  late CustomSectionBlockRepository customSectionBlockRepository;
  late ResumeVersionRepository resumeVersionRepository;
  late ResumeCompilerService compilerService;
  late ResumePdfExportService pdfExportService;
  late Directory tempDir;
  late SaveResumeVersionUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    experienceRepository = SqfliteExperienceBlockRepository(db);
    educationRepository = SqfliteEducationBlockRepository(db);
    projectRepository = SqfliteProjectBlockRepository(db);
    certificationRepository = SqfliteCertificationBlockRepository(db);
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    resumeVersionRepository = SqfliteResumeVersionRepository(db);
    compilerService = ResumeCompilerService(
      experienceBlockRepository: experienceRepository,
      educationBlockRepository: educationRepository,
      projectBlockRepository: projectRepository,
      certificationBlockRepository: certificationRepository,
      skillEntryRepository: skillEntryRepository,
      customSectionBlockRepository: customSectionBlockRepository,
    );
    pdfExportService = const PwResumePdfExportService();
    tempDir = await Directory.systemTemp.createTemp('save_resume_version_test_');
    useCase = SaveResumeVersionUseCase(
      compilerService: compilerService,
      resumeVersionRepository: resumeVersionRepository,
      pdfExportService: pdfExportService,
      outputPathProvider: (ext) async =>
          '${tempDir.path}/resume_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Resume buildResume({int id = 1, String fullName = 'Jane Doe', String? templateId}) {
    final now = DateTime(2026, 1, 1);
    return Resume(
      id: id,
      title: 'Test Resume',
      fullName: fullName,
      templateId: templateId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<int> insertExperience() {
    final now = DateTime(2026, 1, 1);
    return experienceRepository.insert(ExperienceBlock(
      id: null,
      role: 'Engineer',
      company: 'Acme',
      startDate: '2022-01',
      bullets: const ['Did the thing'],
      createdAt: now,
      updatedAt: now,
    ));
  }

  ResumeBlockRef ref(int blockId, {int sortOrder = 0}) {
    return ResumeBlockRef(
      id: null,
      resumeId: 1,
      blockType: ResumeBlockType.experience,
      blockId: blockId,
      sortOrder: sortOrder,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  group('successful save', () {
    test('persists a version and returns it', () async {
      final resume = buildResume();

      final version = await useCase(resume, [], versionLabel: 'v1');

      expect(version.id, isNotNull);
      expect(version.versionLabel, 'v1');
      expect(version.resumeId, 1);
      final stored = await resumeVersionRepository.getById(version.id!);
      expect(stored, isNotNull);
    });

    test('the persisted compiledSnapshot correctly reflects the resolved composition', () async {
      final blockId = await insertExperience();
      final resume = buildResume(fullName: 'Jane Doe');

      final version = await useCase(resume, [ref(blockId)], versionLabel: 'v1');

      expect(version.compiledSnapshot.profile.fullName, 'Jane Doe');
      expect(version.compiledSnapshot.experience, hasLength(1));
      expect(version.compiledSnapshot.experience.single.role, 'Engineer');
    });

    test('exportedPdfPath is set to a real, existing file only after export succeeds', () async {
      final resume = buildResume();

      final version = await useCase(resume, [], versionLabel: 'v1');

      expect(version.exportedPdfPath, isNotNull);
      expect(await File(version.exportedPdfPath!).exists(), isTrue);
    });

    test('the persisted row (re-fetched independently) also has exportedPdfPath set - the '
        'update genuinely reached the database, not just the in-memory return value', () async {
      final resume = buildResume();

      final version = await useCase(resume, [], versionLabel: 'v1');

      final refetched = await resumeVersionRepository.getById(version.id!);
      expect(refetched!.exportedPdfPath, version.exportedPdfPath);
    });
  });

  group('templateId threading (V3 Milestone 1, docs/v3/01-prd.md §16/§25)', () {
    test('a resume with no templateId persists a version tagged with the catalog default '
        '(Classic Single-Column - Warm)', () async {
      final resume = buildResume(templateId: null);

      final version = await useCase(resume, [], versionLabel: 'v1');

      expect(version.templateId, ResumeTemplateCatalog.defaultSpec.id);
    });

    test('a resume with an explicit templateId persists a version tagged with that exact template', () async {
      final resume = buildResume(templateId: 'compact-technical-cool');

      final version = await useCase(resume, [], versionLabel: 'v1');

      expect(version.templateId, 'compact-technical-cool');
    });

    test('a resume with an unrecognized templateId persists a version tagged with the catalog '
        'default rather than throwing or persisting the bogus id verbatim', () async {
      final resume = buildResume(templateId: 'not-a-real-template');

      final version = await useCase(resume, [], versionLabel: 'v1');

      expect(version.templateId, ResumeTemplateCatalog.defaultSpec.id);
    });

    test('the persisted templateId is also present on the row re-fetched independently from '
        'the database, not just the in-memory return value', () async {
      final resume = buildResume(templateId: 'modern-accent-column-cool');

      final version = await useCase(resume, [], versionLabel: 'v1');

      final refetched = await resumeVersionRepository.getById(version.id!);
      expect(refetched!.templateId, 'modern-accent-column-cool');
    });
  });

  group('compiler failure', () {
    test('propagates uncaught and persists no version', () async {
      final throwingCompiler = ResumeCompilerService(
        experienceBlockRepository: _ThrowingExperienceBlockRepository(),
        educationBlockRepository: educationRepository,
        projectBlockRepository: projectRepository,
        certificationBlockRepository: certificationRepository,
        skillEntryRepository: skillEntryRepository,
        customSectionBlockRepository: customSectionBlockRepository,
      );
      final throwingUseCase = SaveResumeVersionUseCase(
        compilerService: throwingCompiler,
        resumeVersionRepository: resumeVersionRepository,
        pdfExportService: pdfExportService,
        outputPathProvider: (ext) async => '${tempDir.path}/x.$ext',
      );
      final resume = buildResume();

      await expectLater(
        throwingUseCase(resume, [ref(1)], versionLabel: 'v1'),
        throwsA(isA<StateError>()),
      );
      expect(await resumeVersionRepository.getForResume(1), isEmpty);
    });
  });

  group('repository persistence failure', () {
    test('an insert failure propagates and no PDF is exported', () async {
      // A closed connection is a genuine, real failure - not a fake -
      // every subsequent repository call against it throws.
      await db.close();
      final resume = buildResume();

      await expectLater(
        useCase(resume, [], versionLabel: 'v1'),
        throwsA(anything),
      );

      // Nothing in tempDir should have been written, since insert() never
      // succeeded and export is never reached.
      expect(await tempDir.list().toList(), isEmpty);
    });
  });

  group('PDF export failure after successful persistence', () {
    test('the version remains persisted, with exportedPdfPath left null, and the failure '
        'propagates to the caller', () async {
      // Force a real export failure: the "directory" the destination
      // lives in is actually an existing file.
      final blockerPath = '${tempDir.path}/blocker';
      await File(blockerPath).writeAsString('not a directory');
      final failingUseCase = SaveResumeVersionUseCase(
        compilerService: compilerService,
        resumeVersionRepository: resumeVersionRepository,
        pdfExportService: pdfExportService,
        outputPathProvider: (ext) async => '$blockerPath/resume.$ext',
      );
      final resume = buildResume();

      await expectLater(
        failingUseCase(resume, [], versionLabel: 'v1'),
        throwsA(anything),
      );

      final versions = await resumeVersionRepository.getForResume(1);
      expect(versions, hasLength(1), reason: 'the version must remain persisted despite the export failure');
      expect(versions.single.exportedPdfPath, isNull);
      expect(versions.single.versionLabel, 'v1');
    });

    test('a second, successful save for the same resume still works after a prior export '
        'failure - the failed attempt does not corrupt subsequent saves', () async {
      final blockerPath = '${tempDir.path}/blocker';
      await File(blockerPath).writeAsString('not a directory');
      final failingUseCase = SaveResumeVersionUseCase(
        compilerService: compilerService,
        resumeVersionRepository: resumeVersionRepository,
        pdfExportService: pdfExportService,
        outputPathProvider: (ext) async => '$blockerPath/resume.$ext',
      );
      final resume = buildResume();
      await expectLater(failingUseCase(resume, [], versionLabel: 'failed'), throwsA(anything));

      final version = await useCase(resume, [], versionLabel: 'succeeded');

      expect(version.exportedPdfPath, isNotNull);
      final versions = await resumeVersionRepository.getForResume(1);
      expect(versions, hasLength(2));
    });
  });
}
