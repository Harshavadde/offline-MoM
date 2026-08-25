import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../models/meeting.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/knowledge_source_card.dart';

/// Thin wrapper around the shared `KnowledgeSourceCard`
/// (lib/shared/widgets/knowledge_source_card.dart, Phase 2B ADR-028) -
/// translates [Meeting]/[MeetingStatus] into that widget's generic
/// parameters and adds the meeting-only favorite star.
class MeetingListTile extends StatelessWidget {
  const MeetingListTile({
    super.key,
    required this.meeting,
    this.onTap,
    this.onDelete,
    this.onToggleFavorite,
  });

  final Meeting meeting;
  final VoidCallback? onTap;

  /// When provided, the tile becomes swipe-to-delete (with a confirmation
  /// dialog) - called after the user confirms.
  final VoidCallback? onDelete;

  /// When provided, shows a tappable star so a meeting can be favorited
  /// right from the list, without opening its details.
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onToggleFavorite = this.onToggleFavorite;
    final isReady = meeting.status == MeetingStatus.ready;

    return KnowledgeSourceCard(
      icon: meeting.source == MeetingSource.recorded
          ? Icons.mic_none_rounded
          : Icons.file_upload_outlined,
      title: meeting.title,
      updatedLabel: DateFormat.yMMMd().add_jm().format(meeting.updatedAt),
      sizeLabel: meeting.durationSeconds > 0
          ? formatDurationSeconds(meeting.durationSeconds)
          : null,
      statusLabel: _statusLabel(meeting.status),
      statusColor: _statusColor(meeting.status, scheme),
      progress: _pipelineProgress(meeting.status),
      isSummaryAvailable: isReady,
      isSearchable: isReady,
      onTap: onTap,
      onDelete: onDelete,
      dismissibleKey: ValueKey('meeting-${meeting.id}'),
      deleteConfirmTitle: 'Delete meeting?',
      deleteConfirmMessage:
          'This permanently deletes "${meeting.title}" and its transcript, '
          'summary, action items and notes. This can\'t be undone.',
      trailing: onToggleFavorite == null
          ? null
          : IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              icon: Icon(
                meeting.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: meeting.isFavorite ? scheme.primary : scheme.onSurfaceVariant,
                size: 20,
              ),
              tooltip: meeting.isFavorite ? 'Unfavorite' : 'Favorite',
              onPressed: onToggleFavorite,
            ),
    );
  }
}

/// A coarse, stage-based sense of "how far along" a meeting's pipeline is -
/// not a byte-accurate download percentage (see the onboarding model-setup
/// screen for that), just enough to show visible movement in the list
/// instead of a status word that looks identical whether it just started
/// or is about to finish. Null once there's no more pipeline left to show
/// progress through (ready/error).
double? _pipelineProgress(MeetingStatus status) => switch (status) {
      MeetingStatus.created => 0.05,
      MeetingStatus.downloadingModel => 0.2,
      MeetingStatus.transcribing => 0.45,
      MeetingStatus.downloadingSummaryModel => 0.65,
      MeetingStatus.summarizing => 0.85,
      MeetingStatus.indexing => 0.95,
      MeetingStatus.ready => null,
      MeetingStatus.error => null,
      MeetingStatus.audioMissing => null,
    };

String _statusLabel(MeetingStatus status) {
  final progress = _pipelineProgress(status);
  final baseLabel = switch (status) {
    MeetingStatus.created => 'New',
    MeetingStatus.downloadingModel => 'Downloading model',
    MeetingStatus.transcribing => 'Transcribing',
    MeetingStatus.downloadingSummaryModel => 'Downloading AI model',
    MeetingStatus.summarizing => 'Summarizing',
    MeetingStatus.indexing => 'Indexing',
    MeetingStatus.ready => 'Ready',
    MeetingStatus.error => 'Error',
    MeetingStatus.audioMissing => 'Audio missing',
  };
  // R-6 fix: this used to render as "Transcribing 45%" - `_pipelineProgress`
  // is a fixed stage-position marker (this stage is the 3rd of ~6), not a
  // real, moving completion percentage - Whisper's own native transcribe
  // call has no fine-grained progress callback at all (confirmed by reading
  // WhisperSpeechToTextEngine.transcribe directly), so there is nothing to
  // report *within* this stage. Presenting a static number that never moves
  // for the entire (potentially many-minute) duration of a stage reads
  // exactly like the app is stuck, even when it's genuinely still working -
  // an ellipsis honestly signals "in progress, no further detail available"
  // instead of implying precision this app doesn't have.
  return progress == null ? baseLabel : '$baseLabel…';
}

Color _statusColor(MeetingStatus status, ColorScheme scheme) => switch (status) {
      MeetingStatus.created => scheme.outline,
      MeetingStatus.downloadingModel => scheme.tertiary,
      MeetingStatus.transcribing => scheme.tertiary,
      MeetingStatus.downloadingSummaryModel => scheme.tertiary,
      MeetingStatus.summarizing => scheme.tertiary,
      MeetingStatus.indexing => scheme.tertiary,
      MeetingStatus.ready => scheme.primary,
      MeetingStatus.error => scheme.error,
      MeetingStatus.audioMissing => scheme.error,
    };
