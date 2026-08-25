// Exercises migration v14 (lib/database/migrations/v14.dart, V2 Phase 6B,
// Hybrid Retrieval Engine) against a database stopped at v13, mirroring
// migration_v13_test.dart's pattern.
import 'dart:typed_data';

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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV13() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 13,
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

Future<int> _insertChunk(Database db, {required String text, required int meetingId}) {
  final now = DateTime(2026, 1, 1).toIso8601String();
  return db.insert('knowledge_chunks', {
    'meeting_id': meetingId,
    'document_id': null,
    'content_type': 'transcript',
    'source_id': 1,
    'chunk_index': 0,
    'chunk_text': text,
    'embedding': Uint8List.fromList(List.filled(8, 0)),
    'embedding_dim': 1,
    'created_at': now,
  });
}

void main() {
  test('creates knowledge_chunks_fts and keeps it in sync via triggers on insert', () async {
    final db = await _openAtV13();
    addTearDown(() => db.close());
    await migrateV13ToV14(db);

    final meetingId = await _insertMeeting(db);
    final id = await _insertChunk(db, text: 'the quarterly budget was approved', meetingId: meetingId);

    final matches = await db.rawQuery(
      "SELECT rowid FROM knowledge_chunks_fts WHERE knowledge_chunks_fts MATCH 'budget'",
    );
    expect(matches.map((r) => r['rowid']), contains(id));
  });

  test('deleting a chunk removes it from the FTS index too', () async {
    final db = await _openAtV13();
    addTearDown(() => db.close());
    await migrateV13ToV14(db);

    final meetingId = await _insertMeeting(db);
    final id = await _insertChunk(db, text: 'a unique searchable phrase', meetingId: meetingId);
    await db.delete('knowledge_chunks', where: 'id = ?', whereArgs: [id]);

    final matches = await db.rawQuery(
      "SELECT rowid FROM knowledge_chunks_fts WHERE knowledge_chunks_fts MATCH 'unique'",
    );
    expect(matches, isEmpty);
  });

  test('a query for a term present in one chunk but not another only matches that chunk', () async {
    final db = await _openAtV13();
    addTearDown(() => db.close());
    await migrateV13ToV14(db);

    final meetingId = await _insertMeeting(db);
    final relevantId =
        await _insertChunk(db, text: 'the roadmap discussion covered pricing', meetingId: meetingId);
    await _insertChunk(db, text: 'lunch order for the team offsite', meetingId: meetingId);

    final matches = await db.rawQuery(
      "SELECT rowid FROM knowledge_chunks_fts WHERE knowledge_chunks_fts MATCH 'roadmap'",
    );
    expect(matches.map((r) => r['rowid']).toList(), [relevantId]);
  });

  test('bm25() ranking is usable against the new index (confirms real BM25, not just MATCH)', () async {
    final db = await _openAtV13();
    addTearDown(() => db.close());
    await migrateV13ToV14(db);

    final meetingId = await _insertMeeting(db);
    await _insertChunk(
      db,
      text: 'budget budget budget budget - heavily about budget',
      meetingId: meetingId,
    );
    await _insertChunk(db, text: 'a passing mention of the budget once', meetingId: meetingId);

    final rows = await db.rawQuery(
      "SELECT rowid, bm25(knowledge_chunks_fts) AS rank FROM knowledge_chunks_fts "
      "WHERE knowledge_chunks_fts MATCH 'budget' ORDER BY rank ASC",
    );
    expect(rows, hasLength(2));
    // bm25() is "more negative = better" - the heavily-repeated-term chunk
    // should rank first (lower/more negative value).
    expect((rows[0]['rank'] as num), lessThan(rows[1]['rank'] as num));
  });

  test('existing chunks from before the migration are backfilled into the index', () async {
    final db = await _openAtV13();
    addTearDown(() => db.close());
    // Insert *before* the migration runs, simulating an upgrading install
    // with pre-existing chunks.
    final meetingId = await _insertMeeting(db);
    final id =
        await _insertChunk(db, text: 'a chunk that existed before v14 was indexed', meetingId: meetingId);
    await migrateV13ToV14(db);

    final matches = await db.rawQuery(
      "SELECT rowid FROM knowledge_chunks_fts WHERE knowledge_chunks_fts MATCH 'existed'",
    );
    expect(matches.map((r) => r['rowid']), contains(id));
  });

  test('adds chat_messages.answer_provenance, nullable, defaulting to null for pre-existing rows', () async {
    final db = await _openAtV13();
    addTearDown(() => db.close());

    final sessionId = await db.insert('chat_sessions', {
      'title': 'A conversation',
      'scope': 'workspace',
      'meeting_id': null,
      'document_id': null,
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
      'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      'is_pinned': 0,
    });
    final messageId = await db.insert('chat_messages', {
      'session_id': sessionId,
      'role': 'user',
      'content': 'hello',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
      'sources_json': null,
    });

    await migrateV13ToV14(db);

    final rows = await db.query('chat_messages', where: 'id = ?', whereArgs: [messageId]);
    expect(rows.single['answer_provenance'], isNull);
  });

  test('answer_provenance can be set to local/general_knowledge and read back', () async {
    final db = await _openAtV13();
    addTearDown(() => db.close());
    await migrateV13ToV14(db);

    final sessionId = await db.insert('chat_sessions', {
      'title': 'A conversation',
      'scope': 'workspace',
      'meeting_id': null,
      'document_id': null,
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
      'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      'is_pinned': 0,
    });
    final id = await db.insert('chat_messages', {
      'session_id': sessionId,
      'role': 'assistant',
      'content': 'an answer',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
      'sources_json': null,
      'answer_provenance': 'generalKnowledge',
    });

    final rows = await db.query('chat_messages', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['answer_provenance'], 'generalKnowledge');
  });
}
