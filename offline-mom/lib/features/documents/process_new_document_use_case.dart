import '../../models/document.dart';
import '../../repositories/document_repository.dart';
import 'document_indexer.dart';
import 'extract_document_text_use_case.dart';
import 'summarize_document_use_case.dart';

/// Runs the full offline pipeline for a newly imported document: extract
/// text, summarize (only if extraction actually succeeded), then index for
/// retrieval (only if summarization actually succeeded) - the same "run
/// stage N, check the resulting status before running stage N+1" shape
/// `ProcessNewMeetingUseCase` uses
/// (lib/features/meetings/process_new_meeting_use_case.dart), now three
/// stages deep instead of two (M1.2, docs/v2/implementation/01-master-roadmap.md).
class ProcessNewDocumentUseCase {
  ProcessNewDocumentUseCase({
    required DocumentRepository documentRepository,
    required ExtractDocumentTextUseCase extractDocumentTextUseCase,
    required SummarizeDocumentUseCase summarizeDocumentUseCase,
    required DocumentIndexer documentIndexer,
  })  : _documentRepository = documentRepository,
        _extractDocumentTextUseCase = extractDocumentTextUseCase,
        _summarizeDocumentUseCase = summarizeDocumentUseCase,
        _documentIndexer = documentIndexer;

  final DocumentRepository _documentRepository;
  final ExtractDocumentTextUseCase _extractDocumentTextUseCase;
  final SummarizeDocumentUseCase _summarizeDocumentUseCase;
  final DocumentIndexer _documentIndexer;

  Future<void> call(int documentId) async {
    await _extractDocumentTextUseCase(documentId);

    final extracted = await _documentRepository.getById(documentId);
    if (extracted?.status != DocumentStatus.summarizing) return;

    await _summarizeDocumentUseCase(documentId);

    final summarized = await _documentRepository.getById(documentId);
    if (summarized?.status != DocumentStatus.ready) return;

    await _documentIndexer(documentId);
  }
}
