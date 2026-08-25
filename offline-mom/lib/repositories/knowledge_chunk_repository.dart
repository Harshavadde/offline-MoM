import 'package:sqflite/sqflite.dart';

import '../core/knowledge/content_type.dart';
import '../database/tables.dart';
import '../models/knowledge_chunk.dart';

/// Ordinary row access (insert/lookup/delete) for [KnowledgeChunk] rows -
/// distinct from [VectorStore] (services/retrieval/vector_store.dart),
/// which handles similarity search specifically. See
/// docs/v2/10-system-architecture.md's split between "Repositories" and
/// "AI/Retrieval" in its component diagram.
abstract class KnowledgeChunkRepository {
  Future<int> insert(KnowledgeChunk chunk);

  /// Inserts every chunk produced for one meeting/document in a single
  /// batch - [DefaultIndexingService] always has the full chunk set for
  /// one content item available at once (chunking + embedding both run
  /// before any persistence), so there is never a reason to insert one
  /// row at a time during indexing.
  Future<void> insertAll(List<KnowledgeChunk> chunks);

  /// Deletes every chunk belonging to one specific prose source (e.g.
  /// "the transcript of meeting 5", "note 12", "document 3's extracted
  /// text") - the granularity [DefaultIndexingService] re-indexes at
  /// (ADR-021, docs/v2/implementation/03-decisions.md). Deliberately not
  /// scoped by [KnowledgeChunk.meetingId]/[KnowledgeChunk.documentId]
  /// alone: a meeting owns several independently-changing sources sharing
  /// one `meetingId` (its transcript, its summary, each of its notes), so
  /// an owner-scoped delete would wipe all of them on every single
  /// source's re-index.
  Future<void> deleteForSource(ContentType contentType, int sourceId);

  Future<List<KnowledgeChunk>> getForMeeting(int meetingId);
  Future<List<KnowledgeChunk>> getForDocument(int documentId);

  /// Every chunk in the corpus - [BruteForceVectorStore]'s similarity
  /// search scans this in full (ADR-004: brute-force Dart cosine
  /// similarity, no separate vector engine), which is the entire reason
  /// this method exists rather than only ever querying by owner.
  Future<List<KnowledgeChunk>> getAll();
}

class SqfliteKnowledgeChunkRepository implements KnowledgeChunkRepository {
  SqfliteKnowledgeChunkRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(KnowledgeChunk chunk) {
    final map = chunk.toMap()..remove(KnowledgeChunksTable.id);
    return _db.insert(KnowledgeChunksTable.name, map);
  }

  @override
  Future<void> insertAll(List<KnowledgeChunk> chunks) async {
    if (chunks.isEmpty) return;
    final batch = _db.batch();
    for (final chunk in chunks) {
      final map = chunk.toMap()..remove(KnowledgeChunksTable.id);
      batch.insert(KnowledgeChunksTable.name, map);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> deleteForSource(ContentType contentType, int sourceId) async {
    await _db.delete(
      KnowledgeChunksTable.name,
      where: '${KnowledgeChunksTable.contentType} = ? AND ${KnowledgeChunksTable.sourceId} = ?',
      whereArgs: [contentType.name, sourceId],
    );
  }

  @override
  Future<List<KnowledgeChunk>> getForMeeting(int meetingId) async {
    final rows = await _db.query(
      KnowledgeChunksTable.name,
      where: '${KnowledgeChunksTable.meetingId} = ?',
      whereArgs: [meetingId],
      orderBy: '${KnowledgeChunksTable.chunkIndex} ASC',
    );
    return rows.map(KnowledgeChunk.fromMap).toList();
  }

  @override
  Future<List<KnowledgeChunk>> getForDocument(int documentId) async {
    final rows = await _db.query(
      KnowledgeChunksTable.name,
      where: '${KnowledgeChunksTable.documentId} = ?',
      whereArgs: [documentId],
      orderBy: '${KnowledgeChunksTable.chunkIndex} ASC',
    );
    return rows.map(KnowledgeChunk.fromMap).toList();
  }

  @override
  Future<List<KnowledgeChunk>> getAll() async {
    final rows = await _db.query(KnowledgeChunksTable.name);
    return rows.map(KnowledgeChunk.fromMap).toList();
  }
}
