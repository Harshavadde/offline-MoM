// Exercises migration v17 (lib/database/migrations/v17.dart, V3 Milestone
// 0, Data Model & Device Foundation) against a database stopped at v16,
// mirroring migration_v13_test.dart's pattern.
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV16() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 16,
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
      },
    ),
  );
}

void main() {
  test('creates suggested_edits with the expected columns and defaults', () async {
    final db = await _openAtV16();
    addTearDown(() => db.close());

    await migrateV16ToV17(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('suggested_edits', {
      'resume_id': 1,
      'target_block_type': 'experience',
      'target_block_id': 7,
      'field_name': 'bullets',
      'original_value': 'Worked on Kubernetes',
      'suggested_value': 'Led Kubernetes deployment automation',
      'source_requirement': 'Kubernetes',
      'status': 'pending',
      'created_at': now,
    });

    final rows = await db.query('suggested_edits', where: 'id = ?', whereArgs: [id]);
    final row = rows.single;
    expect(row['resume_id'], 1);
    expect(row['target_block_type'], 'experience');
    expect(row['status'], 'pending');
    expect(row['resolved_at'], isNull);
  });

  test('suggested_edits accepts a profile-level suggestion with null target columns', () async {
    final db = await _openAtV16();
    addTearDown(() => db.close());
    await migrateV16ToV17(db);

    final id = await db.insert('suggested_edits', {
      'resume_id': 1,
      'field_name': 'summary',
      'original_value': 'a',
      'suggested_value': 'b',
      'status': 'pending',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });

    final row = (await db.query('suggested_edits', where: 'id = ?', whereArgs: [id])).single;
    expect(row['target_block_type'], isNull);
    expect(row['target_block_id'], isNull);
  });

  test(
    'adds resumes.achievements_json and resumes.template_id, defaulting to null on existing rows',
    () async {
      final db = await _openAtV16();
      addTearDown(() => db.close());

      // Insert a resume against the pre-v17 schema, before the new columns
      // exist, to prove the migration doesn't lose or alter existing data.
      final resumeId = await db.insert('resumes', {
        'title': 'Software Engineer Resume',
        'full_name': 'Jane Doe',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      });

      await migrateV16ToV17(db);

      final row = (await db.query('resumes', where: 'id = ?', whereArgs: [resumeId])).single;
      expect(row['title'], 'Software Engineer Resume', reason: 'existing data must survive the migration');
      expect(row['full_name'], 'Jane Doe');
      expect(row['achievements_json'], isNull);
      expect(row['template_id'], isNull);

      await db.update(
        'resumes',
        {'achievements_json': '["Won hackathon"]', 'template_id': 'classic-warm'},
        where: 'id = ?',
        whereArgs: [resumeId],
      );
      final updated = (await db.query('resumes', where: 'id = ?', whereArgs: [resumeId])).single;
      expect(updated['achievements_json'], '["Won hackathon"]');
      expect(updated['template_id'], 'classic-warm');
    },
  );

  test(
    'adds resume_versions.template_id/.tailored_for_jd_title/.tailored_for_jd_company, '
    'defaulting to null on existing rows',
    () async {
      final db = await _openAtV16();
      addTearDown(() => db.close());

      final resumeId = await db.insert('resumes', {
        'title': 'R',
        'full_name': 'Jane Doe',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      });
      final versionId = await db.insert('resume_versions', {
        'resume_id': resumeId,
        'version_label': 'v1',
        'compiled_snapshot': '{}',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      });

      await migrateV16ToV17(db);

      final row =
          (await db.query('resume_versions', where: 'id = ?', whereArgs: [versionId])).single;
      expect(row['version_label'], 'v1', reason: 'existing data must survive the migration');
      expect(row['template_id'], isNull);
      expect(row['tailored_for_jd_title'], isNull);
      expect(row['tailored_for_jd_company'], isNull);

      await db.update(
        'resume_versions',
        {
          'template_id': 'compact-technical-cool',
          'tailored_for_jd_title': 'Senior Backend Engineer',
          'tailored_for_jd_company': 'Acme Corp',
        },
        where: 'id = ?',
        whereArgs: [versionId],
      );
      final updated =
          (await db.query('resume_versions', where: 'id = ?', whereArgs: [versionId])).single;
      expect(updated['tailored_for_jd_title'], 'Senior Backend Engineer');
      expect(updated['tailored_for_jd_company'], 'Acme Corp');
    },
  );

  test('the new index on suggested_edits.resume_id exists', () async {
    final db = await _openAtV16();
    addTearDown(() => db.close());

    await migrateV16ToV17(db);

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'suggested_edits'",
    );
    expect(indexes.map((r) => r['name']), contains('idx_suggested_edits_resume_id'));
  });
}
