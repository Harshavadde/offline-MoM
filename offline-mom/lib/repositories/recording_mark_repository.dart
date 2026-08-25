import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/recording_mark.dart';

abstract class RecordingMarkRepository {
  Future<int> insert(RecordingMark mark);
  Future<List<RecordingMark>> getForMeeting(int meetingId);
}

class SqfliteRecordingMarkRepository implements RecordingMarkRepository {
  SqfliteRecordingMarkRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(RecordingMark mark) {
    final map = mark.toMap()..remove(RecordingMarksTable.id);
    return _db.insert(RecordingMarksTable.name, map);
  }

  @override
  Future<List<RecordingMark>> getForMeeting(int meetingId) async {
    final rows = await _db.query(
      RecordingMarksTable.name,
      where: '${RecordingMarksTable.meetingId} = ?',
      whereArgs: [meetingId],
      orderBy: '${RecordingMarksTable.offsetMs} ASC',
    );
    return rows.map(RecordingMark.fromMap).toList();
  }
}
