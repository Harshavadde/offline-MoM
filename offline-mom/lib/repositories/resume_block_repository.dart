import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/resume_block_ref.dart';
import '../models/resume_block_type.dart';

/// Contract for reading/writing a [Resume]'s *live, editable* composition -
/// which library blocks it currently includes, in what order, with what
/// per-resume overrides. Generalizes [DocumentRepository]'s thin, focused
/// relation-method precedent to a full polymorphic join - the same pattern
/// [KnowledgeChunkRepository] already uses for `content_type` + `source_id`.
abstract class ResumeBlockRepository {
  /// Adds a library block to a resume's composition, appended at the end.
  Future<int> attach(int resumeId, ResumeBlockType blockType, int blockId);

  /// Removes a block from the composition - does not delete the library
  /// block itself.
  Future<void> detach(int resumeId, ResumeBlockType blockType, int blockId);

  /// Persists a new `sort_order` for a resume's blocks, in a single
  /// transaction - mirrors `ScannerController.reorderPage`'s exact intent,
  /// with atomicity added so an interrupted write can never leave a
  /// section's order half-written.
  Future<void> reorder(int resumeId, List<ResumeBlockRef> orderedRefs);

  /// Stores/clears a per-resume customization (e.g. a trimmed bullet
  /// subset) without touching the shared library block.
  Future<void> setOverride(
    int resumeId,
    ResumeBlockType blockType,
    int blockId,
    String? overrideJson,
  );

  /// The resume's full, ordered composition - what the Editor renders and
  /// what `ResumeCompilerService` resolves.
  Future<List<ResumeBlockRef>> getForResume(int resumeId);

  /// Every distinct resume id that currently references one library block
  /// - the sole read `DeleteLibraryBlockUseCase` needs to enforce the
  /// orphan-block policy. Returns an empty list when the block is
  /// unreferenced.
  Future<List<int>> getReferencingResumeIds(
    ResumeBlockType blockType,
    int blockId,
  );
}

class SqfliteResumeBlockRepository implements ResumeBlockRepository {
  SqfliteResumeBlockRepository(this._db);

  final Database _db;

  @override
  Future<int> attach(int resumeId, ResumeBlockType blockType, int blockId) async {
    // "Appended at the end" - the next sort_order after whatever's
    // currently highest for this resume, not a caller-supplied value
    // (attach's signature deliberately takes only ids, not a full
    // ResumeBlockRef, so this repository is the only place that can
    // compute it).
    final maxRows = await _db.rawQuery(
      'SELECT MAX(${ResumeBlocksTable.sortOrder}) as maxOrder '
      'FROM ${ResumeBlocksTable.name} WHERE ${ResumeBlocksTable.resumeId} = ?',
      [resumeId],
    );
    final currentMax = maxRows.first['maxOrder'] as int?;
    final nextSortOrder = (currentMax ?? -1) + 1;

    final ref = ResumeBlockRef(
      id: null,
      resumeId: resumeId,
      blockType: blockType,
      blockId: blockId,
      sortOrder: nextSortOrder,
      createdAt: DateTime.now(),
    );
    final map = ref.toMap()..remove(ResumeBlocksTable.id);
    return _db.insert(ResumeBlocksTable.name, map);
  }

  @override
  Future<void> detach(int resumeId, ResumeBlockType blockType, int blockId) async {
    await _db.delete(
      ResumeBlocksTable.name,
      where: '${ResumeBlocksTable.resumeId} = ? AND ${ResumeBlocksTable.blockType} = ? '
          'AND ${ResumeBlocksTable.blockId} = ?',
      whereArgs: [resumeId, blockType.name, blockId],
    );
  }

  @override
  Future<void> reorder(int resumeId, List<ResumeBlockRef> orderedRefs) async {
    // Single transaction so an interruption partway through this
    // multi-row write can never leave the section half-reordered -
    // mirrors SqfliteInstalledModelRepository.setActive's transaction
    // shape, the only other multi-statement repository write in this
    // codebase.
    await _db.transaction((txn) async {
      for (var i = 0; i < orderedRefs.length; i++) {
        await txn.update(
          ResumeBlocksTable.name,
          {ResumeBlocksTable.sortOrder: i},
          where: '${ResumeBlocksTable.id} = ?',
          whereArgs: [orderedRefs[i].id],
        );
      }
    });
  }

  @override
  Future<void> setOverride(
    int resumeId,
    ResumeBlockType blockType,
    int blockId,
    String? overrideJson,
  ) async {
    await _db.update(
      ResumeBlocksTable.name,
      {ResumeBlocksTable.overrideJson: overrideJson},
      where: '${ResumeBlocksTable.resumeId} = ? AND ${ResumeBlocksTable.blockType} = ? '
          'AND ${ResumeBlocksTable.blockId} = ?',
      whereArgs: [resumeId, blockType.name, blockId],
    );
  }

  @override
  Future<List<ResumeBlockRef>> getForResume(int resumeId) async {
    final rows = await _db.query(
      ResumeBlocksTable.name,
      where: '${ResumeBlocksTable.resumeId} = ?',
      whereArgs: [resumeId],
      orderBy: '${ResumeBlocksTable.sortOrder} ASC',
    );
    return rows.map(ResumeBlockRef.fromMap).toList();
  }

  @override
  Future<List<int>> getReferencingResumeIds(ResumeBlockType blockType, int blockId) async {
    final rows = await _db.query(
      ResumeBlocksTable.name,
      distinct: true,
      columns: [ResumeBlocksTable.resumeId],
      where: '${ResumeBlocksTable.blockType} = ? AND ${ResumeBlocksTable.blockId} = ?',
      whereArgs: [blockType.name, blockId],
    );
    return rows.map((r) => r[ResumeBlocksTable.resumeId] as int).toList();
  }
}
