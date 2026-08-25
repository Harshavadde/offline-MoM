// Exercises migration v9 (lib/database/migrations/v9.dart, ADR-025) against
// a database stopped at v8, rather than through openTestDatabase() - proves
// the CHECK constraints and cascade-delete behavior actually hold at the
// schema level, not just that repository-level code happens to write
// consistent rows.
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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV8() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 8,
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
      },
    ),
  );
}

Future<int> _insertMeeting(Database db) async {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return db.insert('meetings', {
    'title': 'Standup',
    'source': 'recorded',
    'status': 'ready',
    'created_at': now,
    'updated_at': now,
  });
}

Future<int> _insertDocument(Database db) async {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return db.insert('documents', {
    'title': 'Report',
    'original_filename': 'report.pdf',
    'source_type': 'pdf',
    'mime_type': 'application/pdf',
    'file_size_bytes': 100,
    'file_path': '/tmp/report.pdf',
    'status': 'ready',
    'created_at': now,
    'updated_at': now,
  });
}

void main() {
  test('creates chat_sessions and chat_messages, empty on a v8 database with '
      'no chat data', () async {
    final db = await _openAtV8();
    addTearDown(() => db.close());

    await migrateV8ToV9(db);

    expect(await db.query('chat_sessions'), isEmpty);
    expect(await db.query('chat_messages'), isEmpty);
  });

  test('accepts a workspace-scoped session (neither meeting_id nor '
      'document_id set)', () async {
    final db = await _openAtV8();
    addTearDown(() => db.close());
    await migrateV8ToV9(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    final id = await db.insert('chat_sessions', {
      'title': 'Workspace chat',
      'scope': 'workspace',
      'meeting_id': null,
      'document_id': null,
      'created_at': now,
      'updated_at': now,
    });

    expect(await db.query('chat_sessions', where: 'id = ?', whereArgs: [id]), hasLength(1));
  });

  test('rejects a meeting-scoped session with no meeting_id set', () async {
    final db = await _openAtV8();
    addTearDown(() => db.close());
    await migrateV8ToV9(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    await expectLater(
      db.insert('chat_sessions', {
        'title': 'Meeting chat',
        'scope': 'meeting',
        'meeting_id': null,
        'document_id': null,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
  });

  test('rejects a workspace-scoped session that has document_id set anyway',
      () async {
    final db = await _openAtV8();
    addTearDown(() => db.close());
    await migrateV8ToV9(db);
    final documentId = await _insertDocument(db);

    final now = DateTime(2026, 1, 1).toIso8601String();
    await expectLater(
      db.insert('chat_sessions', {
        'title': 'Bad session',
        'scope': 'workspace',
        'meeting_id': null,
        'document_id': documentId,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
  });

  test('accepts a document-scoped session with document_id set, rejects one '
      'with meeting_id set instead', () async {
    final db = await _openAtV8();
    addTearDown(() => db.close());
    await migrateV8ToV9(db);
    final documentId = await _insertDocument(db);
    final meetingId = await _insertMeeting(db);
    final now = DateTime(2026, 1, 1).toIso8601String();

    final id = await db.insert('chat_sessions', {
      'title': 'Document chat',
      'scope': 'document',
      'meeting_id': null,
      'document_id': documentId,
      'created_at': now,
      'updated_at': now,
    });
    expect(await db.query('chat_sessions', where: 'id = ?', whereArgs: [id]), hasLength(1));

    await expectLater(
      db.insert('chat_sessions', {
        'title': 'Bad document chat',
        'scope': 'document',
        'meeting_id': meetingId,
        'document_id': null,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
  });

  test('deleting a chat_sessions row cascades to its chat_messages rows',
      () async {
    final db = await _openAtV8();
    addTearDown(() => db.close());
    await migrateV8ToV9(db);
    final now = DateTime(2026, 1, 1).toIso8601String();

    final sessionId = await db.insert('chat_sessions', {
      'title': 'Workspace chat',
      'scope': 'workspace',
      'meeting_id': null,
      'document_id': null,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('chat_messages', {
      'session_id': sessionId,
      'role': 'user',
      'content': 'Hello?',
      'sources_json': null,
      'created_at': now,
    });

    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [sessionId]);

    expect(
      await db.query('chat_messages', where: 'session_id = ?', whereArgs: [sessionId]),
      isEmpty,
    );
  });

  test('deleting the owning meeting cascades to its chat_sessions rows',
      () async {
    final db = await _openAtV8();
    addTearDown(() => db.close());
    await migrateV8ToV9(db);
    final meetingId = await _insertMeeting(db);
    final now = DateTime(2026, 1, 1).toIso8601String();

    await db.insert('chat_sessions', {
      'title': 'Meeting chat',
      'scope': 'meeting',
      'meeting_id': meetingId,
      'document_id': null,
      'created_at': now,
      'updated_at': now,
    });

    await db.delete('meetings', where: 'id = ?', whereArgs: [meetingId]);

    expect(
      await db.query('chat_sessions', where: 'meeting_id = ?', whereArgs: [meetingId]),
      isEmpty,
    );
  });
}
