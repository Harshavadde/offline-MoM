import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/folder.dart';

/// Contract for reading/writing [Folder] rows (V2.2 Production Hardening,
/// Priority 2) - mirrors [NoteRepository]'s shape
/// (lib/repositories/note_repository.dart).
abstract class FolderRepository {
  Future<int> insert(Folder folder);
  Future<void> update(Folder folder);

  /// Deletes the folder - every document currently in it is moved back to
  /// "All Documents" ([DocumentsTable.folderId] set to null) first, never
  /// deleted. A folder disappearing must never take its documents with
  /// it.
  Future<void> delete(int id);
  Future<Folder?> getById(int id);

  /// Every folder, alphabetically - there is no "recent first" concept
  /// for folders the way there is for meetings/documents (a folder isn't
  /// itself a piece of content with a creation-recency the user cares
  /// about browsing by).
  Future<List<Folder>> getAll();
}

class SqfliteFolderRepository implements FolderRepository {
  SqfliteFolderRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Folder folder) {
    final map = folder.toMap()..remove(FoldersTable.id);
    return _db.insert(FoldersTable.name, map);
  }

  @override
  Future<void> update(Folder folder) async {
    await _db.update(
      FoldersTable.name,
      folder.toMap(),
      where: '${FoldersTable.id} = ?',
      whereArgs: [folder.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.update(
      DocumentsTable.name,
      {DocumentsTable.folderId: null},
      where: '${DocumentsTable.folderId} = ?',
      whereArgs: [id],
    );
    await _db.delete(
      FoldersTable.name,
      where: '${FoldersTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Folder?> getById(int id) async {
    final rows = await _db.query(
      FoldersTable.name,
      where: '${FoldersTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Folder.fromMap(rows.first);
  }

  @override
  Future<List<Folder>> getAll() async {
    final rows = await _db.query(
      FoldersTable.name,
      orderBy: '${FoldersTable.title} COLLATE NOCASE ASC',
    );
    return rows.map(Folder.fromMap).toList();
  }
}
