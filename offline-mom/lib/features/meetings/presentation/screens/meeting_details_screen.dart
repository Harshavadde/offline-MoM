import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../features/chat/presentation/providers/chat_providers.dart';
import '../../../../models/action_item.dart';
import '../../../../models/chat_session.dart';
import '../../../../models/meeting.dart';
import '../../../../models/note.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/audio/audio_player_service.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/ai_disclaimer.dart';
import '../../../../shared/widgets/ai_pipeline_fallback.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/info_row.dart';
import '../../../../shared/widgets/text_input_dialog.dart';
import '../../../ai_summary/presentation/providers/ai_summary_providers.dart';
import '../../../recording/presentation/providers/recording_providers.dart';
import '../../../transcription/presentation/providers/transcript_providers.dart';
import '../providers/meeting_providers.dart';
import '../providers/notes_providers.dart';
import '../providers/pipeline_retry.dart';

/// A single meeting's full detail, as tabs (Overview/Transcript/Summary/MoM/
/// Action Items/Notes) rather than one push route per section - matches
/// the mockup and lets a user flip between them without losing their place
/// in the navigation stack.
///
/// No Decisions tab: the AI no longer extracts decisions (see
/// `LlamaDartLlmEngine`'s doc comment) and there's no manual-add path for
/// them either, so a tab that could genuinely never contain anything
/// would just be confusing dead UI rather than a real feature.
class MeetingDetailsScreen extends ConsumerWidget {
  const MeetingDetailsScreen({super.key, required this.meetingId});

  final int meetingId;

  static const _tabs = [
    (icon: Icons.dashboard_outlined, label: 'Overview'),
    (icon: Icons.subject_rounded, label: 'Transcript'),
    (icon: Icons.summarize_outlined, label: 'Summary'),
    (icon: Icons.description_outlined, label: 'MoM'),
    (icon: Icons.checklist_rounded, label: 'Action Items'),
    (icon: Icons.sticky_note_2_outlined, label: 'Notes'),
  ];

  Future<void> _renameMeeting(
    BuildContext context,
    WidgetRef ref,
    Meeting meeting,
  ) async {
    final newTitle = await showTextInputDialog(
      context,
      title: 'Rename meeting',
      labelText: 'Title',
      initialValue: meeting.title,
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == meeting.title) {
      return;
    }

    await ref.read(meetingRepositoryProvider).update(
          meeting.copyWith(title: newTitle, updatedAt: DateTime.now()),
        );
    ref.invalidate(meetingByIdProvider(meeting.id!));
    ref.invalidate(meetingListProvider);
  }

  Future<void> _toggleFavorite(WidgetRef ref, Meeting meeting) async {
    await ref.read(meetingRepositoryProvider).update(
          meeting.copyWith(isFavorite: !meeting.isFavorite),
        );
    ref.invalidate(meetingByIdProvider(meeting.id!));
    ref.invalidate(meetingListProvider);
  }

  Future<void> _deleteMeeting(
    BuildContext context,
    WidgetRef ref,
    Meeting meeting,
  ) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete meeting?',
      message: 'This permanently deletes "${meeting.title}" and its transcript, '
          'summary, action items and decisions. This can\'t be undone.',
    );
    if (!confirmed) return;

    await ref.read(deleteMeetingUseCaseProvider)(meeting.id!);
    ref.invalidate(meetingListProvider);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetingAsync = ref.watch(meetingByIdProvider(meetingId));

    return meetingAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Meeting details')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Meeting details')),
        body: ErrorState(title: 'Couldn\'t load this meeting', error: err),
      ),
      data: (meeting) {
        if (meeting == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Meeting details')),
            body: const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Meeting not found',
              message: 'This meeting may have been deleted.',
            ),
          );
        }

        return DefaultTabController(
          length: _tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(meeting.title, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.forum_outlined),
                  tooltip: 'Chat about this meeting',
                  onPressed: () => context.push(
                    RoutePaths.chat,
                    extra: ChatLaunchArgs(scope: ChatScope.meeting, meetingId: meeting.id),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    meeting.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  ),
                  tooltip: meeting.isFavorite ? 'Unfavorite' : 'Favorite',
                  onPressed: () => _toggleFavorite(ref, meeting),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename',
                  onPressed: () => _renameMeeting(context, ref, meeting),
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Export as PDF',
                  onPressed: () => context.push(RoutePaths.exportPath(meeting.id!)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Delete',
                  onPressed: () => _deleteMeeting(context, ref, meeting),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final tab in _tabs)
                    Tab(icon: Icon(tab.icon, size: 20), text: tab.label),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _OverviewTab(meeting: meeting),
                _TranscriptTab(meetingId: meeting.id!),
                _SummaryTab(meetingId: meeting.id!),
                _MomTab(meetingId: meeting.id!),
                _ActionItemsTab(meetingId: meeting.id!),
                _NotesTab(meetingId: meeting.id!),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.meeting});

  final Meeting meeting;

  String _statusLabel(MeetingStatus status) => switch (status) {
        MeetingStatus.created => 'Waiting to process',
        MeetingStatus.downloadingModel => 'Downloading speech model',
        MeetingStatus.transcribing => 'Transcribing',
        MeetingStatus.downloadingSummaryModel => 'Downloading AI model',
        MeetingStatus.summarizing => 'Generating summary',
        MeetingStatus.indexing => 'Indexing',
        MeetingStatus.ready => 'Ready',
        MeetingStatus.error => 'Failed',
        MeetingStatus.audioMissing => 'Audio missing',
      };

  @override
  Widget build(BuildContext context) {
    final rows = [
      (
        icon: Icons.calendar_today_outlined,
        label: 'Recorded',
        value: DateFormat.yMMMd().add_jm().format(meeting.createdAt),
      ),
      (
        icon: meeting.source == MeetingSource.recorded
            ? Icons.mic_none_rounded
            : Icons.file_upload_outlined,
        label: 'Source',
        value: meeting.source == MeetingSource.recorded ? 'Recorded' : 'Imported',
      ),
      (
        icon: Icons.timer_outlined,
        label: 'Duration',
        value: meeting.durationSeconds > 0
            ? formatDurationSeconds(meeting.durationSeconds)
            : 'Unknown',
      ),
      (
        icon: Icons.info_outline_rounded,
        label: 'Status',
        value: _statusLabel(meeting.status),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final row in rows) ...[
          InfoRow(icon: row.icon, label: row.label, value: row.value),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// A small "stuck? retry" affordance for the Transcript tab's in-progress
/// states ([MeetingStatus.downloadingModel]/[MeetingStatus.transcribing]).
/// Mirrors [AiPipelineFallback]'s private helper of the same purpose: the
/// transcribe/summarize pipeline runs unawaited in the background, so if
/// Android kills the app process while it's backgrounded (ordinary during a
/// long download), the meeting is left showing this exact status forever
/// with nothing actually running behind it - without this, that was a dead
/// end, since retry previously only ever appeared for [MeetingStatus.error].
List<Widget> _stuckRetryAffordance(BuildContext context, WidgetRef ref, int meetingId) {
  return [
    const SizedBox(height: 20),
    Text(
      'Taking much longer than expected? This can happen if the app '
      'was closed or lost its connection mid-way.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    ),
    const SizedBox(height: 8),
    TextButton.icon(
      onPressed: () => retryMeetingProcessing(ref, meetingId),
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Retry'),
    ),
  ];
}

class _TranscriptTab extends ConsumerWidget {
  const _TranscriptTab({required this.meetingId});

  final int meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcriptAsync = ref.watch(transcriptForMeetingProvider(meetingId));
    final meetingAsync = ref.watch(meetingByIdProvider(meetingId));

    return transcriptAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load the transcript', error: err),
      data: (transcript) {
        if (transcript != null) {
          final audioPath = meetingAsync.valueOrNull?.audioFilePath;
          return Column(
            children: [
              if (audioPath != null)
                _PlaybackBar(meetingId: meetingId, audioFilePath: audioPath),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: transcript.segments.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final segment = transcript.segments[index];
                    return Text(segment.text, style: Theme.of(context).textTheme.bodyLarge);
                  },
                ),
              ),
            ],
          );
        }

        final meeting = meetingAsync.valueOrNull;
        if (meeting?.status == MeetingStatus.downloadingModel) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(
                    'Downloading the speech model…',
                    style: TextStyle(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'One-time download (tens to a few hundred MB, '
                    'depending on the model in Settings > AI Models). '
                    'Needs a working internet connection just this once - '
                    'every transcription after this runs fully offline.',
                    textAlign: TextAlign.center,
                  ),
                  ..._stuckRetryAffordance(context, ref, meetingId),
                ],
              ),
            ),
          );
        }
        // Real-device QA finding: `created` and `indexing` previously fell
        // straight through to the generic "No transcript yet" empty state
        // below, with no retry affordance at all - a meeting killed before
        // transcription ever started (`created`) or after it finished but
        // before indexing completed (`indexing`) had no way to recover
        // short of deleting it. Both get the same in-progress treatment
        // `transcribing` already had; `RetryMeetingProcessingUseCase`
        // already resumes correctly from either state.
        if (meeting?.status == MeetingStatus.transcribing ||
            meeting?.status == MeetingStatus.created ||
            meeting?.status == MeetingStatus.indexing) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Transcribing your meeting…'),
                  ..._stuckRetryAffordance(context, ref, meetingId),
                ],
              ),
            ),
          );
        }
        // Real-device QA finding: `audioMissing` previously fell through
        // to the generic empty state too, unlike its sibling tabs
        // (Summary/MoM already handle it) - same error-with-retry
        // treatment as `error`, using the meeting's own errorMessage.
        if (meeting?.status == MeetingStatus.error ||
            meeting?.status == MeetingStatus.audioMissing) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Transcription failed',
                    message: 'Something went wrong while transcribing this meeting.',
                  ),
                  if (meeting?.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      // V2.2 Production Hardening, Priority 6: was the raw
                      // stored exception text in a monospace debug style -
                      // see AiPipelineFallback's identical fix for the
                      // full reasoning (this tab has its own error block
                      // rather than reusing that widget, so needs the same
                      // fix applied here too).
                      child: SelectableText(
                        friendlyErrorMessage(meeting!.errorMessage!),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => retryMeetingProcessing(ref, meetingId),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return const EmptyState(
          icon: Icons.subject_rounded,
          title: 'No transcript yet',
          message: 'Offline speech-to-text runs automatically once '
              'recording/import is available — the transcript will appear here.',
        );
      },
    );
  }
}

/// Play/pause/seek for the meeting's own audio file, plus tappable chips
/// for any recording marks - jumping straight to a bookmarked moment while
/// reading the transcript alongside it.
class _PlaybackBar extends ConsumerStatefulWidget {
  const _PlaybackBar({required this.meetingId, required this.audioFilePath});

  final int meetingId;
  final String audioFilePath;

  @override
  ConsumerState<_PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends ConsumerState<_PlaybackBar> {
  PlaybackStatus _status = PlaybackStatus.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription<PlaybackStatus>? _statusSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  AudioPlayerService get _player => ref.read(audioPlayerServiceProvider);

  @override
  void initState() {
    super.initState();
    _statusSub = _player.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _positionSub = _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    switch (_status) {
      case PlaybackStatus.playing:
        await _player.pause();
      case PlaybackStatus.paused:
        await _player.resume();
      case PlaybackStatus.stopped:
      case PlaybackStatus.completed:
        await _player.playFile(widget.audioFilePath);
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    // Watching (not just reading) so the provider - and the AudioPlayer it
    // owns - stays alive for as long as this bar is on screen; it's
    // autoDispose, so it tears itself (and playback) down once this widget
    // unmounts.
    ref.watch(audioPlayerServiceProvider);
    final marksAsync = ref.watch(recordingMarksForMeetingProvider(widget.meetingId));
    final scheme = Theme.of(context).colorScheme;
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1;
    final sliderValue = _position.inMilliseconds.clamp(0, maxMs).toDouble();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _status == PlaybackStatus.playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 36,
                  color: scheme.primary,
                ),
                tooltip: _status == PlaybackStatus.playing ? 'Pause audio' : 'Play audio',
                onPressed: _togglePlayback,
              ),
              Expanded(
                child: Slider(
                  value: sliderValue,
                  max: maxMs.toDouble(),
                  onChanged: (value) {
                    setState(() => _position = Duration(milliseconds: value.toInt()));
                  },
                  onChangeEnd: (value) =>
                      _player.seek(Duration(milliseconds: value.toInt())),
                ),
              ),
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          marksAsync.maybeWhen(
            data: (marks) {
              if (marks.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final mark in marks)
                        ActionChip(
                          avatar: const Icon(Icons.flag_outlined, size: 14),
                          label: Text(_formatDuration(Duration(milliseconds: mark.offsetMs))),
                          onPressed: () async {
                            if (_status != PlaybackStatus.playing &&
                                _status != PlaybackStatus.paused) {
                              await _player.playFile(widget.audioFilePath);
                            }
                            await _player.seek(Duration(milliseconds: mark.offsetMs));
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.meetingId});

  final int meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(summaryForMeetingProvider(meetingId));
    final meetingAsync = ref.watch(meetingByIdProvider(meetingId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load this summary', error: err),
      data: (summary) {
        if (summary == null) {
          final status = meetingAsync.valueOrNull?.status;
          return AiPipelineFallback(
            isDownloadingModel: status == MeetingStatus.downloadingSummaryModel,
            // Real-device QA finding: `created` previously had no case
            // here either (falls to the plain "not ready" empty state,
            // same gap as the Transcript tab) - a meeting killed before
            // transcription ever started has no retry affordance without
            // this. `indexing` doesn't need adding: by that point the
            // summary row already exists, so the non-null `data` branch
            // above already renders the real content, not this fallback.
            isGenerating: status == MeetingStatus.summarizing ||
                status == MeetingStatus.created,
            hasError: status == MeetingStatus.error || status == MeetingStatus.audioMissing,
            notReadyIcon: Icons.summarize_outlined,
            notReadyTitle: 'No summary yet',
            notReadyMessage: 'The on-device AI generates a summary '
                'automatically once a transcript is available.',
            errorTitle: status == MeetingStatus.audioMissing
                ? 'Audio file missing'
                : 'AI summary failed',
            errorDescription: status == MeetingStatus.audioMissing
                ? 'The recording for this meeting could not be found on '
                    'this device.'
                : 'Something went wrong while generating the summary for '
                    'this meeting.',
            errorMessage: meetingAsync.valueOrNull?.errorMessage,
            onRetry: () => retryMeetingProcessing(ref, meetingId),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AiDisclaimer(),
            const SizedBox(height: 8),
            Text(summary.summaryText, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            Text('Key topics', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final topic in summary.keyTopics) Chip(label: Text(topic)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MomTab extends ConsumerWidget {
  const _MomTab({required this.meetingId});

  final int meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(summaryForMeetingProvider(meetingId));
    final meetingAsync = ref.watch(meetingByIdProvider(meetingId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load the minutes of meeting', error: err),
      data: (summary) {
        if (summary == null) {
          final status = meetingAsync.valueOrNull?.status;
          return AiPipelineFallback(
            isDownloadingModel: status == MeetingStatus.downloadingSummaryModel,
            // Real-device QA finding: `created` previously had no case
            // here either (falls to the plain "not ready" empty state,
            // same gap as the Transcript tab) - a meeting killed before
            // transcription ever started has no retry affordance without
            // this. `indexing` doesn't need adding: by that point the
            // summary row already exists, so the non-null `data` branch
            // above already renders the real content, not this fallback.
            isGenerating: status == MeetingStatus.summarizing ||
                status == MeetingStatus.created,
            hasError: status == MeetingStatus.error || status == MeetingStatus.audioMissing,
            notReadyIcon: Icons.description_outlined,
            notReadyTitle: 'No Minutes of Meeting yet',
            notReadyMessage: 'A formal MoM document is generated '
                'automatically alongside the summary.',
            errorTitle: status == MeetingStatus.audioMissing
                ? 'Audio file missing'
                : 'AI summary failed',
            errorDescription: status == MeetingStatus.audioMissing
                ? 'The recording for this meeting could not be found on '
                    'this device.'
                : 'Something went wrong while generating the summary for '
                    'this meeting.',
            errorMessage: meetingAsync.valueOrNull?.errorMessage,
            onRetry: () => retryMeetingProcessing(ref, meetingId),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AiDisclaimer(),
            const SizedBox(height: 8),
            Text(summary.minutesOfMeeting, style: Theme.of(context).textTheme.bodyLarge),
          ],
        );
      },
    );
  }
}

class _ActionItemsTab extends ConsumerWidget {
  const _ActionItemsTab({required this.meetingId});

  final int meetingId;

  Future<void> _addActionItem(BuildContext context, WidgetRef ref) async {
    // No TextEditingControllers here deliberately - `TextFormField.onChanged`
    // avoids owning controllers whose lifetime would need to outlive
    // `showDialog`'s returned Future (which completes at `pop()`, before the
    // dialog's own exit transition has finished rebuilding its still-mounted
    // `TextField`s one more time - disposing controllers in a `finally`
    // right after that Future resolves races that last rebuild).
    var enteredDescription = '';
    var enteredOwner = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add action item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (value) => enteredDescription = value,
            ),
            const SizedBox(height: 12),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Owner (optional)'),
              onChanged: (value) => enteredOwner = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final description = enteredDescription.trim();
    final owner = enteredOwner.trim();

    if (saved != true || description.isEmpty) return;

    await ref.read(actionItemRepositoryProvider).insert(
          ActionItem(
            id: null,
            meetingId: meetingId,
            description: description,
            owner: owner.isEmpty ? null : owner,
            isCompleted: false,
            createdAt: DateTime.now(),
          ),
        );
    ref.invalidate(actionItemsForMeetingProvider(meetingId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(actionItemsForMeetingProvider(meetingId));

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addActionItem(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(title: 'Couldn\'t load action items', error: err),
        data: (items) {
          // Purely manual now - the AI no longer extracts these (see
          // LlamaDartLlmEngine), so there's no "waiting on the pipeline"
          // state to show here, only "add one" if the list is empty.
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.checklist_rounded,
              title: 'No action items yet',
              message: 'Tap + to add one.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final item = items[index];
              return Dismissible(
                key: ValueKey(item.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) {
                  ref.read(actionItemRepositoryProvider).delete(item.id!);
                  ref.invalidate(actionItemsForMeetingProvider(meetingId));
                },
                child: CheckboxListTile(
                  value: item.isCompleted,
                  title: Text(item.description),
                  subtitle: item.owner != null ? Text(item.owner!) : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (checked) {
                    ref
                        .read(actionItemRepositoryProvider)
                        .setCompleted(item.id!, checked ?? false);
                    ref.invalidate(actionItemsForMeetingProvider(meetingId));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotesTab extends ConsumerWidget {
  const _NotesTab({required this.meetingId});

  final int meetingId;

  Future<void> _addOrEditNote(
    BuildContext context,
    WidgetRef ref, {
    Note? existing,
  }) async {
    // No TextEditingController here deliberately - `TextFormField.initialValue`
    // + `onChanged` avoids owning a controller whose lifetime would need to
    // outlive `showDialog`'s returned Future (which completes at `pop()`,
    // before the dialog's own exit transition has finished rebuilding its
    // still-mounted `TextField` one more time - disposing a controller in a
    // `finally` right after that Future resolves races that last rebuild).
    var enteredContent = existing?.content ?? '';
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'Add note' : 'Edit note'),
        content: TextFormField(
          initialValue: existing?.content ?? '',
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Type your note…'),
          onChanged: (value) => enteredContent = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(enteredContent.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (content == null || content.isEmpty) return;
    final notes = ref.read(notesControllerProvider);
    if (existing == null) {
      await notes.add(meetingId, content);
    } else {
      await notes.edit(existing, content);
    }
  }

  Future<void> _deleteNote(BuildContext context, WidgetRef ref, Note note) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete note?',
      message: 'This permanently deletes this note. This can\'t be undone.',
    );
    if (!confirmed) return;

    await ref.read(notesControllerProvider).delete(note);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesForMeetingProvider(meetingId));

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditNote(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(title: 'Couldn\'t load notes', error: err),
        data: (notes) {
          if (notes.isEmpty) {
            return const EmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: 'No notes yet',
              message: 'Jot down anything the AI might miss - tap the '
                  '+ button to add your first note.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: notes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                child: ListTile(
                  title: Text(note.content),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(note.updatedAt)),
                  onTap: () => _addOrEditNote(context, ref, existing: note),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Delete note',
                    onPressed: () => _deleteNote(context, ref, note),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
