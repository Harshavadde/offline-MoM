import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../models/meeting.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/entrance_fade.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/skeleton_loader.dart';
import '../providers/meeting_providers.dart';
import '../widgets/meeting_list_tile.dart';

enum _HistoryFilter { all, favorites, recorded, imported }

/// Local to this screen - which meetings match is a pure UI concern, not
/// something any other feature needs to read.
final _historyFilterProvider = StateProvider<_HistoryFilter>((ref) => _HistoryFilter.all);

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  bool _matches(Meeting meeting, _HistoryFilter filter) => switch (filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.favorites => meeting.isFavorite,
        _HistoryFilter.recorded => meeting.source == MeetingSource.recorded,
        _HistoryFilter.imported => meeting.source == MeetingSource.imported,
      };

  Future<void> _toggleFavorite(WidgetRef ref, Meeting meeting) async {
    await ref.read(meetingRepositoryProvider).update(
          meeting.copyWith(isFavorite: !meeting.isFavorite),
        );
    ref.invalidate(meetingListProvider);
    ref.invalidate(meetingByIdProvider(meeting.id!));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetingsAsync = ref.watch(meetingListProvider);
    final filter = ref.watch(_historyFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const [
                    (_HistoryFilter.all, 'All'),
                    (_HistoryFilter.favorites, 'Favorites'),
                    (_HistoryFilter.recorded, 'Recorded'),
                    (_HistoryFilter.imported, 'Imported'),
                  ]) ...[
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: filter == entry.$1,
                      onSelected: (_) =>
                          ref.read(_historyFilterProvider.notifier).state = entry.$1,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: meetingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: SkeletonCardList(),
              ),
              error: (err, _) => ErrorState(title: 'Couldn\'t load your history', error: err),
              data: (allMeetings) {
                final meetings =
                    allMeetings.where((m) => _matches(m, filter)).toList();

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: meetings.isEmpty
                      ? EmptyState(
                          key: const ValueKey('history-empty'),
                          icon: Icons.history_rounded,
                          title: filter == _HistoryFilter.all
                              ? 'No meeting history'
                              : 'No meetings match this filter',
                          message: filter == _HistoryFilter.all
                              ? 'Every meeting you record or import will '
                                  'show up here, newest first.'
                              : 'Try a different filter, or clear it to see '
                                  'every meeting.',
                        )
                      : ListView.separated(
                          key: const ValueKey('history-list'),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: meetings.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final meeting = meetings[index];
                            return EntranceFade(
                              delay: Duration(milliseconds: 20 * index),
                              child: MeetingListTile(
                                meeting: meeting,
                                onTap: () => context.push(
                                  RoutePaths.meetingDetailsPath(meeting.id!),
                                ),
                                onToggleFavorite: () => _toggleFavorite(ref, meeting),
                                onDelete: () async {
                                  await ref
                                      .read(deleteMeetingUseCaseProvider)(meeting.id!);
                                  ref.invalidate(meetingListProvider);
                                },
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
