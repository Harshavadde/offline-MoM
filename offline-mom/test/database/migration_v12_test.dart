// Exercises migration v12 (lib/database/migrations/v12.dart, V2 Phase 5B,
// Scanner + PDF Tools) against a database stopped at v11, mirroring
// migration_v11_test.dart's pattern.
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV11() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 11,
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
      },
    ),
  );
}

void main() {
  test('adds toolkit_files.page_count, nullable, defaulting to null for '
      'pre-existing rows', () async {
    final db = await _openAtV11();
    addTearDown(() => db.close());

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('toolkit_files', {
      'tool_type': 'imageCompress',
      'title': 'passport_photo',
      'output_path': '/data/toolkit/passport_photo.jpg',
      'file_size_bytes': 50000,
      'original_file_size_bytes': 200000,
      'is_favorite': 0,
      'created_at': now,
      'updated_at': now,
    });

    await migrateV11ToV12(db);

    final rows = await db.query('toolkit_files', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['page_count'], isNull);
  });

  test('page_count can be set to a positive integer and read back after '
      'the migration', () async {
    final db = await _openAtV11();
    addTearDown(() => db.close());
    await migrateV11ToV12(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('toolkit_files', {
      'tool_type': 'scan',
      'title': 'Scan 2026-01-01',
      'output_path': '/data/toolkit/scan_1.pdf',
      'file_size_bytes': 900000,
      'is_favorite': 0,
      'created_at': now,
      'updated_at': now,
      'page_count': 12,
    });

    final rows = await db.query('toolkit_files', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['page_count'], 12);
  });
}
