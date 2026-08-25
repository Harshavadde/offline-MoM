import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late DocumentRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteDocumentRepository(db);
  });

  tearDown(() => db.close());

  Document buildDocument({
    String title = 'Q1 Report',
    DocumentSourceType sourceType = DocumentSourceType.pdf,
    DocumentStatus status = DocumentStatus.created,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime(2026, 1, 1, 10);
    return Document(
      id: null,
      title: title,
      originalFilename: '$title.${sourceType.name}',
      sourceType: sourceType,
      mimeType: sourceType.mimeType,
      fileSizeBytes: 1024,
      filePath: '/tmp/$title.${sourceType.name}',
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same document', () async {
    final id = await repository.insert(buildDocument(title: 'Contract'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.title, 'Contract');
    expect(fetched.sourceType, DocumentSourceType.pdf);
    expect(fetched.status, DocumentStatus.created);
    expect(fetched.mimeType, 'application/pdf');
    expect(fetched.fileSizeBytes, 1024);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('getAll orders by createdAt descending', () async {
    await repository.insert(
      buildDocument(title: 'Oldest', createdAt: DateTime(2026, 1, 1)),
    );
    await repository.insert(
      buildDocument(title: 'Newest', createdAt: DateTime(2026, 1, 3)),
    );
    await repository.insert(
      buildDocument(title: 'Middle', createdAt: DateTime(2026, 1, 2)),
    );

    final all = await repository.getAll();

    expect(all.map((d) => d.title).toList(), ['Newest', 'Middle', 'Oldest']);
  });

  test('getAll omits extractedText (Phase 3B: list queries skip the '
      'potentially large text column no list view actually renders), while '
      'getById/getByIds still return the real text', () async {
    final id = await repository.insert(buildDocument(title: 'Report'));
    await repository.update(
      (await repository.getById(id))!.copyWith(
        status: DocumentStatus.ready,
        extractedText: 'A large document body that a list screen never shows.',
      ),
    );

    final all = await repository.getAll();
    expect(all.single.extractedText, isNull);

    final byId = await repository.getById(id);
    expect(byId!.extractedText, 'A large document body that a list screen never shows.');

    final byIds = await repository.getByIds([id]);
    expect(byIds.single.extractedText, 'A large document body that a list screen never shows.');
  });

  test('update persists changed fields, including extracted text and errors',
      () async {
    final id = await repository.insert(buildDocument(title: 'Draft title'));
    final original = (await repository.getById(id))!;

    await repository.update(
      original.copyWith(
        title: 'Final title',
        status: DocumentStatus.ready,
        extractedText: 'The extracted body text.',
      ),
    );
    final updated = await repository.getById(id);

    expect(updated!.title, 'Final title');
    expect(updated.status, DocumentStatus.ready);
    expect(updated.extractedText, 'The extracted body text.');
  });

  test('update persists an error message', () async {
    final id = await repository.insert(buildDocument());
    final original = (await repository.getById(id))!;

    await repository.update(
      original.copyWith(status: DocumentStatus.error, errorMessage: 'boom'),
    );
    final updated = await repository.getById(id);

    expect(updated!.status, DocumentStatus.error);
    expect(updated.errorMessage, 'boom');
  });

  test('delete removes the document', () async {
    final id = await repository.insert(buildDocument());
    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('getByIds returns matching documents and ignores an empty set',
      () async {
    final id1 = await repository.insert(buildDocument(title: 'One'));
    final id2 = await repository.insert(buildDocument(title: 'Two'));
    await repository.insert(buildDocument(title: 'Three'));

    final documents = await repository.getByIds({id1, id2});

    expect(documents.map((d) => d.title).toSet(), {'One', 'Two'});
    expect(await repository.getByIds(const []), isEmpty);
  });

  test('round-trips every DocumentSourceType correctly', () async {
    for (final sourceType in DocumentSourceType.values) {
      final id = await repository.insert(
        buildDocument(title: 'File for ${sourceType.name}', sourceType: sourceType),
      );
      final fetched = await repository.getById(id);
      expect(fetched!.sourceType, sourceType);
      expect(fetched.mimeType, sourceType.mimeType);
    }
  });

  test('handles a very large extracted text body without truncation',
      () async {
    final largeText = 'word ' * 200000; // ~1MB of text
    final id = await repository.insert(buildDocument());
    final original = (await repository.getById(id))!;

    await repository.update(
      original.copyWith(status: DocumentStatus.ready, extractedText: largeText),
    );
    final updated = await repository.getById(id);

    expect(updated!.extractedText!.length, largeText.length);
  });

  // V2.2 Production Hardening, Priority 2 (document folders).
  group('folders', () {
    test('getInFolder(null) - "All Documents" - returns every document with no folder assigned '
        '(every document that existed before this feature, by default)', () async {
      final id1 = await repository.insert(buildDocument(title: 'Unfiled'));
      final id2 = await repository.insert(buildDocument(title: 'Also unfiled'));

      final unfiled = await repository.getInFolder(null);

      expect(unfiled.map((d) => d.id).toSet(), {id1, id2});
    });

    test('moveToFolder then getInFolder(folderId) returns only that folder\'s documents',
        () async {
      final inFolder = await repository.insert(buildDocument(title: 'Filed'));
      final stillUnfiled = await repository.insert(buildDocument(title: 'Unfiled'));

      await repository.moveToFolder(inFolder, 42);

      final folderContents = await repository.getInFolder(42);
      expect(folderContents.map((d) => d.id).toList(), [inFolder]);

      final allDocuments = await repository.getInFolder(null);
      expect(allDocuments.map((d) => d.id).toList(), [stillUnfiled]);
    });

    test('moveToFolder back to null returns a document to "All Documents"', () async {
      final id = await repository.insert(buildDocument());
      await repository.moveToFolder(id, 7);
      await repository.moveToFolder(id, null);

      expect(await repository.getFolderId(id), isNull);
      expect((await repository.getInFolder(null)).map((d) => d.id), contains(id));
    });

    test('getFolderId reflects the current assignment', () async {
      final id = await repository.insert(buildDocument());
      expect(await repository.getFolderId(id), isNull);

      await repository.moveToFolder(id, 3);
      expect(await repository.getFolderId(id), 3);
    });
  });
}
