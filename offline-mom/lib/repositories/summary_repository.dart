import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/summary.dart';

abstract class SummaryRepository {
  Future<int> insert(Summary summary);
  Future<Summary?> getForMeeting(int meetingId);

  /// The document-owned counterpart to [getForMeeting] - added in V2 Phase
  /// 1A alongside [Summary.documentId] (ADR-005,
  /// docs/v2/implementation/03-decisions.md).
  Future<Summary?> getForDocument(int documentId);
}

class SqfliteSummaryRepository implements SummaryRepository {
  SqfliteSummaryRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Summary summary) {
    final map = summary.toMap()..remove(SummariesTable.id);
    return _db.insert(SummariesTable.name, map);
  }

  @override
  Future<Summary?> getForMeeting(int meetingId) async {
    final rows = await _db.query(
      SummariesTable.name,
      where: '${SummariesTable.meetingId} = ?',
      whereArgs: [meetingId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Summary.fromMap(rows.first);
  }

  @override
  Future<Summary?> getForDocument(int documentId) async {
    final rows = await _db.query(
      SummariesTable.name,
      where: '${SummariesTable.documentId} = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Summary.fromMap(rows.first);
  }
}
