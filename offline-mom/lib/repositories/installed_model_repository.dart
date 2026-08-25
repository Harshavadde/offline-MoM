import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/installed_model.dart';
import '../services/ai/model_lifecycle_manager.dart' show ModelKind;

/// Contract for reading/writing [InstalledModel] rows (AI Model Manager,
/// V2 Phase 6A) - mirrors [ToolkitFileRepository]'s shape.
abstract class InstalledModelRepository {
  Future<int> insert(InstalledModel model);
  Future<void> delete(int id);
  Future<InstalledModel?> getById(int id);
  Future<InstalledModel?> getByModelId(String modelId);
  Future<List<InstalledModel>> getAll();
  Future<List<InstalledModel>> getByKind(ModelKind kind);

  /// The currently-active installed model for [kind], or `null` if none is
  /// installed/active yet.
  Future<InstalledModel?> getActiveForKind(ModelKind kind);

  /// Atomically (within one repository call) deactivates every other
  /// installed row of [kind] and activates [modelId]'s row - the
  /// enforcement point for "at most one active model per kind"
  /// ([InstalledModelsTable.isActive]'s doc comment), since SQLite can't
  /// express that invariant as a CHECK constraint on a non-unique column.
  Future<void> setActive(ModelKind kind, String modelId);
}

class SqfliteInstalledModelRepository implements InstalledModelRepository {
  SqfliteInstalledModelRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(InstalledModel model) {
    final map = model.toMap()..remove(InstalledModelsTable.id);
    return _db.insert(InstalledModelsTable.name, map);
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      InstalledModelsTable.name,
      where: '${InstalledModelsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<InstalledModel?> getById(int id) async {
    final rows = await _db.query(
      InstalledModelsTable.name,
      where: '${InstalledModelsTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InstalledModel.fromMap(rows.first);
  }

  @override
  Future<InstalledModel?> getByModelId(String modelId) async {
    final rows = await _db.query(
      InstalledModelsTable.name,
      where: '${InstalledModelsTable.modelId} = ?',
      whereArgs: [modelId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InstalledModel.fromMap(rows.first);
  }

  @override
  Future<List<InstalledModel>> getAll() async {
    final rows = await _db.query(
      InstalledModelsTable.name,
      orderBy: '${InstalledModelsTable.downloadedAt} DESC',
    );
    return rows.map(InstalledModel.fromMap).toList();
  }

  @override
  Future<List<InstalledModel>> getByKind(ModelKind kind) async {
    final rows = await _db.query(
      InstalledModelsTable.name,
      where: '${InstalledModelsTable.kind} = ?',
      whereArgs: [kind.name],
      orderBy: '${InstalledModelsTable.downloadedAt} DESC',
    );
    return rows.map(InstalledModel.fromMap).toList();
  }

  @override
  Future<InstalledModel?> getActiveForKind(ModelKind kind) async {
    final rows = await _db.query(
      InstalledModelsTable.name,
      where: '${InstalledModelsTable.kind} = ? AND ${InstalledModelsTable.isActive} = 1',
      whereArgs: [kind.name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InstalledModel.fromMap(rows.first);
  }

  @override
  Future<void> setActive(ModelKind kind, String modelId) async {
    await _db.transaction((txn) async {
      await txn.update(
        InstalledModelsTable.name,
        {InstalledModelsTable.isActive: 0},
        where: '${InstalledModelsTable.kind} = ?',
        whereArgs: [kind.name],
      );
      await txn.update(
        InstalledModelsTable.name,
        {InstalledModelsTable.isActive: 1},
        where: '${InstalledModelsTable.kind} = ? AND ${InstalledModelsTable.modelId} = ?',
        whereArgs: [kind.name, modelId],
      );
    });
  }
}
