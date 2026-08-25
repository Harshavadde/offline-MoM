import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/note.dart';

abstract class NoteRepository {
  Future<int> insert(Note note);
  Future<void> update(Note note);
  Future<void> delete(int id);
  Future<List<Note>> getForMeeting(int meetingId);
}

class SqfliteNoteRepository implements NoteRepository {
  SqfliteNoteRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Note note) {
    final map = note.toMap()..remove(NotesTable.id);
    return _db.insert(NotesTable.name, map);
  }

  @override
  Future<void> update(Note note) async {
    await _db.update(
      NotesTable.name,
      note.toMap(),
      where: '${NotesTable.id} = ?',
      whereArgs: [note.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      NotesTable.name,
      where: '${NotesTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<Note>> getForMeeting(int meetingId) async {
    final rows = await _db.query(
      NotesTable.name,
      where: '${NotesTable.meetingId} = ?',
      whereArgs: [meetingId],
      orderBy: '${NotesTable.createdAt} DESC',
    );
    return rows.map(Note.fromMap).toList();
  }
}
