import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/folder.dart';
import 'folder_repository.dart';

/// Folders for organizing Student Toolkit outputs (P0-9, File-Manager
/// Parity) - implements the same [FolderRepository] contract
/// `SqfliteFolderRepository` (Documents) already does, reusing the
/// identical [Folder] model, but backed by its own `toolkit_folders` table
/// so deleting/renaming a toolkit folder can never affect Documents' own
/// folders (see `ToolkitFoldersTable`'s own doc comment,
/// database/tables.dart).
class SqfliteToolkitFolderRepository implements FolderRepository {
  SqfliteToolkitFolderRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Folder folder) {
    final map = folder.toMap()..remove(ToolkitFoldersTable.id);
    return _db.insert(ToolkitFoldersTable.name, map);
  }

  @override
  Future<void> update(Folder folder) async {
    await _db.update(
      ToolkitFoldersTable.name,
      folder.toMap(),
      where: '${ToolkitFoldersTable.id} = ?',
      whereArgs: [folder.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.update(
      ToolkitFilesTable.name,
      {ToolkitFilesTable.folderId: null},
      where: '${ToolkitFilesTable.folderId} = ?',
      whereArgs: [id],
    );
    await _db.delete(
      ToolkitFoldersTable.name,
      where: '${ToolkitFoldersTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Folder?> getById(int id) async {
    final rows = await _db.query(
      ToolkitFoldersTable.name,
      where: '${ToolkitFoldersTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Folder.fromMap(rows.first);
  }

  @override
  Future<List<Folder>> getAll() async {
    final rows = await _db.query(
      ToolkitFoldersTable.name,
      orderBy: '${ToolkitFoldersTable.title} COLLATE NOCASE ASC',
    );
    return rows.map(Folder.fromMap).toList();
  }
}
