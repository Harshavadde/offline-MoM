// Exercises migration v13 (lib/database/migrations/v13.dart, V2 Phase 6A,
// AI Model Manager) against a database stopped at v12, mirroring
// migration_v12_test.dart's pattern.
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV12() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 12,
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
      },
    ),
  );
}

void main() {
  test('creates installed_models with the expected columns and defaults', () async {
    final db = await _openAtV12();
    addTearDown(() => db.close());

    await migrateV12ToV13(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('installed_models', {
      'model_id': 'whisper-small',
      'kind': 'speechToText',
      'local_path': '/data/ggml-small.bin',
      'size_bytes': 466 * 1024 * 1024,
      'downloaded_at': now,
    });

    final rows = await db.query('installed_models', where: 'id = ?', whereArgs: [id]);
    final row = rows.single;
    expect(row['model_id'], 'whisper-small');
    expect(row['kind'], 'speechToText');
    expect(row['local_sha256'], isNull);
    expect(row['is_active'], 0, reason: 'is_active should default to 0');
  });

  test('multiple rows of different kinds coexist and are independently queryable', () async {
    final db = await _openAtV12();
    addTearDown(() => db.close());
    await migrateV12ToV13(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    await db.insert('installed_models', {
      'model_id': 'llm-qwen2.5-1.5b-instruct-q4km',
      'kind': 'llm',
      'local_path': 'hf://Qwen/Qwen2.5-1.5B-Instruct-GGUF/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'size_bytes': 1100 * 1024 * 1024,
      'downloaded_at': now,
      'is_active': 1,
    });
    await db.insert('installed_models', {
      'model_id': 'whisper-tiny',
      'kind': 'speechToText',
      'local_path': '/data/ggml-tiny.bin',
      'size_bytes': 75 * 1024 * 1024,
      'downloaded_at': now,
      'local_sha256': 'abc123',
      'is_active': 0,
    });

    final llmRows = await db.query('installed_models', where: 'kind = ?', whereArgs: ['llm']);
    expect(llmRows, hasLength(1));
    expect(llmRows.single['is_active'], 1);

    final sttRows =
        await db.query('installed_models', where: 'kind = ?', whereArgs: ['speechToText']);
    expect(sttRows, hasLength(1));
    expect(sttRows.single['local_sha256'], 'abc123');
  });
}
