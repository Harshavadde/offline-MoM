// Tests migrateV21ToV22 (lib/database/migrations/v22.dart) - the additive
// `project_blocks.status` column backing ProjectBlock.status
// (AI-Tailored-Resume-from-JD feature). Builds a real v21 database (every
// migration up to v21, no further), inserts a pre-v22-shaped row directly,
// then applies the migration and confirms the column exists, is nullable,
// and that a pre-existing row reads back with status == null via
// ProjectBlock.fromMap - never a thrown error.
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
import 'package:offline_mom/database/migrations/v16.dart';
import 'package:offline_mom/database/migrations/v17.dart';
import 'package:offline_mom/database/migrations/v18.dart';
import 'package:offline_mom/database/migrations/v19.dart';
import 'package:offline_mom/database/migrations/v20.dart';
import 'package:offline_mom/database/migrations/v21.dart';
import 'package:offline_mom/database/migrations/v22.dart';
import 'package:offline_mom/models/project_block.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openV21Database() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 21,
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
        await migrateV14ToV15(db);
        await migrateV15ToV16(db);
        await migrateV16ToV17(db);
        await migrateV17ToV18(db);
        await migrateV18ToV19(db);
        await migrateV19ToV20(db);
        await migrateV20ToV21(db);
      },
    ),
  );
}

void main() {
  test('adds a nullable status column without disturbing an existing row', () async {
    final db = await _openV21Database();
    addTearDown(db.close);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final rowId = await db.insert('project_blocks', {
      'name': 'Pre-existing Project',
      'link': null,
      'bullets_json': '[]',
      'created_at': now,
      'updated_at': now,
    });

    await migrateV21ToV22(db);

    final rows = await db.query('project_blocks', where: 'id = ?', whereArgs: [rowId]);
    expect(rows, hasLength(1));
    expect(rows.single['status'], isNull);

    final block = ProjectBlock.fromMap(rows.single);
    expect(block.status, isNull);
    expect(block.name, 'Pre-existing Project');
  });

  test('a row inserted after migration can carry an explicit status and reads back correctly', () async {
    final db = await _openV21Database();
    addTearDown(db.close);
    await migrateV21ToV22(db);

    final now = DateTime(2026, 1, 1);
    final block = ProjectBlock(
      id: null,
      name: 'Job Application Tracker',
      bullets: const ['Built with Django'],
      status: ProjectBlockStatus.planned,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert('project_blocks', block.toMap()..remove('id'));

    final rows = await db.query('project_blocks', where: 'id = ?', whereArgs: [id]);
    final reloaded = ProjectBlock.fromMap(rows.single);
    expect(reloaded.status, ProjectBlockStatus.planned);
  });
}
