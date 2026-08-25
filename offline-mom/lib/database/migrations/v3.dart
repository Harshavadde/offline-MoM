import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v3, bundling three additions that came out of matching the app's UI to
/// the reference design in one pass:
/// - `recording_marks`: timestamps the user flags mid-recording ("Mark").
/// - `notes`: freeform per-meeting notes, independent of the AI summary.
/// - `meetings.is_favorite`: star a meeting for the History screen's
///   Favorites filter.
Future<void> migrateV2ToV3(Database db) async {
  await db.execute('''
    CREATE TABLE ${RecordingMarksTable.name} (
      ${RecordingMarksTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${RecordingMarksTable.meetingId} INTEGER NOT NULL,
      ${RecordingMarksTable.offsetMs} INTEGER NOT NULL,
      ${RecordingMarksTable.createdAt} TEXT NOT NULL,
      FOREIGN KEY (${RecordingMarksTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE
    );
  ''');
  await db.execute(
    'CREATE INDEX idx_recording_marks_meeting_id '
    'ON ${RecordingMarksTable.name} (${RecordingMarksTable.meetingId});',
  );

  await db.execute('''
    CREATE TABLE ${NotesTable.name} (
      ${NotesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${NotesTable.meetingId} INTEGER NOT NULL,
      ${NotesTable.content} TEXT NOT NULL,
      ${NotesTable.createdAt} TEXT NOT NULL,
      ${NotesTable.updatedAt} TEXT NOT NULL,
      FOREIGN KEY (${NotesTable.meetingId})
        REFERENCES ${MeetingsTable.name} (${MeetingsTable.id})
        ON DELETE CASCADE
    );
  ''');
  await db.execute(
    'CREATE INDEX idx_notes_meeting_id '
    'ON ${NotesTable.name} (${NotesTable.meetingId});',
  );

  await db.execute(
    'ALTER TABLE ${MeetingsTable.name} '
    'ADD COLUMN ${MeetingsTable.isFavorite} INTEGER NOT NULL DEFAULT 0',
  );
}
