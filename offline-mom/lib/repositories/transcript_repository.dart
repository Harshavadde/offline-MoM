import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/transcript.dart';

abstract class TranscriptRepository {
  Future<int> insert(Transcript transcript);
  Future<Transcript?> getForMeeting(int meetingId);

  /// IDs of meetings whose transcript text contains [query].
  Future<List<int>> findMeetingIdsByText(String query);
}

class SqfliteTranscriptRepository implements TranscriptRepository {
  SqfliteTranscriptRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Transcript transcript) {
    final map = transcript.toMap()..remove(TranscriptsTable.id);
    return _db.insert(TranscriptsTable.name, map);
  }

  @override
  Future<Transcript?> getForMeeting(int meetingId) async {
    final rows = await _db.query(
      TranscriptsTable.name,
      where: '${TranscriptsTable.meetingId} = ?',
      whereArgs: [meetingId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Transcript.fromMap(rows.first);
  }

  @override
  Future<List<int>> findMeetingIdsByText(String query) async {
    final rows = await _db.query(
      TranscriptsTable.name,
      columns: [TranscriptsTable.meetingId],
      where: '${TranscriptsTable.fullText} LIKE ?',
      whereArgs: ['%$query%'],
    );
    return rows.map((r) => r[TranscriptsTable.meetingId] as int).toList();
  }
}
