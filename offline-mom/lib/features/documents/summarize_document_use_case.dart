import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../models/document.dart';
import '../../models/summary.dart';
import '../../repositories/document_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../services/ai/chunked_summarization_service.dart';

const _log = AppLogger('SummarizeDocumentUseCase');

/// Orchestrates generating a document's AI summary - deliberately as close
/// to a line-for-line mirror of `GenerateMeetingSummaryUseCase`
/// (lib/features/ai_summary/generate_meeting_summary_use_case.dart) as the
/// two entities' different repositories/status enums allow, per this
/// milestone's "reuse the existing LLM engine/prompt builder/queue, don't
/// duplicate AI orchestration" requirement: [ChunkedSummarizationService]
/// (M2.4) is used exactly the same way for a document's extracted text as
/// for a meeting's transcript (it has no meeting-specific behavior - it
/// summarizes whatever text string it's given, chunking/reducing only if
/// that text is long enough to need it), through the same shared
/// [LlmRequestQueue] underneath, writing into the same shared `summaries`
/// table via [Summary.documentId] (ADR-005,
/// docs/v2/implementation/03-decisions.md) instead of a parallel
/// table/use-case-family.
///
/// Kept as a separate class rather than factored into one generic
/// "summarize an entity" helper shared with meetings: the two pipelines
/// differ in their repository type and status enum, and a shared
/// abstraction general enough to cover both would need more
/// parameterization than the ~30 lines of duplication it would save are
/// worth - the actual AI call, the genuinely reusable part, is already
/// 100% shared via [ChunkedSummarizationService]/[SummaryRepository].
class SummarizeDocumentUseCase {
  SummarizeDocumentUseCase({
    required DocumentRepository documentRepository,
    required SummaryRepository summaryRepository,
    required ChunkedSummarizationService chunkedSummarizationService,
  })  : _documentRepository = documentRepository,
        _summaryRepository = summaryRepository,
        _chunkedSummarizationService = chunkedSummarizationService;

  final DocumentRepository _documentRepository;
  final SummaryRepository _summaryRepository;
  final ChunkedSummarizationService _chunkedSummarizationService;

  Future<void> call(int documentId) async {
    final document = await _documentRepository.getById(documentId);
    if (document == null) return;

    final text = document.extractedText;
    if (text == null || text.trim().isEmpty) return;

    try {
      final result = await _chunkedSummarizationService.summarize(
        text,
        onPreparingModel: () {
          // Fire-and-forget: this is a status update for the UI,
          // not something summary generation needs to wait on -
          // same pattern as GenerateMeetingSummaryUseCase.
          unawaited(
            _documentRepository.update(
              document.copyWith(
                status: DocumentStatus.downloadingSummaryModel,
                updatedAt: DateTime.now(),
              ),
            ),
          );
        },
      );

      await _summaryRepository.insert(
        Summary(
          id: null,
          documentId: documentId,
          summaryText: result.summaryText,
          minutesOfMeeting: result.minutesOfMeeting,
          keyTopics: result.keyTopics,
          modelUsed: result.modelUsed,
          generatedAt: DateTime.now(),
        ),
      );

      await _documentRepository.update(
        document.copyWith(
          status: DocumentStatus.ready,
          updatedAt: DateTime.now(),
          errorMessage: null,
        ),
      );
    } catch (e, stackTrace) {
      await _documentRepository.update(
        document.copyWith(
          status: DocumentStatus.error,
          updatedAt: DateTime.now(),
          errorMessage: 'AI summary failed: $e',
        ),
      );
      _log.error('Summary failed for document $documentId', error: e, stackTrace: stackTrace);
    }
  }
}
