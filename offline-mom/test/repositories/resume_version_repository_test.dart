import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/resume_version.dart';
import 'package:offline_mom/repositories/resume_version_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeVersionRepository repository;
  late Directory tempDir;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteResumeVersionRepository(db);
    tempDir = await Directory.systemTemp.createTemp('resume_version_repository_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ResumeSnapshot buildSnapshot({int resumeId = 1}) {
    return ResumeSnapshot(
      resumeId: resumeId,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Engineer',
          company: 'Acme',
          startDate: '2022-01',
          bullets: ['Did the thing'],
        ),
      ],
    );
  }

  ResumeVersion buildVersion({
    int resumeId = 1,
    String label = 'v1',
    DateTime? at,
    String? exportedPdfPath,
  }) {
    final now = at ?? DateTime(2026, 1, 1);
    return ResumeVersion(
      id: null,
      resumeId: resumeId,
      versionLabel: label,
      compiledSnapshot: buildSnapshot(resumeId: resumeId),
      exportedPdfPath: exportedPdfPath,
      createdAt: now,
    );
  }

  Future<String> createRealFile(String name) async {
    final path = '${tempDir.path}/$name';
    await File(path).writeAsString('fake pdf bytes');
    return path;
  }

  test('insert then getById returns the same version', () async {
    final id = await repository.insert(buildVersion(label: 'First draft'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.versionLabel, 'First draft');
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('compiled_snapshot round-trips the full nested ResumeSnapshot correctly, not just its '
      'top-level fields', () async {
    final id = await repository.insert(buildVersion());
    final fetched = (await repository.getById(id))!;

    expect(fetched.compiledSnapshot.profile.fullName, 'Jane Doe');
    expect(fetched.compiledSnapshot.experience, hasLength(1));
    expect(fetched.compiledSnapshot.experience.single.role, 'Engineer');
    expect(fetched.compiledSnapshot.experience.single.bullets, ['Did the thing']);
  });

  test('exportedPdfPath is nullable and round-trips as null before a PDF has been exported', () async {
    final id = await repository.insert(buildVersion());
    final fetched = (await repository.getById(id))!;

    expect(fetched.exportedPdfPath, isNull);
  });

  test('renameLabel edits only the label - compiledSnapshot is untouched', () async {
    final id = await repository.insert(buildVersion(label: 'Old label'));

    await repository.renameLabel(id, 'New label');

    final fetched = (await repository.getById(id))!;
    expect(fetched.versionLabel, 'New label');
    expect(fetched.compiledSnapshot.profile.fullName, 'Jane Doe');
  });

  test('getForResume returns every version of one resume, most recent first', () async {
    await repository.insert(buildVersion(resumeId: 1, label: 'Oldest', at: DateTime(2026, 1, 1)));
    await repository.insert(buildVersion(resumeId: 1, label: 'Newest', at: DateTime(2026, 1, 3)));
    await repository.insert(buildVersion(resumeId: 2, label: 'Other resume', at: DateTime(2026, 1, 2)));

    final versions = await repository.getForResume(1);

    expect(versions.map((v) => v.versionLabel).toList(), ['Newest', 'Oldest']);
  });

  group('delete', () {
    test('removes the version row', () async {
      final id = await repository.insert(buildVersion());
      await repository.delete(id);

      expect(await repository.getById(id), isNull);
    });

    test('does not throw when the version has no exported PDF file', () async {
      final id = await repository.insert(buildVersion(exportedPdfPath: null));
      await expectLater(repository.delete(id), completes);
    });

    test('deletes the exported PDF file from disk along with the row', () async {
      final path = await createRealFile('version-1.pdf');
      final id = await repository.insert(buildVersion(exportedPdfPath: path));
      expect(await File(path).exists(), isTrue, reason: 'sanity check - the file must exist first');

      await repository.delete(id);

      expect(await File(path).exists(), isFalse);
      expect(await repository.getById(id), isNull);
    });

    test('does not throw when exportedPdfPath is set but the file is already missing on disk',
        () async {
      final missingPath = '${tempDir.path}/never-actually-written.pdf';
      final id = await repository.insert(buildVersion(exportedPdfPath: missingPath));

      await expectLater(repository.delete(id), completes);
      expect(await repository.getById(id), isNull);
    });

    test('does nothing and does not throw for an id that does not exist', () async {
      await expectLater(repository.delete(999), completes);
    });
  });

  group('deleteAllForResume', () {
    test('removes every version belonging to the resume', () async {
      await repository.insert(buildVersion(resumeId: 1, label: 'v1'));
      await repository.insert(buildVersion(resumeId: 1, label: 'v2'));
      await repository.insert(buildVersion(resumeId: 2, label: 'other resume'));

      await repository.deleteAllForResume(1);

      expect(await repository.getForResume(1), isEmpty);
      expect(await repository.getForResume(2), hasLength(1), reason: 'another resume\'s versions must survive');
    });

    test('deletes every referenced exported PDF file, not just the DB rows', () async {
      final pathA = await createRealFile('version-a.pdf');
      final pathB = await createRealFile('version-b.pdf');
      await repository.insert(buildVersion(resumeId: 1, label: 'v1', exportedPdfPath: pathA));
      await repository.insert(buildVersion(resumeId: 1, label: 'v2', exportedPdfPath: pathB));

      await repository.deleteAllForResume(1);

      expect(await File(pathA).exists(), isFalse);
      expect(await File(pathB).exists(), isFalse);
    });

    test('correctly handles a mix of versions with and without an exported file', () async {
      final path = await createRealFile('version-with-file.pdf');
      await repository.insert(buildVersion(resumeId: 1, label: 'has file', exportedPdfPath: path));
      await repository.insert(buildVersion(resumeId: 1, label: 'no file', exportedPdfPath: null));

      await expectLater(repository.deleteAllForResume(1), completes);

      expect(await File(path).exists(), isFalse);
      expect(await repository.getForResume(1), isEmpty);
    });

    test('does not touch a different resume\'s exported files', () async {
      final ownPath = await createRealFile('own.pdf');
      final otherPath = await createRealFile('other.pdf');
      await repository.insert(buildVersion(resumeId: 1, exportedPdfPath: ownPath));
      await repository.insert(buildVersion(resumeId: 2, exportedPdfPath: otherPath));

      await repository.deleteAllForResume(1);

      expect(await File(otherPath).exists(), isTrue);
    });

    test('does nothing and does not throw when the resume has no versions at all', () async {
      await expectLater(repository.deleteAllForResume(42), completes);
      expect(await repository.getForResume(42), isEmpty);
    });
  });
}
