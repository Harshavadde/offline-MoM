import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/project_block.dart';

/// Contract for reading/writing the reusable [ProjectBlock] library -
/// app-scoped, not resume-scoped. Depends on nothing but the database; the
/// orphan-block check that gates deletion lives in
/// `DeleteLibraryBlockUseCase`, one layer up, not here.
abstract class ProjectBlockRepository {
  Future<int> insert(ProjectBlock block);
  Future<void> update(ProjectBlock block);

  /// Assumes the caller has already confirmed the block is unreferenced -
  /// performs no reference check itself.
  Future<void> delete(int id);

  Future<ProjectBlock?> getById(int id);

  /// The full library, for the block picker - always listed in full
  /// (mirrors [FolderRepository.getAll]'s own "no pagination needed,
  /// always small" reasoning).
  Future<List<ProjectBlock>> getAll();
}

class SqfliteProjectBlockRepository implements ProjectBlockRepository {
  SqfliteProjectBlockRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(ProjectBlock block) {
    final map = block.toMap()..remove(ProjectBlocksTable.id);
    return _db.insert(ProjectBlocksTable.name, map);
  }

  @override
  Future<void> update(ProjectBlock block) async {
    await _db.update(
      ProjectBlocksTable.name,
      block.toMap(),
      where: '${ProjectBlocksTable.id} = ?',
      whereArgs: [block.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      ProjectBlocksTable.name,
      where: '${ProjectBlocksTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<ProjectBlock?> getById(int id) async {
    final rows = await _db.query(
      ProjectBlocksTable.name,
      where: '${ProjectBlocksTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ProjectBlock.fromMap(rows.first);
  }

  @override
  Future<List<ProjectBlock>> getAll() async {
    final rows = await _db.query(
      ProjectBlocksTable.name,
      orderBy: '${ProjectBlocksTable.createdAt} DESC',
    );
    return rows.map(ProjectBlock.fromMap).toList();
  }
}
