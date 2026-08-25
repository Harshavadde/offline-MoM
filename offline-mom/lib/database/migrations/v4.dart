import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v4: full-text search infrastructure (docs/v2/13-search-architecture.md,
/// ADR-009 in docs/v2/implementation/03-decisions.md).
///
/// Replaces `SearchMeetingsUseCase`'s old leading-wildcard `LIKE` scans
/// (which could never use an index) with a single FTS5 virtual table,
/// [ContentFtsTable], covering everything that was previously searchable
/// (meeting titles, transcripts, action items) plus two gaps that existed
/// even before this migration: summaries and notes were never searchable
/// at all. Decisions are deliberately NOT included here - they stay on
/// their existing `LIKE`-based lookup (`DecisionRepository
/// .findMeetingIdsByDescription`), unchanged, since that table is
/// permanent schema-compatibility dead weight (ADR-012) that can never
/// gain new rows in practice; folding it into this migration would add
/// surface area for zero real benefit.
///
/// [ContentFtsTable.sourceId] is always the *source row's own* primary key
/// (`meetings.id` / `transcripts.id` / `summaries.id` / `action_items.id` /
/// `notes.id`), not the owning meeting - this is what lets an UPDATE/DELETE
/// trigger on one specific row find and resync exactly the FTS row it
/// owns, even when several rows from the same source table (e.g. multiple
/// action items) belong to the same meeting.
/// [ContentFtsTable.meetingId] is always the *owning meeting's* id,
/// separately, so a search hit can be resolved straight back to the
/// [Meeting] the UI needs to open - this is why it's a plain (`UNINDEXED`)
/// column rather than something FTS5 full-text-indexes.
///
/// Every trigger pair below follows the same delete-then-reinsert pattern
/// on UPDATE, the standard, documented way to resync an FTS5 row (FTS5
/// does not support updating individual indexed columns in place the way
/// an ordinary table does). Only `notes.content` has an UPDATE trigger at
/// all - it's the only searchable column, on any of these five tables,
/// that the app actually lets a user change after the row is created
/// (`NoteRepository.update`); every other table's searchable text is set
/// once at insert and never edited in place (`meetings.title` is
/// renameable too, so it gets one as well).
///
/// The five `INSERT ... SELECT` statements at the end backfill this index
/// from whatever data already exists - a no-op on a fresh install (every
/// source table is still empty at this point in `onCreate`'s migration
/// sequence), but essential on a real upgrade from v3, where a user's
/// existing meetings/transcripts/summaries/action items/notes would
/// otherwise be invisible to search until each one was individually
/// touched again.
Future<void> migrateV3ToV4(Database db) async {
  await db.execute('''
    CREATE VIRTUAL TABLE ${ContentFtsTable.name} USING fts5(
      ${ContentFtsTable.contentType} UNINDEXED,
      ${ContentFtsTable.meetingId} UNINDEXED,
      ${ContentFtsTable.sourceId} UNINDEXED,
      ${ContentFtsTable.title},
      ${ContentFtsTable.body}
    );
  ''');

  // -- meetings (title changes via rename; searchable text is the title,
  // -- there's no separate body) -------------------------------------------
  await db.execute('''
    CREATE TRIGGER meetings_fts_ai AFTER INSERT ON ${MeetingsTable.name} BEGIN
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('meeting', NEW.${MeetingsTable.id}, NEW.${MeetingsTable.id}, NEW.${MeetingsTable.title}, '');
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER meetings_fts_au AFTER UPDATE OF ${MeetingsTable.title} ON ${MeetingsTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'meeting' AND ${ContentFtsTable.sourceId} = OLD.${MeetingsTable.id};
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('meeting', NEW.${MeetingsTable.id}, NEW.${MeetingsTable.id}, NEW.${MeetingsTable.title}, '');
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER meetings_fts_ad AFTER DELETE ON ${MeetingsTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'meeting' AND ${ContentFtsTable.sourceId} = OLD.${MeetingsTable.id};
    END;
  ''');

  // -- transcripts (insert-only; TranscriptRepository has no update/delete
  // -- method of its own - a row only ever disappears via a meeting's
  // -- cascading delete, which still fires this AFTER DELETE trigger) ------
  await db.execute('''
    CREATE TRIGGER transcripts_fts_ai AFTER INSERT ON ${TranscriptsTable.name} BEGIN
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('transcript', NEW.${TranscriptsTable.meetingId}, NEW.${TranscriptsTable.id}, NULL, NEW.${TranscriptsTable.fullText});
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER transcripts_fts_ad AFTER DELETE ON ${TranscriptsTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'transcript' AND ${ContentFtsTable.sourceId} = OLD.${TranscriptsTable.id};
    END;
  ''');

  // -- summaries (insert-only, same reasoning as transcripts; body is the
  // -- summary text + minutes of meeting + key topics, so a search matches
  // -- anything the summary screen actually shows) -------------------------
  await db.execute('''
    CREATE TRIGGER summaries_fts_ai AFTER INSERT ON ${SummariesTable.name} BEGIN
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES (
        'summary', NEW.${SummariesTable.meetingId}, NEW.${SummariesTable.id}, NULL,
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

  // -- action_items (insert-only for the description text -
  // -- ActionItemRepository.setCompleted only ever touches is_completed,
  // -- never description, so no UPDATE trigger is needed) ------------------
  await db.execute('''
    CREATE TRIGGER action_items_fts_ai AFTER INSERT ON ${ActionItemsTable.name} BEGIN
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('action_item', NEW.${ActionItemsTable.meetingId}, NEW.${ActionItemsTable.id}, NULL, NEW.${ActionItemsTable.description});
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER action_items_fts_ad AFTER DELETE ON ${ActionItemsTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'action_item' AND ${ContentFtsTable.sourceId} = OLD.${ActionItemsTable.id};
    END;
  ''');

  // -- notes (the one source table whose searchable text can genuinely be
  // -- edited after creation - NoteRepository.update - so this is the only
  // -- one of the five that needs an UPDATE trigger) ------------------------
  await db.execute('''
    CREATE TRIGGER notes_fts_ai AFTER INSERT ON ${NotesTable.name} BEGIN
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('note', NEW.${NotesTable.meetingId}, NEW.${NotesTable.id}, NULL, NEW.${NotesTable.content});
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER notes_fts_au AFTER UPDATE OF ${NotesTable.content} ON ${NotesTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'note' AND ${ContentFtsTable.sourceId} = OLD.${NotesTable.id};
      INSERT INTO ${ContentFtsTable.name}
        (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
      VALUES ('note', NEW.${NotesTable.meetingId}, NEW.${NotesTable.id}, NULL, NEW.${NotesTable.content});
    END;
  ''');
  await db.execute('''
    CREATE TRIGGER notes_fts_ad AFTER DELETE ON ${NotesTable.name} BEGIN
      DELETE FROM ${ContentFtsTable.name}
        WHERE ${ContentFtsTable.contentType} = 'note' AND ${ContentFtsTable.sourceId} = OLD.${NotesTable.id};
    END;
  ''');

  // -- backfill existing rows (no-op on a fresh install; essential on a
  // -- real v3 -> v4 upgrade) -----------------------------------------------
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
      (${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.sourceId}, ${ContentFtsTable.title}, ${ContentFtsTable.body})
    SELECT 'summary', ${SummariesTable.meetingId}, ${SummariesTable.id}, NULL,
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
}
