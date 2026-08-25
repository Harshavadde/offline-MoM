import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../models/document.dart';
import '../../../../models/meeting.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/section_heading.dart';
import '../../../documents/presentation/widgets/document_list_tile.dart';
import '../../../meetings/presentation/widgets/meeting_list_tile.dart';
import '../../search_workspace_use_case.dart';
import '../providers/search_providers.dart';

/// True Workspace Search (Phase 2B requirement #2,
/// docs/v2/implementation/03-decisions.md ADR-028) - searches meetings,
/// documents, notes, summaries and transcripts through the single
/// [SearchWorkspaceUseCase], displays results grouped by Knowledge Source
/// kind, and filters by All/Meetings/Documents/Notes.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final formatted = DateFormat.yMMMd().format(picked);
    _controller.text = formatted;
    ref.read(searchQueryProvider.notifier).state = formatted;
    ref.read(recentSearchesProvider.notifier).add(formatted);
  }

  void _submit(String value) {
    ref.read(recentSearchesProvider.notifier).add(value);
  }

  void _selectRecent(String term) {
    _controller.text = term;
    ref.read(searchQueryProvider.notifier).state = term;
  }

  bool _hasNote(Set<String>? contentTypes) => contentTypes?.contains('note') ?? false;

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final filter = ref.watch(searchScopeFilterProvider);
    final resultsAsync = ref.watch(searchResultsProvider);
    final recentSearches = ref.watch(recentSearchesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search meetings, documents, notes…',
            border: InputBorder.none,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                    },
                  ),
          ),
          onChanged: (value) => ref.read(searchQueryProvider.notifier).state = value,
          onSubmitted: _submit,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Search by date',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'Ask the AI Workspace',
            onPressed: () => context.push(RoutePaths.chat),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const [
                    (SearchScopeFilter.all, 'All'),
                    (SearchScopeFilter.meetings, 'Meetings'),
                    (SearchScopeFilter.documents, 'Documents'),
                    (SearchScopeFilter.notes, 'Notes'),
                  ]) ...[
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: filter == entry.$1,
                      onSelected: (_) =>
                          ref.read(searchScopeFilterProvider.notifier).state = entry.$1,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          if (query.isEmpty && recentSearches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeading(
                    'Recent searches',
                    onAction: () => ref.read(recentSearchesProvider.notifier).clear(),
                    actionLabel: 'Clear',
                    dense: true,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final term in recentSearches)
                        ActionChip(
                          avatar: Icon(Icons.history_rounded, size: 16, color: scheme.onSurfaceVariant),
                          label: Text(term),
                          onPressed: () => _selectRecent(term),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorState(title: 'Search didn\'t work', error: err),
              data: (allResults) {
                final meetings = _filterMeetings(allResults, filter);
                final documents = _filterDocuments(allResults, filter);

                if (meetings.isEmpty && documents.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off_rounded,
                    title: query.isEmpty ? 'Search your workspace' : 'No matches',
                    message: query.isEmpty
                        ? 'Search meetings, documents, notes, summaries and '
                            'transcripts - or a date.'
                        : 'Nothing matches "$query" in this filter.',
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (documents.isNotEmpty) ...[
                      _SectionHeader(label: 'Documents', count: documents.length),
                      const SizedBox(height: 10),
                      for (final document in documents) ...[
                        DocumentListTile(
                          document: document,
                          onTap: () {
                            if (query.isNotEmpty) _submit(query);
                            context.push(
                              RoutePaths.documentDetailsPath(document.id!),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (meetings.isNotEmpty) ...[
                      if (documents.isNotEmpty) const SizedBox(height: 8),
                      _SectionHeader(label: 'Meetings', count: meetings.length),
                      const SizedBox(height: 10),
                      for (final meeting in meetings) ...[
                        MeetingListTile(
                          meeting: meeting,
                          onTap: () {
                            if (query.isNotEmpty) _submit(query);
                            context.push(RoutePaths.meetingDetailsPath(meeting.id!));
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Meeting> _filterMeetings(SearchResults results, SearchScopeFilter filter) {
    switch (filter) {
      case SearchScopeFilter.documents:
        return const [];
      case SearchScopeFilter.notes:
        return results.meetings
            .where((m) => _hasNote(results.meetingContentTypes[m.id]))
            .toList();
      case SearchScopeFilter.all:
      case SearchScopeFilter.meetings:
        return results.meetings;
    }
  }

  List<Document> _filterDocuments(SearchResults results, SearchScopeFilter filter) {
    switch (filter) {
      case SearchScopeFilter.meetings:
        return const [];
      case SearchScopeFilter.notes:
        return results.documents
            .where((d) => _hasNote(results.documentContentTypes[d.id]))
            .toList();
      case SearchScopeFilter.all:
      case SearchScopeFilter.documents:
        return results.documents;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
