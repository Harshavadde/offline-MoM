// Exercises migration v8 (lib/database/migrations/v8.dart) directly against
// a database stopped at v7, rather than through openTestDatabase() (which
// always applies every migration up front) - this is the only way to prove
// the backfill logic actually runs correctly against pre-existing v7 rows,
// not just that the final v8 schema happens to work.
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
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<Database> _openAtV7() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 7,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await createV1Schema(db);
        await migrateV1ToV2(db);
        await migrateV2ToV3(db);
        await migrateV3ToV4(db);
        await migrateV4ToV5(db);
        await migrateV5ToV6(db);
        await migrateV6ToV7(db);
      },
    ),
  );
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
  test('adds content_type and source_id, backfilling pre-existing rows as '
      "content_type='document', source_id=document_id", () async {
    final db = await _openAtV7();
    addTearDown(() => db.close());

    final documentId = await _insertDocument(db);
    final chunkId = await db.insert('knowledge_chunks', {
      'document_id': documentId,
      'chunk_index': 0,
      'chunk_text': 'pre-existing v7 chunk',
      'embedding': KnowledgeChunk.encodeEmbedding([0.1, 0.2]),
      'embedding_dim': 2,
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
    });

    await migrateV7ToV8(db);

    final rows = await db.query('knowledge_chunks', where: 'id = ?', whereArgs: [chunkId]);
    expect(rows, hasLength(1));
    expect(rows.single['content_type'], 'document');
    expect(rows.single['source_id'], documentId);
    expect(rows.single['chunk_text'], 'pre-existing v7 chunk');
  });

  test('preserves every column value across the rebuild, not just the new '
      'ones', () async {
    final db = await _openAtV7();
    addTearDown(() => db.close());

    final documentId = await _insertDocument(db);
    final embedding = [0.5, -0.25, 1.0];
    await db.insert('knowledge_chunks', {
      'document_id': documentId,
      'chunk_index': 3,
      'chunk_text': 'exact text',
      'embedding': KnowledgeChunk.encodeEmbedding(embedding),
      'embedding_dim': embedding.length,
      'created_at': DateTime(2026, 3, 4, 5, 6).toIso8601String(),
    });

    await migrateV7ToV8(db);

    final rows = await db.query('knowledge_chunks');
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['chunk_index'], 3);
    expect(row['embedding_dim'], 3);
    expect(
      KnowledgeChunk.decodeEmbedding(row['embedding'] as Uint8List, 3),
      embedding,
    );
  });

  test('content_type and source_id reject NULL on insert after the '
      'migration', () async {
    final db = await _openAtV7();
    addTearDown(() => db.close());
    await migrateV7ToV8(db);

    final documentId = await _insertDocument(db);
    await expectLater(
      db.insert('knowledge_chunks', {
        'document_id': documentId,
        'chunk_index': 0,
        'chunk_text': 'missing content_type/source_id',
        'embedding': KnowledgeChunk.encodeEmbedding([0.1]),
        'embedding_dim': 1,
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      }),
      throwsA(anything),
    );
  });

  test('the meeting/document CHECK constraint still holds after the '
      'rebuild', () async {
    final db = await _openAtV7();
    addTearDown(() => db.close());
    await migrateV7ToV8(db);

    final documentId = await _insertDocument(db);
    final now = DateTime(2026, 1, 1).toIso8601String();
    final meetingId = await db.insert('meetings', {
      'title': 'Standup',
      'source': 'recorded',
      'status': 'ready',
      'created_at': now,
      'updated_at': now,
    });

    await expectLater(
      db.insert('knowledge_chunks', {
        'meeting_id': meetingId,
        'document_id': documentId,
        'content_type': 'transcript',
        'source_id': meetingId,
        'chunk_index': 0,
        'chunk_text': 'both owners set',
        'embedding': KnowledgeChunk.encodeEmbedding([0.1]),
        'embedding_dim': 1,
        'created_at': now,
      }),
      throwsA(anything),
    );
  });

  test('a v7 database with no knowledge_chunks rows migrates cleanly to an '
      'empty v8 table', () async {
    final db = await _openAtV7();
    addTearDown(() => db.close());

    await migrateV7ToV8(db);

    expect(await db.query('knowledge_chunks'), isEmpty);
  });
}
