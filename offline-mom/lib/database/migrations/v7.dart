import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v7: retrieval infrastructure (V2 Phase 1B, M1.2 in
/// `docs/v2/implementation/01-master-roadmap.md`). Adds `knowledge_chunks`
/// only - the table ADR-009's illustrative sequence called v6, but v6 was
/// already spent in Phase 1A on the `summaries`/`content_fts` rework (see
/// ADR-018), so this is the next actually-available version number. The
/// table *design* is unchanged from `docs/v2/12-database-design.md`; only
/// its migration-file number moved, exactly the kind of ordering
/// adjustment ADR-009 already established as normal for this project.
///
/// Same two-nullable-FK + CHECK pattern as `summaries` (ADR-005): exactly
/// one of `meeting_id`/`document_id` is set per row, `ON DELETE CASCADE`
/// so deleting a meeting/document automatically removes its chunks - no
/// separate cleanup trigger or use-case step is needed for that part.
///
/// No FTS5/`content_fts` involvement here - `knowledge_chunks` is read by
/// [VectorStore] (`services/retrieval/vector_store.dart`) via a full-table
/// scan (`SqfliteKnowledgeChunkRepository.getAll`), not by any SQL
/// `MATCH`/`LIKE` query, so it needs no search index of its own.
Future<void> migrateV6ToV7(Database db) async {
  await db.execute('''
    CREATE TABLE ${KnowledgeChunksTable.name} (
      ${KnowledgeChunksTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${KnowledgeChunksTable.meetingId} INTEGER,
      ${KnowledgeChunksTable.documentId} INTEGER,
      ${KnowledgeChunksTable.chunkIndex} INTEGER NOT NULL,
      ${KnowledgeChunksTable.chunkText} TEXT NOT NULL,
      ${KnowledgeChunksTable.embedding} BLOB NOT NULL,
      ${KnowledgeChunksTable.embeddingDim} INTEGER NOT NULL,
      ${KnowledgeChunksTable.createdAt} TEXT NOT NULL,
      FOREIGN KEY (${KnowledgeChunksTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE,
      FOREIGN KEY (${KnowledgeChunksTable.documentId})
        REFERENCES ${DocumentsTable.name} (${DocumentsTable.id})
        ON DELETE CASCADE,
      CHECK (
        (${KnowledgeChunksTable.meetingId} IS NOT NULL)
        <> (${KnowledgeChunksTable.documentId} IS NOT NULL)
      )
    );
  ''');
  await db.execute(
    'CREATE INDEX idx_knowledge_chunks_meeting_id ON ${KnowledgeChunksTable.name} (${KnowledgeChunksTable.meetingId});',
  );
  await db.execute(
    'CREATE INDEX idx_knowledge_chunks_document_id ON ${KnowledgeChunksTable.name} (${KnowledgeChunksTable.documentId});',
  );
}
