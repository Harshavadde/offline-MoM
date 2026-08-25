import '../../models/document.dart';
import '../../repositories/document_repository.dart';
import '../../repositories/summary_repository.dart';
import 'document_indexer.dart';
import 'extract_document_text_use_case.dart';
import 'summarize_document_use_case.dart';

/// Retries a failed document from wherever the pipeline actually left off -
/// mirrors `RetryMeetingProcessingUseCase`
/// (lib/features/meetings/retry_meeting_processing_use_case.dart): each
/// stage is skipped if its own output already exists, so a retry never
/// redoes already-successful work. This matters more than it did in
/// Phase 1A now that a third stage exists (M1.2,
/// docs/v2/implementation/01-master-roadmap.md): a document can reach
/// `error` from a failed *indexing* step with both its text already
/// extracted **and** a summary already persisted - blindly re-running
/// [SummarizeDocumentUseCase] in that case (as a naive two-stage
/// "extractedText is null?" check alone would) would silently insert a
/// second, orphaned summary row for the same document (wasting an LLM
/// call, since [SummarizeDocumentUseCase] has no existing-summary guard
/// of its own) - so this checks [SummaryRepository.getForDocument]
/// explicitly rather than inferring "was this stage already done?" from
/// [Document.extractedText] alone.
class RetryDocumentProcessingUseCase {
  RetryDocumentProcessingUseCase({
    required DocumentRepository documentRepository,
    required SummaryRepository summaryRepository,
    required ExtractDocumentTextUseCase extractDocumentTextUseCase,
    required SummarizeDocumentUseCase summarizeDocumentUseCase,
    required DocumentIndexer documentIndexer,
  })  : _documentRepository = documentRepository,
        _summaryRepository = summaryRepository,
        _extractDocumentTextUseCase = extractDocumentTextUseCase,
        _summarizeDocumentUseCase = summarizeDocumentUseCase,
        _documentIndexer = documentIndexer;

  final DocumentRepository _documentRepository;
  final SummaryRepository _summaryRepository;
  final ExtractDocumentTextUseCase _extractDocumentTextUseCase;
  final SummarizeDocumentUseCase _summarizeDocumentUseCase;
  final DocumentIndexer _documentIndexer;

  Future<void> call(int documentId) async {
    var document = await _documentRepository.getById(documentId);
    if (document == null) return;

    if (document.extractedText == null) {
      await _extractDocumentTextUseCase(documentId);
      document = await _documentRepository.getById(documentId);
      if (document?.extractedText == null) return;
    }

    if (await _summaryRepository.getForDocument(documentId) == null) {
      await _summarizeDocumentUseCase(documentId);
      final summarized = await _documentRepository.getById(documentId);
      if (summarized?.status != DocumentStatus.ready) return;
    }

    await _documentIndexer(documentId);
  }
}
