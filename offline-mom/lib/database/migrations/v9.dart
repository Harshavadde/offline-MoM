import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v9: `chat_sessions` + `chat_messages` (V2 Phase 2A, ADR-025,
/// docs/v2/implementation/03-decisions.md). Not v8 as `docs/v2/12-database
/// -design.md`'s illustrative sequence originally numbered it - v8 was
/// already spent in Phase 1C on `knowledge_chunks.content_type`/`source_id`
/// (ADR-021), the same "the illustrative number moved" situation ADR-019
/// resolved once before for `knowledge_chunks` itself.
///
/// `chat_sessions.scope` picks which of `meeting_id`/`document_id` (if
/// either) applies - `general` and `workspace` set neither, `document`
/// sets only `document_id`, `meeting` sets only `meeting_id`. Enforced by a
/// CHECK constraint rather than trusted to application code alone, per
/// this project's established two-nullable-FK convention (ADR-005),
/// extended here to a three-way discriminated shape since a chat session
/// (unlike a summary or knowledge chunk) can legitimately belong to
/// neither owner at all.
///
/// `chat_messages.session_id` cascades on `chat_sessions` delete, so
/// deleting a conversation removes every one of its messages automatically
/// - no separate cleanup use case/trigger needed (mirrors every other
/// owned-child-table relationship in this schema).
Future<void> migrateV8ToV9(Database db) async {
  await db.execute('''
    CREATE TABLE ${ChatSessionsTable.name} (
      ${ChatSessionsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${ChatSessionsTable.title} TEXT NOT NULL,
      ${ChatSessionsTable.scope} TEXT NOT NULL,
      ${ChatSessionsTable.meetingId} INTEGER,
      ${ChatSessionsTable.documentId} INTEGER,
      ${ChatSessionsTable.createdAt} TEXT NOT NULL,
      ${ChatSessionsTable.updatedAt} TEXT NOT NULL,
      FOREIGN KEY (${ChatSessionsTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE,
      FOREIGN KEY (${ChatSessionsTable.documentId})
        REFERENCES ${DocumentsTable.name} (${DocumentsTable.id})
        ON DELETE CASCADE,
      CHECK (
        (${ChatSessionsTable.scope} = 'meeting') = (${ChatSessionsTable.meetingId} IS NOT NULL)
      ),
      CHECK (
        (${ChatSessionsTable.scope} = 'document') = (${ChatSessionsTable.documentId} IS NOT NULL)
      )
    );
  ''');
  await db.execute(
    'CREATE INDEX idx_chat_sessions_meeting_id ON ${ChatSessionsTable.name} (${ChatSessionsTable.meetingId});',
  );
  await db.execute(
    'CREATE INDEX idx_chat_sessions_document_id ON ${ChatSessionsTable.name} (${ChatSessionsTable.documentId});',
  );

  await db.execute('''
    CREATE TABLE ${ChatMessagesTable.name} (
      ${ChatMessagesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${ChatMessagesTable.sessionId} INTEGER NOT NULL,
      ${ChatMessagesTable.role} TEXT NOT NULL,
      ${ChatMessagesTable.content} TEXT NOT NULL,
      ${ChatMessagesTable.sourcesJson} TEXT,
      ${ChatMessagesTable.createdAt} TEXT NOT NULL,
      FOREIGN KEY (${ChatMessagesTable.sessionId})
        REFERENCES ${ChatSessionsTable.name} (${ChatSessionsTable.id})
        ON DELETE CASCADE
    );
  ''');
  await db.execute(
    'CREATE INDEX idx_chat_messages_session_id ON ${ChatMessagesTable.name} (${ChatMessagesTable.sessionId});',
  );
}
