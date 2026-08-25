import '../../core/knowledge/content_type.dart';
import '../../core/logging/app_logger.dart';
import '../../models/document.dart';
import '../../repositories/document_repository.dart';
import '../../services/retrieval/indexing_service.dart';

const _log = AppLogger('DocumentIndexer');

/// Drives a document through [DocumentStatus.indexing] - the background
/// step that chunks and embeds a document's already-extracted text via
/// [IndexingService] (services/retrieval/indexing_service.dart), per FR-40
/// and Milestone M1.2 (docs/v2/implementation/01-master-roadmap.md).
///
/// Runs *after* [SummarizeDocumentUseCase] has already moved a document to
/// [DocumentStatus.ready] - deliberately not folded into that use case, so
/// its existing, already-shipped-and-tested contract (Phase 1A) is
/// untouched. A document that goes through both therefore visits `ready`
/// twice in quick succession (once from summarization, once - the final,
/// durable one - from this indexer); nothing reads or renders that
/// transient intermediate state in this milestone (no chat/UI depends on
/// indexing yet), so this is safe. [ProcessNewDocumentUseCase]/
/// [RetryDocumentProcessingUseCase] call this as an explicit extra step
/// after summarization succeeds, the same "run stage N, check the
/// resulting status, then run stage N+1" shape those use cases already
/// use between extraction and summarization.
class DocumentIndexer {
  DocumentIndexer({
    required DocumentRepository documentRepository,
    required IndexingService indexingService,
  })  : _documentRepository = documentRepository,
        _indexingService = indexingService;

  final DocumentRepository _documentRepository;
  final IndexingService _indexingService;

  Future<void> call(int documentId) async {
    final document = await _documentRepository.getById(documentId);
    if (document == null) return;

    final text = document.extractedText;
    if (text == null || text.trim().isEmpty) return;

    await _documentRepository.update(
      document.copyWith(status: DocumentStatus.indexing, updatedAt: DateTime.now()),
    );

    try {
      await _indexingService.indexContent(
        contentType: ContentType.document,
        sourceId: documentId,
        documentId: documentId,
        text: text,
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
          errorMessage: 'Indexing failed: $e',
        ),
      );
      _log.error('Indexing failed for document $documentId', error: e, stackTrace: stackTrace);
    }
  }
}
