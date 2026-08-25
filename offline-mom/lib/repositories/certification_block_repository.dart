import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/certification_block.dart';

/// Contract for reading/writing the reusable [CertificationBlock] library -
/// app-scoped, not resume-scoped. Depends on nothing but the database; the
/// orphan-block check that gates deletion lives in
/// `DeleteLibraryBlockUseCase`, one layer up, not here.
abstract class CertificationBlockRepository {
  Future<int> insert(CertificationBlock block);
  Future<void> update(CertificationBlock block);

  /// Assumes the caller has already confirmed the block is unreferenced -
  /// performs no reference check itself.
  Future<void> delete(int id);

  Future<CertificationBlock?> getById(int id);

  /// The full library, for the block picker - always listed in full
  /// (mirrors [FolderRepository.getAll]'s own "no pagination needed,
  /// always small" reasoning).
  Future<List<CertificationBlock>> getAll();
}

class SqfliteCertificationBlockRepository implements CertificationBlockRepository {
  SqfliteCertificationBlockRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(CertificationBlock block) {
    final map = block.toMap()..remove(CertificationBlocksTable.id);
    return _db.insert(CertificationBlocksTable.name, map);
  }

  @override
  Future<void> update(CertificationBlock block) async {
    await _db.update(
      CertificationBlocksTable.name,
      block.toMap(),
      where: '${CertificationBlocksTable.id} = ?',
      whereArgs: [block.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      CertificationBlocksTable.name,
      where: '${CertificationBlocksTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<CertificationBlock?> getById(int id) async {
    final rows = await _db.query(
      CertificationBlocksTable.name,
      where: '${CertificationBlocksTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CertificationBlock.fromMap(rows.first);
  }

  @override
  Future<List<CertificationBlock>> getAll() async {
    final rows = await _db.query(
      CertificationBlocksTable.name,
      orderBy: '${CertificationBlocksTable.createdAt} DESC',
    );
    return rows.map(CertificationBlock.fromMap).toList();
  }
}
