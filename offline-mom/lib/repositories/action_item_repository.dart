import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/action_item.dart';

abstract class ActionItemRepository {
  Future<void> insertAll(List<ActionItem> items);

  /// Adds a single manually-entered action item (the AI-extracted path uses
  /// [insertAll] instead, since it always has a full batch at once).
  Future<int> insert(ActionItem item);
  Future<List<ActionItem>> getForMeeting(int meetingId);
  Future<void> setCompleted(int id, bool isCompleted);
  Future<void> delete(int id);

  /// IDs of meetings with an action item whose description contains [query].
  Future<List<int>> findMeetingIdsByDescription(String query);
}

class SqfliteActionItemRepository implements ActionItemRepository {
  SqfliteActionItemRepository(this._db);

  final Database _db;

  @override
  Future<void> insertAll(List<ActionItem> items) async {
    final batch = _db.batch();
    for (final item in items) {
      final map = item.toMap()..remove(ActionItemsTable.id);
      batch.insert(ActionItemsTable.name, map);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<int> insert(ActionItem item) {
    final map = item.toMap()..remove(ActionItemsTable.id);
    return _db.insert(ActionItemsTable.name, map);
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      ActionItemsTable.name,
      where: '${ActionItemsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<ActionItem>> getForMeeting(int meetingId) async {
    final rows = await _db.query(
      ActionItemsTable.name,
      where: '${ActionItemsTable.meetingId} = ?',
      whereArgs: [meetingId],
      orderBy: '${ActionItemsTable.createdAt} ASC',
    );
    return rows.map(ActionItem.fromMap).toList();
  }

  @override
  Future<void> setCompleted(int id, bool isCompleted) async {
    await _db.update(
      ActionItemsTable.name,
      {ActionItemsTable.isCompleted: isCompleted ? 1 : 0},
      where: '${ActionItemsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<int>> findMeetingIdsByDescription(String query) async {
    final rows = await _db.query(
      ActionItemsTable.name,
      columns: [ActionItemsTable.meetingId],
      where: '${ActionItemsTable.description} LIKE ?',
      whereArgs: ['%$query%'],
    );
    return rows.map((r) => r[ActionItemsTable.meetingId] as int).toList();
  }
}
