import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/search/search_workspace_use_case.dart';
import '../../../../models/document.dart';
import '../../../../providers/app_providers.dart';
import '../../../meetings/presentation/providers/meeting_providers.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

/// Which Knowledge Source kind the Workspace Search results are filtered to
/// (Phase 2B requirement #2, docs/v2/implementation/03-decisions.md
/// ADR-028) - local to the search screen, same reasoning as
/// `_historyFilterProvider` in `history_screen.dart`.
enum SearchScopeFilter { all, meetings, documents, notes }

final searchScopeFilterProvider =
    StateProvider<SearchScopeFilter>((ref) => SearchScopeFilter.all);

/// Empty query browses all meetings and shows no documents (reusing the
/// already-fetched meeting list, same as before documents existed); a
/// non-empty query fans out across meeting name, transcript, action items,
/// decisions, date, documents and document summaries via
/// [SearchWorkspaceUseCase].
final searchResultsProvider = FutureProvider<SearchResults>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) {
    final meetings = await ref.watch(meetingListProvider.future);
    return SearchResults(meetings: meetings, documents: const <Document>[]);
  }
  return ref.watch(searchWorkspaceUseCaseProvider)(query);
});

/// The last few search terms a user actually committed (submitted), stored
/// in the same Hive box as app settings under their own key - it's session
/// history, not a user preference, so it lives separately from
/// [AppSettings] rather than bloating that model.
class RecentSearchesController extends Notifier<List<String>> {
  static const _key = 'recent_searches';
  static const _maxEntries = 8;

  @override
  List<String> build() {
    final raw = ref.watch(settingsBoxProvider).get(_key);
    if (raw == null) return const [];
    return List<String>.from(raw as List);
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final deduped = [
      trimmed,
      ...state.where((s) => s.toLowerCase() != trimmed.toLowerCase()),
    ];
    final capped = deduped.take(_maxEntries).toList();
    state = capped;
    await ref.read(settingsBoxProvider).put(_key, capped);
  }

  Future<void> clear() async {
    state = const [];
    await ref.read(settingsBoxProvider).put(_key, const <String>[]);
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
  RecentSearchesController.new,
);
