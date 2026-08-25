import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/toolkit_file.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ToolkitFileRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteToolkitFileRepository(db);
  });

  tearDown(() => db.close());

  ToolkitFile buildFile({
    String title = 'passport_photo',
    ToolkitToolType toolType = ToolkitToolType.imageCompress,
    int fileSizeBytes = 50000,
    int? originalFileSizeBytes = 200000,
    bool isFavorite = false,
    DateTime? createdAt,
    int? pageCount,
  }) {
    final now = createdAt ?? DateTime(2026, 1, 1, 10);
    return ToolkitFile(
      id: null,
      toolType: toolType,
      title: title,
      outputPath: '/data/toolkit/$title.jpg',
      fileSizeBytes: fileSizeBytes,
      originalFileSizeBytes: originalFileSizeBytes,
      isFavorite: isFavorite,
      createdAt: now,
      updatedAt: now,
      pageCount: pageCount,
    );
  }

  test('insert then getById returns the same file', () async {
    final id = await repository.insert(buildFile(title: 'scholarship_form'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.title, 'scholarship_form');
    expect(fetched.toolType, ToolkitToolType.imageCompress);
    expect(fetched.fileSizeBytes, 50000);
    expect(fetched.originalFileSizeBytes, 200000);
    expect(fetched.isFavorite, isFalse);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('round-trips a null originalFileSizeBytes', () async {
    final id = await repository.insert(buildFile(originalFileSizeBytes: null));
    final fetched = await repository.getById(id);

    expect(fetched!.originalFileSizeBytes, isNull);
    expect(fetched.reductionPercent, isNull);
  });

  test('round-trips ToolkitToolType.imageResize', () async {
    final id = await repository.insert(buildFile(toolType: ToolkitToolType.imageResize));
    final fetched = await repository.getById(id);

    expect(fetched!.toolType, ToolkitToolType.imageResize);
  });

  test('getAll orders by createdAt descending', () async {
    await repository.insert(buildFile(title: 'Oldest', createdAt: DateTime(2026, 1, 1)));
    await repository.insert(buildFile(title: 'Newest', createdAt: DateTime(2026, 1, 3)));
    await repository.insert(buildFile(title: 'Middle', createdAt: DateTime(2026, 1, 2)));

    final all = await repository.getAll();

    expect(all.map((f) => f.title).toList(), ['Newest', 'Middle', 'Oldest']);
  });

  test('update persists a renamed title and favorite flag', () async {
    final id = await repository.insert(buildFile(title: 'Draft'));
    final original = (await repository.getById(id))!;

    await repository.update(original.copyWith(title: 'Final', isFavorite: true));
    final updated = await repository.getById(id);

    expect(updated!.title, 'Final');
    expect(updated.isFavorite, isTrue);
  });

  test('delete removes the row', () async {
    final id = await repository.insert(buildFile());
    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('round-trips every Phase 5B ToolkitToolType value (scan/pdfCompress/'
      'pdfMerge/pdfSplit/pdfOrganize)', () async {
    for (final toolType in [
      ToolkitToolType.scan,
      ToolkitToolType.pdfCompress,
      ToolkitToolType.pdfMerge,
      ToolkitToolType.pdfSplit,
      ToolkitToolType.pdfOrganize,
    ]) {
      final id = await repository.insert(
        buildFile(title: 'File for ${toolType.name}', toolType: toolType),
      );
      final fetched = await repository.getById(id);
      expect(fetched!.toolType, toolType, reason: toolType.name);
    }
  });

  test('round-trips a non-null pageCount for a scan/PDF output', () async {
    final id = await repository.insert(
      buildFile(toolType: ToolkitToolType.scan, pageCount: 7, originalFileSizeBytes: null),
    );
    final fetched = await repository.getById(id);

    expect(fetched!.pageCount, 7);
  });

  test('pageCount is null for an image compress/resize row', () async {
    final id = await repository.insert(buildFile());
    final fetched = await repository.getById(id);

    expect(fetched!.pageCount, isNull);
  });

  group('P0-9: folders', () {
    test('folderId defaults to null (unfiled)', () async {
      final id = await repository.insert(buildFile());
      final fetched = await repository.getById(id);

      expect(fetched!.folderId, isNull);
    });

    test('getInFolder(null) returns only unfiled files', () async {
      final unfiled = await repository.insert(buildFile(title: 'Unfiled'));
      final filed = await repository.insert(buildFile(title: 'Filed'));
      await repository.moveToFolder(filed, 42);

      final result = await repository.getInFolder(null);

      expect(result.map((f) => f.id), contains(unfiled));
      expect(result.map((f) => f.id), isNot(contains(filed)));
    });

    test('getInFolder(id) returns only files in that folder, newest first', () async {
      final a = await repository.insert(buildFile(title: 'A', createdAt: DateTime(2026, 1, 1)));
      final b = await repository.insert(buildFile(title: 'B', createdAt: DateTime(2026, 1, 2)));
      final other = await repository.insert(buildFile(title: 'Other'));
      await repository.moveToFolder(a, 7);
      await repository.moveToFolder(b, 7);
      await repository.moveToFolder(other, 8);

      final result = await repository.getInFolder(7);

      expect(result.map((f) => f.id).toList(), [b, a]);
    });

    test('moveToFolder(id, null) moves a file back to All Files', () async {
      final id = await repository.insert(buildFile());
      await repository.moveToFolder(id, 5);
      expect((await repository.getById(id))!.folderId, 5);

      await repository.moveToFolder(id, null);
      expect((await repository.getById(id))!.folderId, isNull);
    });

    test('getAll() includes files regardless of folder (folder-agnostic)', () async {
      final unfiled = await repository.insert(buildFile(title: 'Unfiled'));
      final filed = await repository.insert(buildFile(title: 'Filed'));
      await repository.moveToFolder(filed, 1);

      final all = await repository.getAll();

      expect(all.map((f) => f.id), containsAll([unfiled, filed]));
    });
  });
}
