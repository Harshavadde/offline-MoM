import '../../../models/suggested_edit.dart';
import '../../../repositories/suggested_edit_repository.dart';
import 'accept_suggested_edit_use_case.dart'
    show SuggestedEditNotFoundException, SuggestedEditNotPendingException;

/// Rejects one pending [SuggestedEdit] (docs/v3/01-prd.md §25 Milestone 3,
/// FR3-09, §12). Never touches resume content in any way - a rejection is
/// purely a status change on the suggestion row itself, which is what
/// guarantees FR3-09's "rejecting a suggestion leaves the original content
/// byte-identical" without needing a dedicated test to prove a negative:
/// there is no code path here that could write to a resume block even by
/// accident.
///
/// Rejected suggestions are retained, not deleted (docs/v3/01-prd.md §12 -
/// audit/undo history), by simply moving `status` from `pending` to
/// `rejected` via [SuggestedEditRepository.resolve].
///
/// Idempotent for an already-rejected suggestion: calling this again
/// returns the same already-rejected row unchanged rather than throwing -
/// "repeated rejection behaves safely," matching a user tapping Reject
/// twice in a row (e.g. a slow double-tap) never producing an error.
/// Rejecting an already-*accepted* suggestion is different: that would
/// mean un-applying already-live content through a status flip alone,
/// which this use case does not support, so it throws
/// [SuggestedEditNotPendingException] instead.
class RejectSuggestedEditUseCase {
  RejectSuggestedEditUseCase({required SuggestedEditRepository suggestedEditRepository})
      : _suggestedEditRepository = suggestedEditRepository;

  final SuggestedEditRepository _suggestedEditRepository;

  Future<SuggestedEdit> call(int suggestedEditId) async {
    final edit = await _suggestedEditRepository.getById(suggestedEditId);
    if (edit == null) throw SuggestedEditNotFoundException(suggestedEditId);

    if (edit.status == SuggestedEditStatus.rejected) {
      return edit;
    }
    if (edit.status != SuggestedEditStatus.pending) {
      throw SuggestedEditNotPendingException(edit.status);
    }

    final resolvedAt = DateTime.now();
    await _suggestedEditRepository.resolve(suggestedEditId, SuggestedEditStatus.rejected, resolvedAt);

    return edit.copyWith(status: SuggestedEditStatus.rejected, resolvedAt: resolvedAt);
  }
}
