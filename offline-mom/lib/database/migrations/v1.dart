import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// Initial schema (database version 1).
///
/// Foreign keys cascade on delete so removing a [MeetingsTable] row cleans up
/// every dependent transcript/summary/action item/decision automatically —
/// deleting a meeting from History never leaves orphan rows behind.
Future<void> createV1Schema(Database db) async {
  await db.execute('''
    CREATE TABLE ${MeetingsTable.name} (
      ${MeetingsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${MeetingsTable.title} TEXT NOT NULL,
      ${MeetingsTable.source} TEXT NOT NULL,
      ${MeetingsTable.status} TEXT NOT NULL,
      ${MeetingsTable.createdAt} TEXT NOT NULL,
      ${MeetingsTable.updatedAt} TEXT NOT NULL,
      ${MeetingsTable.durationSeconds} INTEGER NOT NULL DEFAULT 0,
      ${MeetingsTable.audioFilePath} TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE ${TranscriptsTable.name} (
      ${TranscriptsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${TranscriptsTable.meetingId} INTEGER NOT NULL,
      ${TranscriptsTable.language} TEXT NOT NULL,
      ${TranscriptsTable.fullText} TEXT NOT NULL,
      ${TranscriptsTable.segmentsJson} TEXT NOT NULL,
      ${TranscriptsTable.createdAt} TEXT NOT NULL,
      FOREIGN KEY (${TranscriptsTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE
    );
  ''');

  await db.execute('''
    CREATE TABLE ${SummariesTable.name} (
      ${SummariesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${SummariesTable.meetingId} INTEGER NOT NULL,
      ${SummariesTable.summaryText} TEXT NOT NULL,
      ${SummariesTable.minutesOfMeeting} TEXT NOT NULL,
      ${SummariesTable.keyTopicsJson} TEXT NOT NULL,
      ${SummariesTable.modelUsed} TEXT NOT NULL,
      ${SummariesTable.generatedAt} TEXT NOT NULL,
      FOREIGN KEY (${SummariesTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE
    );
  ''');

  await db.execute('''
    CREATE TABLE ${ActionItemsTable.name} (
      ${ActionItemsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${ActionItemsTable.meetingId} INTEGER NOT NULL,
      ${ActionItemsTable.description} TEXT NOT NULL,
      ${ActionItemsTable.owner} TEXT,
      ${ActionItemsTable.dueDate} TEXT,
      ${ActionItemsTable.isCompleted} INTEGER NOT NULL DEFAULT 0,
      ${ActionItemsTable.createdAt} TEXT NOT NULL,
      FOREIGN KEY (${ActionItemsTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE
    );
  ''');

  await db.execute('''
    CREATE TABLE ${DecisionsTable.name} (
      ${DecisionsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${DecisionsTable.meetingId} INTEGER NOT NULL,
      ${DecisionsTable.description} TEXT NOT NULL,
      ${DecisionsTable.createdAt} TEXT NOT NULL,
      FOREIGN KEY (${DecisionsTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE
    );
  ''');

  await db.execute(
    'CREATE INDEX idx_transcripts_meeting_id '
    'ON ${TranscriptsTable.name} (${TranscriptsTable.meetingId});',
  );
  await db.execute(
    'CREATE INDEX idx_summaries_meeting_id '
    'ON ${SummariesTable.name} (${SummariesTable.meetingId});',
  );
  await db.execute(
    'CREATE INDEX idx_action_items_meeting_id '
    'ON ${ActionItemsTable.name} (${ActionItemsTable.meetingId});',
  );
  await db.execute(
    'CREATE INDEX idx_decisions_meeting_id '
    'ON ${DecisionsTable.name} (${DecisionsTable.meetingId});',
  );
}
