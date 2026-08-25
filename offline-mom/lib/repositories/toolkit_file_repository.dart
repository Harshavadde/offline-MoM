import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/toolkit_file.dart';

/// Contract for reading/writing [ToolkitFile] rows (Student Toolkit Recent
/// Files, V2 Phase 5A) - mirrors [NoteRepository]'s shape exactly
/// (lib/repositories/note_repository.dart).
abstract class ToolkitFileRepository {
  Future<int> insert(ToolkitFile file);
  Future<void> update(ToolkitFile file);
  Future<void> delete(int id);
  Future<ToolkitFile?> getById(int id);

  /// Every toolkit output, most recently created first - drives the Recent
  /// Files list's Today/This Week/Older grouping (a presentation-layer
  /// concern, done by the screen, not this query). Includes files that are
  /// inside a folder - "All Files" and "Recent" are folder-agnostic views.
  Future<List<ToolkitFile>> getAll();

  /// Files in [folderId], most recently created first - `null` means "All
  /// Files" (every file with no folder), mirroring
  /// `DocumentRepository.getInFolder`'s identical shape (P0-9,
  /// File-Manager Parity).
  Future<List<ToolkitFile>> getInFolder(int? folderId);

  /// Moves [id] into [folderId] (or back to "All Files" when `null`).
  Future<void> moveToFolder(int id, int? folderId);
}

class SqfliteToolkitFileRepository implements ToolkitFileRepository {
  SqfliteToolkitFileRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(ToolkitFile file) {
    final map = file.toMap()..remove(ToolkitFilesTable.id);
    return _db.insert(ToolkitFilesTable.name, map);
  }

  @override
  Future<void> update(ToolkitFile file) async {
    await _db.update(
      ToolkitFilesTable.name,
      file.toMap(),
      where: '${ToolkitFilesTable.id} = ?',
      whereArgs: [file.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      ToolkitFilesTable.name,
      where: '${ToolkitFilesTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<ToolkitFile?> getById(int id) async {
    final rows = await _db.query(
      ToolkitFilesTable.name,
      where: '${ToolkitFilesTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ToolkitFile.fromMap(rows.first);
  }

  @override
  Future<List<ToolkitFile>> getAll() async {
    final rows = await _db.query(
      ToolkitFilesTable.name,
      orderBy: '${ToolkitFilesTable.createdAt} DESC',
    );
    return rows.map(ToolkitFile.fromMap).toList();
  }

  @override
  Future<List<ToolkitFile>> getInFolder(int? folderId) async {
    final rows = await _db.query(
      ToolkitFilesTable.name,
      where: folderId == null
          ? '${ToolkitFilesTable.folderId} IS NULL'
          : '${ToolkitFilesTable.folderId} = ?',
      whereArgs: folderId == null ? null : [folderId],
      orderBy: '${ToolkitFilesTable.createdAt} DESC',
    );
    return rows.map(ToolkitFile.fromMap).toList();
  }

  @override
  Future<void> moveToFolder(int id, int? folderId) async {
    await _db.update(
      ToolkitFilesTable.name,
      {ToolkitFilesTable.folderId: folderId},
      where: '${ToolkitFilesTable.id} = ?',
      whereArgs: [id],
    );
  }
}
