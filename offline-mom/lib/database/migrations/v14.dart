import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v14 (V2 Phase 6B, Hybrid Retrieval Engine, ADR-037): two independent,
/// minimum-additive schema changes -
///
/// 1. [KnowledgeChunksFtsTable] - a new FTS5 "external content" virtual
///    table over `knowledge_chunks.chunk_text`, trigger-synced so it's
///    never out of date with the source table (see that table's own doc
///    comment for why this is a *second*, chunk-granularity index, not an
///    extension of the existing `content_fts`). `content=knowledge_chunks,
///    content_rowid=id` means the chunk text itself is never duplicated on
///    disk - only the FTS5 index structures are stored.
/// 2. `chat_messages.answer_provenance` - one new nullable column, the same
///    "exactly one concrete field, not a speculative blob" discipline
///    ADR-033's `page_count` and ADR-036's `installed_models` columns
///    already established.
///
/// No existing table's data is touched or migrated by either change.
Future<void> migrateV13ToV14(Database db) async {
  await db.execute('''
    CREATE VIRTUAL TABLE ${KnowledgeChunksFtsTable.name} USING fts5(
      ${KnowledgeChunksFtsTable.chunkText},
      content='${KnowledgeChunksTable.name}',
      content_rowid='${KnowledgeChunksTable.id}'
    );
  ''');

  // Backfill: existing chunks (if any - e.g. an upgrading install) must be
  // indexed too, not just chunks inserted from this point forward.
  await db.execute('''
    INSERT INTO ${KnowledgeChunksFtsTable.name}(rowid, ${KnowledgeChunksFtsTable.chunkText})
    SELECT ${KnowledgeChunksTable.id}, ${KnowledgeChunksTable.chunkText} FROM ${KnowledgeChunksTable.name};
  ''');

  await db.execute('''
    CREATE TRIGGER knowledge_chunks_fts_ai AFTER INSERT ON ${KnowledgeChunksTable.name} BEGIN
      INSERT INTO ${KnowledgeChunksFtsTable.name}(rowid, ${KnowledgeChunksFtsTable.chunkText})
      VALUES (new.${KnowledgeChunksTable.id}, new.${KnowledgeChunksTable.chunkText});
    END;
  ''');

  await db.execute('''
    CREATE TRIGGER knowledge_chunks_fts_ad AFTER DELETE ON ${KnowledgeChunksTable.name} BEGIN
      INSERT INTO ${KnowledgeChunksFtsTable.name}(${KnowledgeChunksFtsTable.name}, rowid, ${KnowledgeChunksFtsTable.chunkText})
      VALUES('delete', old.${KnowledgeChunksTable.id}, old.${KnowledgeChunksTable.chunkText});
    END;
  ''');

  await db.execute('''
    CREATE TRIGGER knowledge_chunks_fts_au AFTER UPDATE ON ${KnowledgeChunksTable.name} BEGIN
      INSERT INTO ${KnowledgeChunksFtsTable.name}(${KnowledgeChunksFtsTable.name}, rowid, ${KnowledgeChunksFtsTable.chunkText})
      VALUES('delete', old.${KnowledgeChunksTable.id}, old.${KnowledgeChunksTable.chunkText});
      INSERT INTO ${KnowledgeChunksFtsTable.name}(rowid, ${KnowledgeChunksFtsTable.chunkText})
      VALUES (new.${KnowledgeChunksTable.id}, new.${KnowledgeChunksTable.chunkText});
    END;
  ''');

  await db.execute('''
    ALTER TABLE ${ChatMessagesTable.name}
    ADD COLUMN ${ChatMessagesTable.answerProvenance} TEXT;
  ''');
}
