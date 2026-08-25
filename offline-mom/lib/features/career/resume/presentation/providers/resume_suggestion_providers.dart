import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/job_description.dart';
import '../../../../../models/suggested_edit.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/resume/suggestion_fabrication_guard.dart';
import 'resume_editor_providers.dart';

/// One pending suggestion paired with its lazily-computed fabrication
/// flag (docs/v3/01-prd.md AC3-03/D-08). Computed here, at read time, from
/// [SuggestedEdit.originalValue]/[SuggestedEdit.suggestedValue] - never
/// persisted, since the guard is a pure function of already-stored data
/// (see `GenerateResumeSuggestionsUseCase`'s own doc comment for why
/// running it once at generation time and discarding the result would be
/// redundant).
class SuggestionReviewItem {
  const SuggestionReviewItem({required this.edit, required this.fabricationCheck});

  final SuggestedEdit edit;
  final FabricationCheckResult fabricationCheck;
}

/// How many suggestions are still awaiting review for one resume - what
/// the Editor's entry point into the review screen badges itself with.
final pendingSuggestionCountProvider = FutureProvider.autoDispose.family<int, int>((ref, resumeId) async {
  final pending = await ref.watch(suggestedEditRepositoryProvider).getPendingForResume(resumeId);
  return pending.length;
});

/// The Suggestion Review screen's actual list - every still-pending
/// suggestion for one resume, each paired with its fabrication flag.
final suggestionReviewListProvider =
    FutureProvider.autoDispose.family<List<SuggestionReviewItem>, int>((ref, resumeId) async {
  final pending = await ref.watch(suggestedEditRepositoryProvider).getPendingForResume(resumeId);
  const guard = SuggestionFabricationGuard();
  return [
    for (final edit in pending)
      SuggestionReviewItem(
        edit: edit,
        fabricationCheck:
            guard.check(originalText: edit.originalValue, suggestedText: edit.suggestedValue),
      ),
  ];
});

/// State for [GenerateSuggestionsController] - mirrors
/// `ResumeJdAnalysisController`'s exact sealed Idle/Running/Succeeded/Failed
/// shape, the established convention for a one-shot async action in this
/// codebase.
sealed class GenerateSuggestionsUiState {
  const GenerateSuggestionsUiState();
}

class GenerateSuggestionsIdle extends GenerateSuggestionsUiState {
  const GenerateSuggestionsIdle();
}

class GenerateSuggestionsRunning extends GenerateSuggestionsUiState {
  const GenerateSuggestionsRunning();
}

class GenerateSuggestionsSucceeded extends GenerateSuggestionsUiState {
  const GenerateSuggestionsSucceeded(this.count);
  final int count;
}

class GenerateSuggestionsFailed extends GenerateSuggestionsUiState {
  const GenerateSuggestionsFailed(this.message);
  final String message;
}

/// Triggers `GenerateResumeSuggestionsUseCase` for one resume against a
/// caller-supplied JD (the JD is a method argument, not part of the family
/// key, mirroring `ResumeEditorController.saveVersion(label)` - this
/// controller's own identity is just "which resume," the JD is per-call
/// input). `family` by `resumeId`, `autoDispose` so a second Editor/
/// Analysis session for the same or a different resume never reads stale
/// generation state left behind by a prior one.
class GenerateSuggestionsController extends AutoDisposeFamilyNotifier<GenerateSuggestionsUiState, int> {
  @override
  GenerateSuggestionsUiState build(int resumeId) => const GenerateSuggestionsIdle();

  Future<void> generate(ParsedJobDescription jd) async {
    state = const GenerateSuggestionsRunning();
    try {
      final created = await ref.read(generateResumeSuggestionsUseCaseProvider)(arg, jd);
      state = GenerateSuggestionsSucceeded(created.length);
      ref.invalidate(pendingSuggestionCountProvider(arg));
      ref.invalidate(suggestionReviewListProvider(arg));
    } catch (e) {
      state = GenerateSuggestionsFailed(friendlyErrorMessage(e));
    }
  }

  /// Returns to [GenerateSuggestionsIdle] - lets the trigger UI retry after
  /// a failure without needing a whole new screen instance.
  void reset() => state = const GenerateSuggestionsIdle();
}

final generateSuggestionsControllerProvider = NotifierProvider.autoDispose
    .family<GenerateSuggestionsController, GenerateSuggestionsUiState, int>(
  GenerateSuggestionsController.new,
);

/// Busy/error wrapper for [SuggestionReviewController] - the Review
/// screen's actual list always comes from [suggestionReviewListProvider],
/// never from here, mirroring `ResumeVersionControllerState`'s identical
/// "thin action-state, not a data cache" shape.
class SuggestionReviewActionState {
  const SuggestionReviewActionState({this.busyId, this.error});

  /// The `SuggestedEdit.id` currently being accepted/rejected, if any -
  /// lets the review screen disable just that one row's buttons rather
  /// than the whole list while an action is in flight.
  final int? busyId;
  final String? error;

  SuggestionReviewActionState copyWith({
    int? busyId,
    bool clearBusy = false,
    String? error,
    bool clearError = false,
  }) {
    return SuggestionReviewActionState(
      busyId: clearBusy ? null : (busyId ?? this.busyId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Accepts/rejects individual suggestions for one resume, via
/// `AcceptSuggestedEditUseCase`/`RejectSuggestedEditUseCase` - never a
/// direct repository call from the UI (docs/v3/01-prd.md's own "the UI
/// must never directly manipulate the database to perform these
/// operations"). `family` by `resumeId`, `autoDispose`, mirroring every
/// other per-resume controller in this feature.
class SuggestionReviewController extends AutoDisposeFamilyNotifier<SuggestionReviewActionState, int> {
  @override
  SuggestionReviewActionState build(int resumeId) => const SuggestionReviewActionState();

  Future<void> accept(int suggestedEditId) async {
    state = state.copyWith(busyId: suggestedEditId, clearError: true);
    try {
      await ref.read(acceptSuggestedEditUseCaseProvider)(suggestedEditId);
      ref.invalidate(suggestionReviewListProvider(arg));
      ref.invalidate(pendingSuggestionCountProvider(arg));
      // The Editor's own live composition just changed underneath it (a
      // block override was set) - invalidate so re-opening/returning to
      // the Editor reflects the merged content rather than a stale read.
      ref.invalidate(resumeEditorControllerProvider(arg));
      state = state.copyWith(clearBusy: true);
    } catch (e) {
      state = state.copyWith(clearBusy: true, error: friendlyErrorMessage(e));
    }
  }

  Future<void> reject(int suggestedEditId) async {
    state = state.copyWith(busyId: suggestedEditId, clearError: true);
    try {
      await ref.read(rejectSuggestedEditUseCaseProvider)(suggestedEditId);
      ref.invalidate(suggestionReviewListProvider(arg));
      ref.invalidate(pendingSuggestionCountProvider(arg));
      state = state.copyWith(clearBusy: true);
    } catch (e) {
      state = state.copyWith(clearBusy: true, error: friendlyErrorMessage(e));
    }
  }
}

final suggestionReviewControllerProvider = NotifierProvider.autoDispose
    .family<SuggestionReviewController, SuggestionReviewActionState, int>(
  SuggestionReviewController.new,
);
