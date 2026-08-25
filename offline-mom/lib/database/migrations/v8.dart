import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v8: `knowledge_chunks` gains `content_type` + `source_id` (V2 Phase 1C,
/// ADR-021, docs/v2/implementation/03-decisions.md). Rebuilds the table
/// (SQLite can't add a NOT NULL column without a single constant default,
/// and `source_id`'s correct value varies per row - same standard
/// create-copy-drop-rename workaround already used for `summaries` in
/// migration v6, ADR-005/018) rather than `ALTER TABLE ... ADD COLUMN`.
///
/// Why this is needed: Phase 1B's `knowledge_chunks` only ever indexed one
/// prose source per owner (a document's whole extracted text), so
/// `meeting_id`/`document_id` alone was enough to scope a re-index's
/// delete-then-reinsert safely. Phase 1C indexes three independently
/// -changing prose sources under the same meeting (its transcript, its
/// summary, each of its notes) - re-indexing one (e.g. a single edited
/// note) must never delete another's chunks, which `deleteForMeeting`
/// alone could not distinguish. `content_type` + `source_id` (mirroring
/// `content_fts.content_type`/`source_id`'s already-proven purpose
/// exactly) gives every independently-indexable piece of content its own
/// scope, while `meeting_id`/`document_id` are kept unchanged for the
/// existing owner-level queries (`getForMeeting`/`getForDocument`) and for
/// `ON DELETE CASCADE` when the owning meeting/document itself is
/// deleted.
///
/// Backfill: every row that exists before this migration is
/// document-owned (Phase 1B never indexed meetings) and always
/// corresponds to a whole document's extracted text - so `content_type =
/// 'document'` and `source_id = document_id` for every pre-existing row
/// is not a guess, it's the only value Phase 1B's code ever wrote.
Future<void> migrateV7ToV8(Database db) async {
  await db.execute('''
    CREATE TABLE knowledge_chunks_new (
      ${KnowledgeChunksTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${KnowledgeChunksTable.meetingId} INTEGER,
      ${KnowledgeChunksTable.documentId} INTEGER,
      ${KnowledgeChunksTable.contentType} TEXT NOT NULL,
      ${KnowledgeChunksTable.sourceId} INTEGER NOT NULL,
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

  await db.execute('''
    INSERT INTO knowledge_chunks_new
      (${KnowledgeChunksTable.id}, ${KnowledgeChunksTable.meetingId}, ${KnowledgeChunksTable.documentId},
       ${KnowledgeChunksTable.contentType}, ${KnowledgeChunksTable.sourceId},
       ${KnowledgeChunksTable.chunkIndex}, ${KnowledgeChunksTable.chunkText},
       ${KnowledgeChunksTable.embedding}, ${KnowledgeChunksTable.embeddingDim}, ${KnowledgeChunksTable.createdAt})
    SELECT ${KnowledgeChunksTable.id}, ${KnowledgeChunksTable.meetingId}, ${KnowledgeChunksTable.documentId},
       'document', ${KnowledgeChunksTable.documentId},
       ${KnowledgeChunksTable.chunkIndex}, ${KnowledgeChunksTable.chunkText},
       ${KnowledgeChunksTable.embedding}, ${KnowledgeChunksTable.embeddingDim}, ${KnowledgeChunksTable.createdAt}
    FROM ${KnowledgeChunksTable.name};
  ''');

  await db.execute('DROP TABLE ${KnowledgeChunksTable.name};');
  await db.execute('ALTER TABLE knowledge_chunks_new RENAME TO ${KnowledgeChunksTable.name};');

  await db.execute(
    'CREATE INDEX idx_knowledge_chunks_meeting_id ON ${KnowledgeChunksTable.name} (${KnowledgeChunksTable.meetingId});',
  );
  await db.execute(
    'CREATE INDEX idx_knowledge_chunks_document_id ON ${KnowledgeChunksTable.name} (${KnowledgeChunksTable.documentId});',
  );
  await db.execute(
    'CREATE INDEX idx_knowledge_chunks_content_type_source_id ON ${KnowledgeChunksTable.name} '
    '(${KnowledgeChunksTable.contentType}, ${KnowledgeChunksTable.sourceId});',
  );
}
