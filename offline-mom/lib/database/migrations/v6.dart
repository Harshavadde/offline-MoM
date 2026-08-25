import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v6: makes documents fully first-class in the shared `summaries` table
/// and the FTS5 search index, in one migration rather than two - both
/// changes touch the same two objects (`summaries`, `content_fts`) and
/// splitting them would mean recreating `summaries`' FTS triggers twice
/// for no benefit. This is an implementation-level refinement of ADR-009's
/// illustrative v5/v6/v7 split (docs/v2/implementation/03-decisions.md) -
/// the table designs it describes are unchanged, only which migration
/// file does the work.
///
/// Part 1 - `summaries` table rebuild (ADR-005): SQLite's `ALTER TABLE`
/// can't add a CHECK constraint or drop a NOT NULL constraint on an
/// existing column, so this uses SQLite's standard workaround: build the
/// new shape as `summaries_new`, copy every existing row across (with
/// `document_id` left NULL, since no summary belonged to a document
/// before this migration), drop the old table, rename the new one into
/// place. Dropping `summaries` also silently drops the triggers migration
/// v4 created on it - Part 3 recreates them.
///
/// Part 2 - `content_fts` gains a `document_id` column. Unlike an ordinary
/// table, an FTS5 virtual table does not support `ALTER TABLE ... ADD
/// COLUMN` at all (SQLite raises "virtual tables may not be altered"), so
/// this uses the same drop-and-rebuild approach as `summaries` above: drop
/// `content_fts` and recreate it with `document_id` present from the
/// start. Dropping it discards every row currently indexed, so the
/// backfill at the end of this migration re-populates all of it, not just
/// documents/summaries - the same five `INSERT ... SELECT`s v4 ran,
/// repeated here for the same reason v4 needed them on a v3 upgrade.
///
/// Part 3 - triggers: `summaries`' FTS triggers are recreated to write
/// whichever of `meeting_id`/`document_id` is actually set on the row
/// (exactly one, per the CHECK constraint); `documents` gains its own
/// insert/update/delete triggers (title changes via rename, same as
/// `meetings`; `extracted_text` is set once by the extraction pipeline and
/// never edited directly, so - like `transcripts`/`action_items` in v4 -
/// it only needs insert/delete triggers, not an update one).
Future<void> migrateV5ToV6(Database db) async {
  // -- Part 1: rebuild `summaries` --------------------------------------
  await db.execute('''
    CREATE TABLE summaries_new (
      ${SummariesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${SummariesTable.meetingId} INTEGER,
      ${SummariesTable.documentId} INTEGER,
      ${SummariesTable.summaryText} TEXT NOT NULL,
      ${SummariesTable.minutesOfMeeting} TEXT NOT NULL,
      ${SummariesTable.keyTopicsJson} TEXT NOT NULL,
      ${SummariesTable.modelUsed} TEXT NOT NULL,
      ${SummariesTable.generatedAt} TEXT NOT NULL,
      FOREIGN KEY (${SummariesTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE,
      FOREIGN KEY (${SummariesTable.documentId})
        REFERENCES ${DocumentsTable.name} (${DocumentsTable.id})
        ON DELETE CASCADE,
      CHECK (
        (${SummariesTable.meetingId} IS NOT NULL)
        <> (${SummariesTable.documentId} IS NOT NULL)
      )
    );
  ''');
  await db.execute('''
    INSERT INTO summaries_new
      (${SummariesTable.id}, ${SummariesTable.meetingId}, ${SummariesTable.documentId},
       ${SummariesTable.summaryText}, ${SummariesTable.minutesOfMeeting},
       ${SummariesTable.keyTopicsJson}, ${SummariesTable.modelUsed}, ${SummariesTable.generatedAt})
    SELECT ${SummariesTable.id}, ${SummariesTable.meetingId}, NULL,
       ${SummariesTable.summaryText}, ${SummariesTable.minutesOfMeeting},
       ${SummariesTable.keyTopicsJson}, ${SummariesTable.modelUsed}, ${SummariesTable.generatedAt}
    FROM ${SummariesTable.name};
  ''');
  await db.execute('DROP TABLE ${SummariesTable.name};');
  await db.execute('ALTER TABLE summaries_new RENAME TO ${SummariesTable.name};');
  await db.execute(
    'CREATE INDEX idx_summaries_meeting_id ON ${SummariesTable.name} (${SummariesTable.meetingId});',
  );
  await db.execute(
    'CREATE INDEX idx_summaries_document_id ON ${SummariesTable.name} (${SummariesTable.documentId});',
  );

  // -- Part 2: content_fts gains document_id (rebuild - see doc comment) -
  await db.execute('DROP TABLE ${ContentFtsTable.name};');
  await db.execute('''
    CREATE VIRTUAL TABLE ${ContentFtsTable.name} USING fts5(
      ${ContentFtsTable.contentType} UNINDEXED,
      ${ContentFtsTable.meetingId} UNINDEXED,
      ${ContentFtsTable.documentId} UNINDEXED,
      ${ContentFtsTable.sourceId} UNINDEXED,
      ${ContentFtsTable.title},
      ${ContentFtsTable.body}
    );
  ''');

  // -- Part 3a: recreate summaries' FTS triggers (meeting- or
  // document-owned, whichever NEW actually has set) ----------------------
  await db.execute('''
    CREATE TRIGGER summaries_fts_ai AFTER INSERT ON ${SummariesTable.name} BEGIN
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.documentId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES (
        'summary', NEW.${SummariesTable.meetingId}, NEW.${SummariesTable.documentId}, NEW.${SummariesTable.id}, NULL,
        NEW.${SummariesTable.summaryText} || ' ' || NEW.${SummariesTable.minutesOfMeeting} || ' ' || NEW.${SummariesTable.keyTopicsJson}
      );
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER summaries_fts_ad AFTER DELETE ON ${SummariesTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'summary' AND ${ContentFtsTable.sourceId} = OLD.${SummariesTable.id};
    END;
  ''');

  // -- Part 3b: documents' own FTS triggers -------------------------------
  await db.execute('''
    CREATE TRIGGER documents_fts_ai AFTER INSERT ON ${DocumentsTable.name} BEGIN
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.documentId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('document', NEW.${DocumentsTable.id}, NEW.${DocumentsTable.id}, NEW.${DocumentsTable.title}, '');
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER documents_fts_au AFTER UPDATE OF ${DocumentsTable.title} ON ${DocumentsTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'document' AND ${ContentFtsTable.sourceId} = OLD.${DocumentsTable.id};
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.documentId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('document', NEW.${DocumentsTable.id}, NEW.${DocumentsTable.id}, NEW.${DocumentsTable.title}, '');
    END;
  ''');
  // Deletes both the 'document' (title) and 'document_text' (extracted
  // text) rows for this document - both share the same source_id
  // (the document's own id), so one trigger clears both content types
  // rather than needing a second AFTER DELETE trigger.
  await db.execute('''
    CREATE TRIGGER documents_fts_ad AFTER DELETE ON ${DocumentsTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} IN ('document', 'document_text')
          AND ${ContentFtsTable.sourceId} = OLD.${DocumentsTable.id};
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER document_text_fts_au AFTER UPDATE OF ${DocumentsTable.extractedText} ON ${DocumentsTable.name}
    WHEN NEW.${DocumentsTable.extractedText} IS NOT NULL BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'document_text' AND ${ContentFtsTable.sourceId} = NEW.${DocumentsTable.id};
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.documentId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('document_text', NEW.${DocumentsTable.id}, NEW.${DocumentsTable.id}, NULL, NEW.${DocumentsTable.extractedText});
    END;
  ''');

  // -- Backfill: content_fts was just dropped and recreated empty (Part 2),
  // so every content type v4 originally indexed needs re-inserting, not
  // just summaries/documents - a no-op on a fresh install (every source
  // table is still empty at this point in onCreate's migration sequence),
  // but essential on a real upgrade, same reasoning as v4's own backfill. -
  await db.execute('''
    INSERT INTO ${ContentFtsTable.name}
      (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'meeting', ${MeetingsTable.id}, ${MeetingsTable.id}, ${MeetingsTable.title}, ''
    FROM ${MeetingsTable.name};
  ''');
  await db.execute('''
    INSERT INTO ${ContentFtsTable.name}
      (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'transcript', ${TranscriptsTable.meetingId}, ${TranscriptsTable.id}, NULL, ${TranscriptsTable.fullText}
    FROM ${TranscriptsTable.name};
  ''');
  await db.execute('''
    INSERT INTO ${ContentFtsTable.name}
      (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.documentId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'summary', ${SummariesTable.meetingId}, ${SummariesTable.documentId}, ${SummariesTable.id}, NULL,
      ${SummariesTable.summaryText} || ' ' || ${SummariesTable.minutesOfMeeting} || ' ' || ${SummariesTable.keyTopicsJson}
    FROM ${SummariesTable.name};
  ''');
  await db.execute('''
    INSERT INTO ${ContentFtsTable.name}
      (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'action_item', ${ActionItemsTable.meetingId}, ${ActionItemsTable.id}, NULL, ${ActionItemsTable.description}
    FROM ${ActionItemsTable.name};
  ''');
  await db.execute('''
    INSERT INTO ${ContentFtsTable.name}
      (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'note', ${NotesTable.meetingId}, ${NotesTable.id}, NULL, ${NotesTable.content}
    FROM ${NotesTable.name};
  ''');
  await db.execute('''
    INSERT INTO ${ContentFtsTable.name}
      (${ContentFtsTable.contentType}, ${ContentFtsTable.documentId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'document', ${DocumentsTable.id}, ${DocumentsTable.id}, ${DocumentsTable.title}, ''
    FROM ${DocumentsTable.name};
  ''');
  await db.execute('''
    INSERT INTO ${ContentFtsTable.name}
      (${ContentFtsTable.contentType}, ${ContentFtsTable.documentId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'document_text', ${DocumentsTable.id}, ${DocumentsTable.id}, NULL, ${DocumentsTable.extractedText}
    FROM ${DocumentsTable.name}
    WHERE ${DocumentsTable.extractedText} IS NOT NULL;
  ''');
}
