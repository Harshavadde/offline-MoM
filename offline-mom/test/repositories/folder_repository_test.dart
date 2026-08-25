import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/folder.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/folder_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late FolderRepository folderRepository;
  late DocumentRepository documentRepository;

  setUp(() async {
    db = await openTestDatabase();
    folderRepository = SqfliteFolderRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
  });

  tearDown(() => db.close());

  Folder buildFolder({String title = 'Coursework', DateTime? at}) {
    final now = at ?? DateTime(2026, 1, 1);
    return Folder(id: null, title: title, createdAt: now, updatedAt: now);
  }

  Document buildDocument({String title = 'Doc'}) {
    final now = DateTime(2026, 1, 1);
    return Document(
      id: null,
      title: title,
      originalFilename: '$title.pdf',
      sourceType: DocumentSourceType.pdf,
      mimeType: 'application/pdf',
      fileSizeBytes: 1024,
      filePath: '/tmp/$title.pdf',
      status: DocumentStatus.ready,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same folder', () async {
    final id = await folderRepository.insert(buildFolder(title: 'Semester 1'));
    final fetched = await folderRepository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.title, 'Semester 1');
  });

  test('getById returns null for an unknown id', () async {
    expect(await folderRepository.getById(999), isNull);
  });

  test('an empty folder (no documents ever assigned to it) is a completely normal, listable row '
      '- empty folders are allowed by design', () async {
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

  test('delete moves every document in the folder back to "All Documents" - the documents '
      'themselves are never deleted', () async {
    final folderId = await folderRepository.insert(buildFolder(title: 'Coursework'));
    final documentId = await documentRepository.insert(buildDocument(title: 'Assignment'));
    await documentRepository.moveToFolder(documentId, folderId);

    expect(await documentRepository.getFolderId(documentId), folderId);

    await folderRepository.delete(folderId);

    expect(
      await documentRepository.getFolderId(documentId),
      isNull,
      reason: 'the document must move back to "All Documents"',
    );
    expect(
      await documentRepository.getById(documentId),
      isNotNull,
      reason: 'deleting a folder must never delete the documents inside it',
    );
  });

  test('deleting a folder with no documents in it does not throw (the common case for an '
      'empty folder)', () async {
    final id = await folderRepository.insert(buildFolder(title: 'Never used'));
    await expectLater(folderRepository.delete(id), completes);
  });
}
