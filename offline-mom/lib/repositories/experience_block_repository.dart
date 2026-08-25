import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/experience_block.dart';

/// Contract for reading/writing the reusable [ExperienceBlock] library -
/// app-scoped, not resume-scoped. Depends on nothing but the database; the
/// orphan-block check that gates deletion lives in
/// `DeleteLibraryBlockUseCase`, one layer up, not here.
abstract class ExperienceBlockRepository {
  Future<int> insert(ExperienceBlock block);
  Future<void> update(ExperienceBlock block);

  /// Assumes the caller has already confirmed the block is unreferenced -
  /// performs no reference check itself.
  Future<void> delete(int id);

  Future<ExperienceBlock?> getById(int id);

  /// The full library, for the block picker - always listed in full
  /// (mirrors [FolderRepository.getAll]'s own "no pagination needed,
  /// always small" reasoning).
  Future<List<ExperienceBlock>> getAll();
}

class SqfliteExperienceBlockRepository implements ExperienceBlockRepository {
  SqfliteExperienceBlockRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(ExperienceBlock block) {
    final map = block.toMap()..remove(ExperienceBlocksTable.id);
    return _db.insert(ExperienceBlocksTable.name, map);
  }

  @override
  Future<void> update(ExperienceBlock block) async {
    await _db.update(
      ExperienceBlocksTable.name,
      block.toMap(),
      where: '${ExperienceBlocksTable.id} = ?',
      whereArgs: [block.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      ExperienceBlocksTable.name,
      where: '${ExperienceBlocksTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<ExperienceBlock?> getById(int id) async {
    final rows = await _db.query(
      ExperienceBlocksTable.name,
      where: '${ExperienceBlocksTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ExperienceBlock.fromMap(rows.first);
  }

  @override
  Future<List<ExperienceBlock>> getAll() async {
    final rows = await _db.query(
      ExperienceBlocksTable.name,
      orderBy: '${ExperienceBlocksTable.createdAt} DESC',
    );
    return rows.map(ExperienceBlock.fromMap).toList();
  }
}
