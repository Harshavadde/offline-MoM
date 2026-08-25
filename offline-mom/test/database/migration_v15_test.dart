// Exercises migration v15 (lib/database/migrations/v15.dart, V2.2
// Production Hardening, Priority 2 - document folders) against a database
// stopped at v14, mirroring migration_v13_test.dart's pattern.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/database/migrations/v1.dart';
import 'package:offline_mom/database/migrations/v2.dart';
import 'package:offline_mom/database/migrations/v3.dart';
import 'package:offline_mom/database/migrations/v4.dart';
import 'package:offline_mom/database/migrations/v5.dart';
import 'package:offline_mom/database/migrations/v6.dart';
import 'package:offline_mom/database/migrations/v7.dart';
import 'package:offline_mom/database/migrations/v8.dart';
import 'package:offline_mom/database/migrations/v9.dart';
import 'package:offline_mom/database/migrations/v10.dart';
import 'package:offline_mom/database/migrations/v11.dart';
import 'package:offline_mom/database/migrations/v12.dart';
import 'package:offline_mom/database/migrations/v13.dart';
import 'package:offline_mom/database/migrations/v14.dart';
import 'package:offline_mom/database/migrations/v15.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV14() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 14,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await createV1Schema(db);
        await migrateV1ToV2(db);
        await migrateV2ToV3(db);
        await migrateV3ToV4(db);
        await migrateV4ToV5(db);
        await migrateV5ToV6(db);
        await migrateV6ToV7(db);
        await migrateV7ToV8(db);
        await migrateV8ToV9(db);
        await migrateV9ToV10(db);
        await migrateV10ToV11(db);
        await migrateV11ToV12(db);
        await migrateV12ToV13(db);
        await migrateV13ToV14(db);
      },
    ),
  );
}

Map<String, Object?> _documentRow({String title = 'Doc'}) {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return {
    'title': title,
    'original_filename': '$title.pdf',
    'source_type': 'pdf',
    'mime_type': 'application/pdf',
    'file_size_bytes': 1024,
    'file_path': '/tmp/$title.pdf',
    'status': 'ready',
    'created_at': now,
    'updated_at': now,
  };
}

void main() {
  test('creates folders with the expected columns', () async {
    final db = await _openAtV14();
    addTearDown(() => db.close());
    await migrateV14ToV15(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('folders', {
      'title': 'Coursework',
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query('folders', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['title'], 'Coursework');
  });

  test('an empty folder is allowed - inserting one with no documents does not throw', () async {
    final db = await _openAtV14();
    addTearDown(() => db.close());
    await migrateV14ToV15(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    await db.insert('folders', {'title': 'Empty', 'created_at': now, 'updated_at': now});

    final rows = await db.query('folders');
    expect(rows, hasLength(1));
  });

  test('documents.folder_id is added, nullable, and defaults to null for pre-existing rows',
      () async {
    final db = await _openAtV14();
    addTearDown(() => db.close());

    // Inserted *before* the migration - simulates a document that existed
    // on a real device before upgrading to v15.
    final preExistingId = await db.insert('documents', _documentRow(title: 'Pre-existing'));

    await migrateV14ToV15(db);

    final rows = await db.query('documents', where: 'id = ?', whereArgs: [preExistingId]);
    expect(
      rows.single['folder_id'],
      isNull,
      reason: 'a document that existed before this migration must stay visible under '
          '"All Documents" (folder_id IS NULL), not silently disappear or error',
    );
  });

  test('a document can be inserted directly into a folder', () async {
    final db = await _openAtV14();
    addTearDown(() => db.close());
    await migrateV14ToV15(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final folderId =
        await db.insert('folders', {'title': 'Coursework', 'created_at': now, 'updated_at': now});
    final documentId =
        await db.insert('documents', {..._documentRow(title: 'Filed'), 'folder_id': folderId});

    final rows = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    expect(rows.single['folder_id'], folderId);
  });

  test('deleting a folder does not cascade-delete its documents at the SQL level '
      '(no foreign key is declared - unfiling is the repository layer\'s job)', () async {
    final db = await _openAtV14();
    addTearDown(() => db.close());
    await migrateV14ToV15(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final folderId =
        await db.insert('folders', {'title': 'Coursework', 'created_at': now, 'updated_at': now});
    final documentId =
        await db.insert('documents', {..._documentRow(title: 'Filed'), 'folder_id': folderId});

    await db.delete('folders', where: 'id = ?', whereArgs: [folderId]);

    final rows = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    expect(rows, hasLength(1), reason: 'the document itself must never be deleted');
  });
}
