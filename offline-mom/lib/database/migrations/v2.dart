import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v2: adds `meetings.error_message` so a pipeline failure (transcription or
/// AI summary) records *why* it failed instead of just flipping the meeting
/// to `error` with no diagnostic trail - the previous behavior made a
/// real, reported failure impossible to debug after the fact.
Future<void> migrateV1ToV2(Database db) async {
  await db.execute(
    'ALTER TABLE ${MeetingsTable.name} ADD COLUMN ${MeetingsTable.errorMessage} TEXT',
  );
}
