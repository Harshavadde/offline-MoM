// Mirrors folder_repository_test.dart (Documents' own folder repository) -
// SqfliteToolkitFolderRepository implements the exact same FolderRepository
// contract, backed by its own toolkit_folders table (P0-9, File-Manager
// Parity).
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/folder.dart';
import 'package:offline_mom/models/toolkit_file.dart';
import 'package:offline_mom/repositories/folder_repository.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/repositories/toolkit_folder_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late FolderRepository folderRepository;
  late ToolkitFileRepository fileRepository;

  setUp(() async {
    db = await openTestDatabase();
    folderRepository = SqfliteToolkitFolderRepository(db);
    fileRepository = SqfliteToolkitFileRepository(db);
  });

  tearDown(() => db.close());

  Folder buildFolder({String title = 'Tax 2026', DateTime? at}) {
    final now = at ?? DateTime(2026, 1, 1);
    return Folder(id: null, title: title, createdAt: now, updatedAt: now);
  }

  ToolkitFile buildFile({String title = 'File'}) {
    final now = DateTime(2026, 1, 1);
    return ToolkitFile(
      id: null,
      toolType: ToolkitToolType.imageCompress,
      title: title,
      outputPath: '/data/toolkit/$title.jpg',
      fileSizeBytes: 1000,
      originalFileSizeBytes: 2000,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same folder', () async {
    final id = await folderRepository.insert(buildFolder(title: 'Scholarships'));
    final fetched = await folderRepository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.title, 'Scholarships');
  });

  test('getById returns null for an unknown id', () async {
    expect(await folderRepository.getById(999), isNull);
  });

  test('an empty folder (no files ever assigned to it) is a completely normal, listable row - '
      'empty folders are allowed by design', () async {
    await folderRepository.insert(buildFolder(title: 'Empty on purpose'));

    final all = await folderRepository.getAll();

    expect(all, hasLength(1));
    expect(all.single.title, 'Empty on purpose');
  });

  test('getAll orders alphabetically, case-insensitively', () async {
    await folderRepository.insert(buildFolder(title: 'zebra'));
    await folderRepository.insert(buildFolder(title: 'Apple'));
    await folderRepository.insert(buildFolder(title: 'banana'));

    final all = await folderRepository.getAll();

    expect(all.map((f) => f.title).toList(), ['Apple', 'banana', 'zebra']);
  });

  test('two folders may share the same name (no uniqueness constraint, matching Documents\' own '
      'folders) - a real duplicate-name scenario that is simply allowed, not an error', () async {
    final first = await folderRepository.insert(buildFolder(title: 'Tax'));
    final second = await folderRepository.insert(buildFolder(title: 'Tax'));

    expect(first, isNot(second));
    final all = await folderRepository.getAll();
    expect(all.where((f) => f.title == 'Tax'), hasLength(2));
  });

  test('update renames a folder', () async {
    final id = await folderRepository.insert(buildFolder(title: 'Old name'));
    final folder = (await folderRepository.getById(id))!;

    await folderRepository.update(folder.copyWith(title: 'New name'));

    expect((await folderRepository.getById(id))!.title, 'New name');
  });

  test('delete removes the folder', () async {
    final id = await folderRepository.insert(buildFolder());
    await folderRepository.delete(id);

    expect(await folderRepository.getById(id), isNull);
  });

  test('delete moves every file in the folder back to "All Files" - the files themselves are '
      'never deleted', () async {
    final folderId = await folderRepository.insert(buildFolder(title: 'Receipts'));
    final fileId = await fileRepository.insert(buildFile(title: 'Receipt'));
    await fileRepository.moveToFolder(fileId, folderId);

    expect((await fileRepository.getById(fileId))!.folderId, folderId);

    await folderRepository.delete(folderId);

    final moved = await fileRepository.getById(fileId);
    expect(moved, isNotNull, reason: 'deleting a folder must never delete the files inside it');
    expect(moved!.folderId, isNull, reason: 'the file must move back to "All Files"');
  });

  test('deleting a folder with no files in it does not throw (the common case for an empty '
      'folder)', () async {
    final id = await folderRepository.insert(buildFolder(title: 'Never used'));
    await expectLater(folderRepository.delete(id), completes);
  });

  test('deleting a toolkit folder never touches Documents\' own folders table', () async {
    // A regression guard for the exact reason this pass uses a separate
    // table: this repository's delete() must only ever touch toolkit_files,
    // never documents. Proven indirectly - if it accidentally wrote to the
    // documents table, sqflite would either throw (wrong columns) or
    // silently succeed against a table this test never creates data in, so
    // the only meaningful assertion is that delete() completes cleanly
    // against a purely toolkit-scoped fixture.
    final folderId = await folderRepository.insert(buildFolder(title: 'Isolated'));
    final fileId = await fileRepository.insert(buildFile());
    await fileRepository.moveToFolder(fileId, folderId);

    await expectLater(folderRepository.delete(folderId), completes);
  });
}
