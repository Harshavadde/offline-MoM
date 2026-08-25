// Exercises migration v11 (lib/database/migrations/v11.dart, V2 Phase 5A,
// Student Toolkit) against a database stopped at v10, mirroring
// migration_v10_test.dart's pattern.
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV10() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 10,
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
      },
    ),
  );
}

void main() {
  test('creates toolkit_files with no rows and no foreign keys', () async {
    final db = await _openAtV10();
    addTearDown(() => db.close());

    await migrateV10ToV11(db);

    expect(await db.query('toolkit_files'), isEmpty);
    final fkCheck = await db.rawQuery('PRAGMA foreign_key_list(toolkit_files)');
    expect(fkCheck, isEmpty);
  });

  test('a row can be inserted and read back after the migration, including '
      'a null original_file_size_bytes', () async {
    final db = await _openAtV10();
    addTearDown(() => db.close());
    await migrateV10ToV11(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('toolkit_files', {
      'tool_type': 'imageCompress',
      'title': 'passport_photo',
      'output_path': '/data/toolkit/passport_photo.jpg',
      'file_size_bytes': 50000,
      'original_file_size_bytes': null,
      'is_favorite': 0,
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query('toolkit_files', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['title'], 'passport_photo');
    expect(rows.single['original_file_size_bytes'], isNull);
    expect(rows.single['is_favorite'], 0);
  });

  test('is_favorite defaults to 0 when omitted on insert', () async {
    final db = await _openAtV10();
    addTearDown(() => db.close());
    await migrateV10ToV11(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('toolkit_files', {
      'tool_type': 'imageResize',
      'title': 'diagram',
      'output_path': '/data/toolkit/diagram.png',
      'file_size_bytes': 10000,
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query('toolkit_files', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['is_favorite'], 0);
  });
}
