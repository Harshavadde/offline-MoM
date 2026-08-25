import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../models/document.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/knowledge_source_card.dart';

/// Thin wrapper around the shared `KnowledgeSourceCard`
/// (lib/shared/widgets/knowledge_source_card.dart, Phase 2B ADR-028) -
/// translates [Document]/[DocumentStatus] into that widget's generic
/// parameters. Mirrors `MeetingListTile`'s shape exactly
/// (lib/features/meetings/presentation/widgets/meeting_list_tile.dart), just
/// with no favorite-star trailing control (documents don't have one).
class DocumentListTile extends StatelessWidget {
  const DocumentListTile({
    super.key,
    required this.document,
    this.onTap,
    this.onDelete,
  });

  final Document document;
  final VoidCallback? onTap;

  /// When provided, the tile becomes swipe-to-delete (with a confirmation
  /// dialog) - called after the user confirms.
  final VoidCallback? onDelete;

  static IconData _sourceIcon(DocumentSourceType sourceType) => switch (sourceType) {
        DocumentSourceType.pdf => Icons.picture_as_pdf_outlined,
        DocumentSourceType.docx => Icons.description_outlined,
        DocumentSourceType.txt => Icons.article_outlined,
        DocumentSourceType.markdown => Icons.article_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isReady = document.status == DocumentStatus.ready;

    return KnowledgeSourceCard(
      icon: _sourceIcon(document.sourceType),
      title: document.title,
      updatedLabel: DateFormat.yMMMd().add_jm().format(document.updatedAt),
      sizeLabel: formatFileSize(document.fileSizeBytes),
      statusLabel: _statusLabel(document.status),
      statusColor: _statusColor(document.status, scheme),
      progress: _pipelineProgress(document.status),
      isSummaryAvailable: isReady,
      isSearchable: isReady,
      onTap: onTap,
      onDelete: onDelete,
      dismissibleKey: ValueKey('document-${document.id}'),
      deleteConfirmTitle: 'Delete document?',
      deleteConfirmMessage:
          'This permanently deletes "${document.title}" and its summary. '
          'This can\'t be undone.',
    );
  }
}

/// Mirrors meeting_list_tile.dart's `_pipelineProgress` - a coarse,
/// stage-based sense of "how far along" a document's pipeline is. Null
/// once there's no more pipeline left to show progress through
/// (ready/error). [DocumentStatus.indexing] isn't reachable in Phase 1A
/// (see [Document]'s doc comment) but is still given a sane value here so
/// the mapping stays exhaustive and correct once Phase 1B starts using it.
double? _pipelineProgress(DocumentStatus status) => switch (status) {
      DocumentStatus.created => 0.1,
      DocumentStatus.extracting => 0.35,
      DocumentStatus.downloadingSummaryModel => 0.6,
      DocumentStatus.summarizing => 0.8,
      DocumentStatus.indexing => 0.95,
      DocumentStatus.ready => null,
      DocumentStatus.error => null,
    };

String _statusLabel(DocumentStatus status) {
  final progress = _pipelineProgress(status);
  final baseLabel = switch (status) {
    DocumentStatus.created => 'New',
    DocumentStatus.extracting => 'Extracting text',
    DocumentStatus.downloadingSummaryModel => 'Downloading AI model',
    DocumentStatus.summarizing => 'Summarizing',
    DocumentStatus.indexing => 'Indexing',
    DocumentStatus.ready => 'Ready',
    DocumentStatus.error => 'Error',
  };
  // R-8.1 fix (same bug/fix as meeting_list_tile.dart's R-6 fix): this used
  // to render as "Summarizing 80%" - `_pipelineProgress` is a fixed
  // stage-position marker used only to position `KnowledgeSourceCard`'s
  // progress bar, never a real, measured completion percentage for
  // extraction/summarization/indexing. A static number that never moves
  // for the whole duration of a stage reads exactly like the app is stuck;
  // an ellipsis honestly signals "in progress, no further detail
  // available" instead of implying precision this app doesn't have.
  return progress == null ? baseLabel : '$baseLabel…';
}

Color _statusColor(DocumentStatus status, ColorScheme scheme) => switch (status) {
      DocumentStatus.created => scheme.outline,
      DocumentStatus.extracting => scheme.tertiary,
      DocumentStatus.downloadingSummaryModel => scheme.tertiary,
      DocumentStatus.summarizing => scheme.tertiary,
      DocumentStatus.indexing => scheme.tertiary,
      DocumentStatus.ready => scheme.primary,
      DocumentStatus.error => scheme.error,
    };
