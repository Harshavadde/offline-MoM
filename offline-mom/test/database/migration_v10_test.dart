// Exercises migration v10 (lib/database/migrations/v10.dart, V2 Phase 2B,
// ADR-028) against a database stopped at v9, rather than through
// openTestDatabase() - mirrors migration_v9_test.dart's pattern.
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV9() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 9,
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
      },
    ),
  );
}

void main() {
  test('adds is_pinned defaulting to 0, backfilling every pre-existing row',
      () async {
    final db = await _openAtV9();
    addTearDown(() => db.close());

    final now = DateTime(2026, 1, 1).toIso8601String();
    final sessionId = await db.insert('chat_sessions', {
      'title': 'Workspace chat',
      'scope': 'workspace',
      'meeting_id': null,
      'document_id': null,
      'created_at': now,
      'updated_at': now,
    });

    await migrateV9ToV10(db);

    final rows = await db.query('chat_sessions', where: 'id = ?', whereArgs: [sessionId]);
    expect(rows.single['is_pinned'], 0);
  });

  test('is_pinned can be set to 1 and read back after the migration', () async {
    final db = await _openAtV9();
    addTearDown(() => db.close());
    await migrateV9ToV10(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final sessionId = await db.insert('chat_sessions', {
      'title': 'Pinned chat',
      'scope': 'workspace',
      'meeting_id': null,
      'document_id': null,
      'created_at': now,
      'updated_at': now,
      'is_pinned': 1,
    });

    final rows = await db.query('chat_sessions', where: 'id = ?', whereArgs: [sessionId]);
    expect(rows.single['is_pinned'], 1);
  });
}
