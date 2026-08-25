import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/education_block.dart';

/// Contract for reading/writing the reusable [EducationBlock] library -
/// app-scoped, not resume-scoped. Depends on nothing but the database; the
/// orphan-block check that gates deletion lives in
/// `DeleteLibraryBlockUseCase`, one layer up, not here.
abstract class EducationBlockRepository {
  Future<int> insert(EducationBlock block);
  Future<void> update(EducationBlock block);

  /// Assumes the caller has already confirmed the block is unreferenced -
  /// performs no reference check itself.
  Future<void> delete(int id);

  Future<EducationBlock?> getById(int id);

  /// The full library, for the block picker - always listed in full
  /// (mirrors [FolderRepository.getAll]'s own "no pagination needed,
  /// always small" reasoning).
  Future<List<EducationBlock>> getAll();
}

class SqfliteEducationBlockRepository implements EducationBlockRepository {
  SqfliteEducationBlockRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(EducationBlock block) {
    final map = block.toMap()..remove(EducationBlocksTable.id);
    return _db.insert(EducationBlocksTable.name, map);
  }

  @override
  Future<void> update(EducationBlock block) async {
    await _db.update(
      EducationBlocksTable.name,
      block.toMap(),
      where: '${EducationBlocksTable.id} = ?',
      whereArgs: [block.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      EducationBlocksTable.name,
      where: '${EducationBlocksTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<EducationBlock?> getById(int id) async {
    final rows = await _db.query(
      EducationBlocksTable.name,
      where: '${EducationBlocksTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EducationBlock.fromMap(rows.first);
  }

  @override
  Future<List<EducationBlock>> getAll() async {
    final rows = await _db.query(
      EducationBlocksTable.name,
      orderBy: '${EducationBlocksTable.createdAt} DESC',
    );
    return rows.map(EducationBlock.fromMap).toList();
  }
}
