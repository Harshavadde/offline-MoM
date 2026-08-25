import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/document.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/documents/document_import_service.dart';
import '../../../ai_summary/presentation/providers/ai_summary_providers.dart';

/// Mirrors `meeting_providers.dart`'s shape
/// (lib/features/meetings/presentation/providers/meeting_providers.dart) -
/// plain `FutureProvider`s for reads.
final documentListProvider = FutureProvider<List<Document>>((ref) {
  return ref.watch(documentRepositoryProvider).getAll();
});

/// Document Manager improvement pass (Part D): the Documents screen's
/// search box text, filtered client-side against the already-fetched
/// folder's document list (title, case-insensitive substring match) -
/// screen-local, never persisted, same convention [selectedFolderProvider]
/// already uses (folder_providers.dart). Deliberately not a real FTS5
/// query against `extractedText` (that's `SearchWorkspaceUseCase`'s own,
/// separate, already-existing full-content search surfaced via the
/// dedicated Search tab) - this is a lightweight "find this document by
/// name in the list I'm already looking at" filter, not a duplicate
/// content-search feature.
final documentSearchQueryProvider = StateProvider<String>((ref) => '');

/// How the Documents screen's list is ordered - screen-local, never
/// persisted, same convention as [documentSearchQueryProvider].
enum DocumentSortOrder { titleAZ, newestFirst, oldestFirst, largestFirst }

final documentSortOrderProvider =
    StateProvider<DocumentSortOrder>((ref) => DocumentSortOrder.newestFirst);

/// Applies [documentSearchQueryProvider]/[documentSortOrderProvider] to
/// [documents] - the one place both filters are actually applied, reused
/// identically by every screen that lists documents rather than
/// duplicating the filter/sort logic per screen.
List<Document> applyDocumentSearchAndSort(
  List<Document> documents,
  String query,
  DocumentSortOrder order,
) {
  final trimmedQuery = query.trim().toLowerCase();
  final filtered = trimmedQuery.isEmpty
      ? documents
      : documents.where((d) => d.title.toLowerCase().contains(trimmedQuery)).toList();
  final sorted = List<Document>.of(filtered);
  switch (order) {
    case DocumentSortOrder.titleAZ:
      sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case DocumentSortOrder.newestFirst:
      sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case DocumentSortOrder.oldestFirst:
      sorted.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    case DocumentSortOrder.largestFirst:
      sorted.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
  }
  return sorted;
}

/// `autoDispose` (Phase 4B) - see `meetingByIdProvider`'s doc comment
/// (lib/features/meetings/presentation/providers/meeting_providers.dart) for
/// why every per-id detail-screen provider in this app uses it.
final documentByIdProvider =
    FutureProvider.autoDispose.family<Document?, int>((ref, id) {
  return ref.watch(documentRepositoryProvider).getById(id);
});

/// Mirrors `ImportController`'s sealed-state shape
/// (lib/features/import/presentation/providers/import_providers.dart).
sealed class DocumentImportUiState {
  const DocumentImportUiState();
}

class DocumentImportIdle extends DocumentImportUiState {
  const DocumentImportIdle();
}

class DocumentImportProcessing extends DocumentImportUiState {
  const DocumentImportProcessing();
}

class DocumentImportSucceeded extends DocumentImportUiState {
  const DocumentImportSucceeded(this.documentId);
  final int documentId;
}

class DocumentImportFailed extends DocumentImportUiState {
  const DocumentImportFailed(this.message);
  final String message;
}

/// Orchestrates importing a document, mirroring `ImportController` exactly
/// (lib/features/import/presentation/providers/import_providers.dart): the
/// actual pick+copy+insert work lives in [DocumentImportUseCase], so this
/// controller only owns UI state and kicks off the background processing
/// pipeline once the row exists.
class DocumentImportController extends Notifier<DocumentImportUiState> {
  @override
  DocumentImportUiState build() => const DocumentImportIdle();

  Future<void> importFile() async {
    // Phase 8C production-hardening finding: same gap as `ImportController
    // .importFile` (lib/features/import/presentation/providers/import_providers.dart)
    // - see that method's identical comment for the full reasoning.
    if (state is DocumentImportProcessing) return;
    state = const DocumentImportProcessing();

    try {
      final documentId = await ref.read(documentImportUseCaseProvider)();
      if (documentId == null) {
        state = const DocumentImportIdle();
        return;
      }

      ref.invalidate(documentListProvider);
      state = DocumentImportSucceeded(documentId);

      // The full offline pipeline (extract, then summarize) runs in the
      // background - not awaited, so the user isn't stuck waiting on the
      // Import screen for it to finish.
      unawaited(
        ref.read(processNewDocumentUseCaseProvider)(documentId).then((_) {
          ref.invalidate(documentByIdProvider(documentId));
          ref.invalidate(documentListProvider);
          ref.invalidate(summaryForDocumentProvider(documentId));
        }),
      );
    } on DocumentImportException catch (e) {
      state = DocumentImportFailed(e.message);
    }
  }

  void reset() => state = const DocumentImportIdle();
}

final documentImportControllerProvider =
    NotifierProvider<DocumentImportController, DocumentImportUiState>(
  DocumentImportController.new,
);

/// Shared by every screen with a "Retry" action on [AiPipelineFallback] for
/// a document - mirrors `retryMeetingProcessing`
/// (lib/features/meetings/presentation/providers/pipeline_retry.dart):
/// re-runs the pipeline from wherever it left off, then refreshes every
/// provider a screen might be watching.
Future<void> retryDocumentProcessing(WidgetRef ref, int documentId) async {
  await ref.read(retryDocumentProcessingUseCaseProvider)(documentId);
  ref.invalidate(documentByIdProvider(documentId));
  ref.invalidate(documentListProvider);
  ref.invalidate(summaryForDocumentProvider(documentId));
}
