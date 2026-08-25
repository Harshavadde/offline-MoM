import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/custom_section_block.dart';

/// Contract for reading/writing the reusable [CustomSectionBlock] library -
/// app-scoped, not resume-scoped. Mirrors [ProjectBlockRepository]'s exact
/// shape and reasoning. The orphan-block check that gates deletion lives in
/// `DeleteLibraryBlockUseCase`, one layer up, not here.
abstract class CustomSectionBlockRepository {
  Future<int> insert(CustomSectionBlock block);
  Future<void> update(CustomSectionBlock block);

  /// Assumes the caller has already confirmed the block is unreferenced -
  /// performs no reference check itself.
  Future<void> delete(int id);

  Future<CustomSectionBlock?> getById(int id);

  /// The full library, for the block picker - always listed in full
  /// (mirrors [ProjectBlockRepository.getAll]'s own "no pagination needed,
  /// always small" reasoning).
  Future<List<CustomSectionBlock>> getAll();
}

class SqfliteCustomSectionBlockRepository implements CustomSectionBlockRepository {
  SqfliteCustomSectionBlockRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(CustomSectionBlock block) {
    final map = block.toMap()..remove(CustomSectionBlocksTable.id);
    return _db.insert(CustomSectionBlocksTable.name, map);
  }

  @override
  Future<void> update(CustomSectionBlock block) async {
    await _db.update(
      CustomSectionBlocksTable.name,
      block.toMap(),
      where: '${CustomSectionBlocksTable.id} = ?',
      whereArgs: [block.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      CustomSectionBlocksTable.name,
      where: '${CustomSectionBlocksTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<CustomSectionBlock?> getById(int id) async {
    final rows = await _db.query(
      CustomSectionBlocksTable.name,
      where: '${CustomSectionBlocksTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CustomSectionBlock.fromMap(rows.first);
  }

  @override
  Future<List<CustomSectionBlock>> getAll() async {
    final rows = await _db.query(
      CustomSectionBlocksTable.name,
      orderBy: '${CustomSectionBlocksTable.createdAt} DESC',
    );
    return rows.map(CustomSectionBlock.fromMap).toList();
  }
}
