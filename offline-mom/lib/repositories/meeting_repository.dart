import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/meeting.dart';

/// Contract for reading/writing [Meeting] rows.
///
/// Presentation-layer code (ViewModels) depends on this abstract type, never
/// on [SqfliteMeetingRepository] directly, so the storage engine can change
/// without touching a single screen.
abstract class MeetingRepository {
  Future<int> insert(Meeting meeting);
  Future<void> update(Meeting meeting);
  Future<void> delete(int id);
  Future<Meeting?> getById(int id);
  Future<List<Meeting>> getAll();

  /// IDs of meetings whose title contains [query] (case-insensitive).
  Future<List<int>> findIdsByTitle(String query);

  /// IDs of meetings created within `[start, end)`.
  Future<List<int>> findIdsByDateRange(DateTime start, DateTime end);

  /// Fetches multiple meetings by id, most recent first. Used to resolve a
  /// combined set of ids gathered from several search sources into full
  /// [Meeting] rows in one query.
  Future<List<Meeting>> getByIds(Iterable<int> ids);
}

class SqfliteMeetingRepository implements MeetingRepository {
  SqfliteMeetingRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Meeting meeting) {
    final map = meeting.toMap()..remove(MeetingsTable.id);
    return _db.insert(MeetingsTable.name, map);
  }

  @override
  Future<void> update(Meeting meeting) async {
    await _db.update(
      MeetingsTable.name,
      meeting.toMap(),
      where: '${MeetingsTable.id} = ?',
      whereArgs: [meeting.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      MeetingsTable.name,
      where: '${MeetingsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Meeting?> getById(int id) async {
    final rows = await _db.query(
      MeetingsTable.name,
      where: '${MeetingsTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Meeting.fromMap(rows.first);
  }

  @override
  Future<List<Meeting>> getAll() async {
    final rows = await _db.query(
      MeetingsTable.name,
      orderBy: '${MeetingsTable.createdAt} DESC',
    );
    return rows.map(Meeting.fromMap).toList();
  }

  @override
  Future<List<int>> findIdsByTitle(String query) async {
    final rows = await _db.query(
      MeetingsTable.name,
      columns: [MeetingsTable.id],
      where: '${MeetingsTable.title} LIKE ?',
      whereArgs: ['%$query%'],
    );
    return rows.map((r) => r[MeetingsTable.id] as int).toList();
  }

  @override
  Future<List<int>> findIdsByDateRange(DateTime start, DateTime end) async {
    final rows = await _db.query(
      MeetingsTable.name,
      columns: [MeetingsTable.id],
      where: '${MeetingsTable.createdAt} >= ? AND ${MeetingsTable.createdAt} < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
    return rows.map((r) => r[MeetingsTable.id] as int).toList();
  }

  @override
  Future<List<Meeting>> getByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db.query(
      MeetingsTable.name,
      where: '${MeetingsTable.id} IN ($placeholders)',
      whereArgs: ids.toList(),
      orderBy: '${MeetingsTable.createdAt} DESC',
    );
    return rows.map(Meeting.fromMap).toList();
  }
}
