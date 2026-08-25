import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../features/chat/presentation/providers/chat_providers.dart';
import '../../../../models/chat_session.dart';
import '../../../../models/document.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/ai_pipeline_fallback.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/info_row.dart';
import '../../../../shared/widgets/text_input_dialog.dart';
import '../../../ai_summary/presentation/providers/ai_summary_providers.dart';
import '../providers/document_providers.dart';
import '../providers/folder_providers.dart';

/// A single document's full detail, as tabs (Overview/Text/Summary) -
/// mirrors `meeting_details_screen.dart`'s structure
/// (lib/features/meetings/presentation/screens/meeting_details_screen.dart),
/// scoped down to the tabs that make sense for a document (no Transcript/
/// MoM/Action Items - those are meeting-specific pipeline stages).
class DocumentDetailsScreen extends ConsumerWidget {
  const DocumentDetailsScreen({super.key, required this.documentId});

  final int documentId;

  static const _tabs = [
    (icon: Icons.dashboard_outlined, label: 'Overview'),
    (icon: Icons.subject_rounded, label: 'Text'),
    (icon: Icons.summarize_outlined, label: 'Summary'),
  ];

  Future<void> _renameDocument(
    BuildContext context,
    WidgetRef ref,
    Document document,
  ) async {
    final newTitle = await showTextInputDialog(
      context,
      title: 'Rename document',
      labelText: 'Title',
      initialValue: document.title,
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == document.title) {
      return;
    }

    await ref.read(documentRepositoryProvider).update(
          document.copyWith(title: newTitle, updatedAt: DateTime.now()),
        );
    ref.invalidate(documentByIdProvider(document.id!));
    ref.invalidate(documentListProvider);
  }

  Future<void> _deleteDocument(
    BuildContext context,
    WidgetRef ref,
    Document document,
  ) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete document?',
      message: 'This permanently deletes "${document.title}" and its summary. '
          'This can\'t be undone.',
    );
    if (!confirmed) return;

    await ref.read(deleteDocumentUseCaseProvider)(document.id!);
    ref.invalidate(documentListProvider);
    if (context.mounted) Navigator.of(context).pop();
  }

  /// "Move to folder" (V2.2 Production Hardening, Priority 2) - lists
  /// every existing folder plus "All Documents" (the unfiled default) as
  /// a simple radio list, matching this screen's own dialog conventions
  /// exactly (a plain `AlertDialog`, not a new picker widget).
  Future<void> _moveToFolder(
    BuildContext context,
    WidgetRef ref,
    Document document,
    int? currentFolderId,
  ) async {
    final folders = await ref.read(folderRepositoryProvider).getAll();
    if (!context.mounted) return;

    // A record (not a bare `int?`) so "the dialog was dismissed without
    // choosing anything" (showDialog's own `null` for that case) can
    // never be confused with "the user explicitly chose All Documents"
    // (itself a real, meaningful `folderId: null`) - both would otherwise
    // collapse to the same `null` value.
    final chosen = await showDialog<({int? folderId})>(
      context: context,
      // RadioGroup<int?> wrapping bare RadioListTiles - the current,
      // non-deprecated way to group radio tiles (Flutter 3.32+), matching
      // `appearance_screen.dart`/`language_screen.dart`/
      // `recording_preferences_screen.dart`'s already-established
      // convention exactly, rather than the older per-tile
      // groupValue/onChanged API those screens already moved off of.
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          RadioGroup<int?>(
            groupValue: currentFolderId,
            onChanged: (value) => Navigator.of(dialogContext).pop((folderId: value)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RadioListTile<int?>(value: null, title: Text('All Documents')),
                for (final folder in folders)
                  RadioListTile<int?>(value: folder.id, title: Text(folder.title)),
              ],
            ),
          ),
        ],
      ),
    );

    if (chosen == null || chosen.folderId == currentFolderId) return;
    await moveDocumentToFolder(ref, document.id!, chosen.folderId);
    ref.invalidate(documentByIdProvider(document.id!));
    ref.invalidate(documentFolderIdProvider(document.id!));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentAsync = ref.watch(documentByIdProvider(documentId));

    return documentAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Document details')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Document details')),
        body: ErrorState(title: 'Couldn\'t load this document', error: err),
      ),
      data: (document) {
        if (document == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Document details')),
            body: const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Document not found',
              message: 'This document may have been deleted.',
            ),
          );
        }

        return DefaultTabController(
          length: _tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(document.title, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.forum_outlined),
                  // Phase 8B.3, Priority 5/8: previously enabled regardless
                  // of status - starting a document-scoped chat before
                  // this document is actually indexed meant nothing could
                  // ever be retrieved for it, so every question silently
                  // fell back to a general-knowledge answer that could
                  // look like it was about the document when it wasn't.
                  tooltip: document.status == DocumentStatus.ready
                      ? 'Chat about this document'
                      : 'Available once this document has finished processing',
                  onPressed: document.status == DocumentStatus.ready
                      ? () => context.push(
                            RoutePaths.chat,
                            extra: ChatLaunchArgs(scope: ChatScope.document, documentId: document.id),
                          )
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename',
                  onPressed: () => _renameDocument(context, ref, document),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: 'Move to folder',
                  onPressed: () async {
                    final currentFolderId =
                        await ref.read(documentFolderIdProvider(document.id!).future);
                    if (!context.mounted) return;
                    await _moveToFolder(context, ref, document, currentFolderId);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Delete',
                  onPressed: () => _deleteDocument(context, ref, document),
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
                _OverviewTab(document: document),
                _TextTab(documentId: document.id!),
                _SummaryTab(documentId: document.id!),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.document});

  final Document document;

  String _sourceLabel(DocumentSourceType sourceType) => switch (sourceType) {
        DocumentSourceType.pdf => 'PDF',
        DocumentSourceType.docx => 'Word document',
        DocumentSourceType.txt => 'Text file',
        DocumentSourceType.markdown => 'Markdown',
      };

  String _statusLabel(DocumentStatus status) => switch (status) {
        DocumentStatus.created => 'Waiting to process',
        DocumentStatus.extracting => 'Extracting text',
        DocumentStatus.downloadingSummaryModel => 'Downloading AI model',
        DocumentStatus.summarizing => 'Generating summary',
        DocumentStatus.indexing => 'Indexing',
        DocumentStatus.ready => 'Ready',
        DocumentStatus.error => 'Failed',
      };

  @override
  Widget build(BuildContext context) {
    final rows = [
      (
        icon: Icons.calendar_today_outlined,
        label: 'Imported',
        value: DateFormat.yMMMd().add_jm().format(document.createdAt),
      ),
      (
        icon: Icons.insert_drive_file_outlined,
        label: 'Original file',
        value: document.originalFilename,
      ),
      (
        icon: Icons.description_outlined,
        label: 'Type',
        value: _sourceLabel(document.sourceType),
      ),
      (
        icon: Icons.data_usage_outlined,
        label: 'Size',
        value: formatFileSize(document.fileSizeBytes),
      ),
      (
        icon: Icons.info_outline_rounded,
        label: 'Status',
        value: _statusLabel(document.status),
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

class _TextTab extends ConsumerWidget {
  const _TextTab({required this.documentId});

  final int documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentAsync = ref.watch(documentByIdProvider(documentId));

    return documentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load this document', error: err),
      data: (document) {
        if (document == null) {
          return const EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Document not found',
            message: 'This document may have been deleted.',
          );
        }

        final text = document.extractedText;
        if (text == null) {
          return AiPipelineFallback(
            isDownloadingModel: false,
            isGenerating: document.status == DocumentStatus.created ||
                document.status == DocumentStatus.extracting,
            hasError: document.status == DocumentStatus.error,
            notReadyIcon: Icons.subject_rounded,
            notReadyTitle: 'No text yet',
            notReadyMessage: 'Extracted text will appear here once this '
                'document has been processed.',
            errorTitle: 'Text extraction failed',
            errorDescription: 'Something went wrong while extracting text '
                'from this document.',
            errorMessage: document.errorMessage,
            onRetry: () => retryDocumentProcessing(ref, documentId),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SelectableText(text, style: Theme.of(context).textTheme.bodyLarge),
          ],
        );
      },
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.documentId});

  final int documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(summaryForDocumentProvider(documentId));
    final documentAsync = ref.watch(documentByIdProvider(documentId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load this summary', error: err),
      data: (summary) {
        if (summary == null) {
          final status = documentAsync.valueOrNull?.status;
          return AiPipelineFallback(
            isDownloadingModel: status == DocumentStatus.downloadingSummaryModel,
            isGenerating: status == DocumentStatus.summarizing,
            hasError: status == DocumentStatus.error,
            notReadyIcon: Icons.summarize_outlined,
            notReadyTitle: 'No summary yet',
            notReadyMessage: 'The on-device AI generates a summary '
                'automatically once this document\'s text has been '
                'extracted.',
            errorTitle: 'AI summary failed',
            errorDescription: 'Something went wrong while generating the '
                'summary for this document.',
            errorMessage: documentAsync.valueOrNull?.errorMessage,
            onRetry: () => retryDocumentProcessing(ref, documentId),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
