import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/suggested_edit.dart';

/// Contract for reading/writing [SuggestedEdit] rows - the persistence half
/// of the "AI proposes, user decides" pipeline (docs/v3/01-prd.md §22.3).
/// Generation (Milestone 3) and accept/reject use cases are the only
/// intended callers; nothing in Milestone 0 generates a real suggestion,
/// this repository exists purely as the schema/CRUD foundation those later
/// use cases build on.
abstract class SuggestedEditRepository {
  /// Persist a newly-generated suggestion - always `status: pending`.
  Future<int> insert(SuggestedEdit edit);

  /// Moves a suggestion out of `pending` into [status], stamping
  /// [resolvedAt]. The suggestion's [SuggestedEdit.suggestedValue] is never
  /// rewritten here - an "edited" resolution records the user's final text
  /// as a *separate* concern (the caller's own accept/edit use case, not
  /// this repository), matching `ResumeVersionRepository.renameLabel`'s
  /// "one permitted metadata edit target" precedent for keeping a
  /// repository's write surface narrow and explicit.
  Future<void> resolve(int id, SuggestedEditStatus status, DateTime resolvedAt);

  /// Remove one suggestion outright - used only when the resume/target
  /// block it belongs to is itself deleted, never as a substitute for
  /// [resolve].
  Future<void> delete(int id);

  Future<SuggestedEdit?> getById(int id);

  /// Every suggestion for one Resume, most recent first.
  Future<List<SuggestedEdit>> getForResume(int resumeId);

  /// Only the still-actionable suggestions for one Resume, most recent
  /// first - what the Suggestion Review screen (Milestone 3) actually
  /// lists.
  Future<List<SuggestedEdit>> getPendingForResume(int resumeId);
}

class SqfliteSuggestedEditRepository implements SuggestedEditRepository {
  SqfliteSuggestedEditRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(SuggestedEdit edit) {
    final map = edit.toMap()..remove(SuggestedEditsTable.id);
    return _db.insert(SuggestedEditsTable.name, map);
  }

  @override
  Future<void> resolve(int id, SuggestedEditStatus status, DateTime resolvedAt) async {
    await _db.update(
      SuggestedEditsTable.name,
      {
        SuggestedEditsTable.status: status.name,
        SuggestedEditsTable.resolvedAt: resolvedAt.toIso8601String(),
      },
      where: '${SuggestedEditsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      SuggestedEditsTable.name,
      where: '${SuggestedEditsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<SuggestedEdit?> getById(int id) async {
    final rows = await _db.query(
      SuggestedEditsTable.name,
      where: '${SuggestedEditsTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SuggestedEdit.fromMap(rows.first);
  }

  @override
  Future<List<SuggestedEdit>> getForResume(int resumeId) async {
    final rows = await _db.query(
      SuggestedEditsTable.name,
      where: '${SuggestedEditsTable.resumeId} = ?',
      whereArgs: [resumeId],
      orderBy: '${SuggestedEditsTable.createdAt} DESC',
    );
    return rows.map(SuggestedEdit.fromMap).toList();
  }

  @override
  Future<List<SuggestedEdit>> getPendingForResume(int resumeId) async {
    final rows = await _db.query(
      SuggestedEditsTable.name,
      where: '${SuggestedEditsTable.resumeId} = ? AND ${SuggestedEditsTable.status} = ?',
      whereArgs: [resumeId, SuggestedEditStatus.pending.name],
      orderBy: '${SuggestedEditsTable.createdAt} DESC',
    );
    return rows.map(SuggestedEdit.fromMap).toList();
  }
}
