import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/decision.dart';

/// The `decisions` table this repository backs is permanent
/// schema-compatibility dead weight, not a functional gap: the on-device
/// LLM stopped extracting decisions well before V2 (see
/// `LlamaDartLlmEngine`'s doc comment), and there is no manual "add a
/// decision" UI path either - `insertAll` is only ever called with an
/// empty list in practice, and no code path calls a single-item `insert`
/// at all (unlike [ActionItemRepository], which has both a batch and a
/// manual single-item path for exactly that reason).
///
/// This was reconsidered, not just carried forward by default, as part of
/// Phase 0 (ADR-012, docs/v2/implementation/03-decisions.md): remove the
/// table entirely, or resurrect AI-extracted decisions now that would cost
/// real churn (Export screen toggle, this repository, `SearchMeetingsUseCase`'s
/// decision lookup) for zero functional gain in the first case, or requires
/// a materially more capable default model than V2 Phase 0/1 commits to in
/// the second. Decision: leave it exactly as-is. Revisit only if/when a
/// future, genuinely larger default LLM tier ships (V2 Phase 3, optional -
/// see docs/v2/07-feature-roadmap.md).
abstract class DecisionRepository {
  Future<void> insertAll(List<Decision> decisions);
  Future<List<Decision>> getForMeeting(int meetingId);

  /// IDs of meetings with a decision whose description contains [query].
  Future<List<int>> findMeetingIdsByDescription(String query);
}

class SqfliteDecisionRepository implements DecisionRepository {
  SqfliteDecisionRepository(this._db);

  final Database _db;

  @override
  Future<void> insertAll(List<Decision> decisions) async {
    final batch = _db.batch();
    for (final decision in decisions) {
      final map = decision.toMap()..remove(DecisionsTable.id);
      batch.insert(DecisionsTable.name, map);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<Decision>> getForMeeting(int meetingId) async {
    final rows = await _db.query(
      DecisionsTable.name,
      where: '${DecisionsTable.meetingId} = ?',
      whereArgs: [meetingId],
      orderBy: '${DecisionsTable.createdAt} ASC',
    );
    return rows.map(Decision.fromMap).toList();
  }

  @override
  Future<List<int>> findMeetingIdsByDescription(String query) async {
    final rows = await _db.query(
      DecisionsTable.name,
      columns: [DecisionsTable.meetingId],
      where: '${DecisionsTable.description} LIKE ?',
      whereArgs: ['%$query%'],
    );
    return rows.map((r) => r[DecisionsTable.meetingId] as int).toList();
  }
}
