import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/delete_resume_use_case.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/resume_version.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/resume_version_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ResumeVersionRepository resumeVersionRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late DeleteResumeUseCase useCase;
  late Directory tempDir;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    resumeVersionRepository = SqfliteResumeVersionRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    useCase = DeleteResumeUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      resumeVersionRepository: resumeVersionRepository,
    );
    tempDir = await Directory.systemTemp.createTemp('delete_resume_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> createResume({String title = 'Backend-Focused'}) {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: title, fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
  }

  Future<int> createExperienceBlock() {
    final now = DateTime(2026, 1, 1);
    return experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: 'Engineer',
      company: 'Acme',
      startDate: '2022-01',
      bullets: const ['B'],
      createdAt: now,
      updatedAt: now,
    ));
  }

  ResumeSnapshot buildSnapshot(int resumeId) {
    return ResumeSnapshot(
      resumeId: resumeId,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
    );
  }

  Future<int> createVersion(int resumeId, {String? exportedPdfPath}) {
    return resumeVersionRepository.insert(ResumeVersion(
      id: null,
      resumeId: resumeId,
      versionLabel: 'v1',
      compiledSnapshot: buildSnapshot(resumeId),
      exportedPdfPath: exportedPdfPath,
      createdAt: DateTime(2026, 1, 1),
    ));
  }

  test('deleting a resume with no versions removes the resume', () async {
    final resumeId = await createResume();

    await useCase(resumeId);

    expect(await resumeRepository.getById(resumeId), isNull);
  });

  test('deleting a resume with versions removes the resume and every version', () async {
    final resumeId = await createResume();
    await createVersion(resumeId);
    await createVersion(resumeId);

    await useCase(resumeId);

    expect(await resumeRepository.getById(resumeId), isNull);
    expect(await resumeVersionRepository.getForResume(resumeId), isEmpty);
  });

  test('exported PDF files are removed from disk when the resume is deleted', () async {
    final resumeId = await createResume();
    final filePath = '${tempDir.path}/version.pdf';
    await File(filePath).writeAsBytes(utf8.encode('fake pdf bytes'));
    await createVersion(resumeId, exportedPdfPath: filePath);

    await useCase(resumeId);

    expect(await File(filePath).exists(), isFalse);
  });

  test('resume block references (the live composition) are removed', () async {
    final resumeId = await createResume();
    final blockId = await createExperienceBlock();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, blockId);

    await useCase(resumeId);

    expect(await resumeBlockRepository.getForResume(resumeId), isEmpty);
  });

  test('deleting a resume never deletes the library blocks it referenced - they may still be '
      'used by other resumes', () async {
    final resumeId = await createResume();
    final blockId = await createExperienceBlock();
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, blockId);

    await useCase(resumeId);

    expect(await experienceBlockRepository.getById(blockId), isNotNull);
  });

  test('another resume\'s versions, blocks, and files remain untouched', () async {
    final resumeIdA = await createResume(title: 'To be deleted');
    final resumeIdB = await createResume(title: 'Must survive');
    final blockId = await createExperienceBlock();
    await resumeBlockRepository.attach(resumeIdA, ResumeBlockType.experience, blockId);
    await resumeBlockRepository.attach(resumeIdB, ResumeBlockType.experience, blockId);
    final survivingFilePath = '${tempDir.path}/surviving.pdf';
    await File(survivingFilePath).writeAsBytes(utf8.encode('keep me'));
    await createVersion(resumeIdB, exportedPdfPath: survivingFilePath);

    await useCase(resumeIdA);

    expect(await resumeRepository.getById(resumeIdB), isNotNull);
    expect(await resumeBlockRepository.getForResume(resumeIdB), hasLength(1));
    expect(await File(survivingFilePath).exists(), isTrue);
  });

  test('deleting an unknown resume id does not throw', () async {
    await expectLater(useCase(999999), completes);
  });
}
