import '../../core/logging/app_logger.dart';
import '../../models/document.dart';
import '../../repositories/document_repository.dart';
import '../../services/documents/document_text_extraction_service.dart';

const _log = AppLogger('ExtractDocumentTextUseCase');

/// Orchestrates turning a document's file into stored extracted text -
/// mirrors `TranscribeMeetingUseCase`'s shape exactly (mark as in-progress,
/// run the format-appropriate parser, persist the result, advance to the
/// next stage or mark failed), crossing one repository and one service so,
/// per the architecture notes, it earns a dedicated use case.
class ExtractDocumentTextUseCase {
  ExtractDocumentTextUseCase({
    required DocumentRepository documentRepository,
    required Map<DocumentSourceType, DocumentTextExtractionService> extractors,
  })  : _documentRepository = documentRepository,
        _extractors = extractors;

  final DocumentRepository _documentRepository;

  /// One parser per format (services/documents/parsers/), keyed by the
  /// format it handles - avoids a composite dispatcher class for what's
  /// otherwise a one-line lookup.
  final Map<DocumentSourceType, DocumentTextExtractionService> _extractors;

  Future<void> call(int documentId) async {
    final document = await _documentRepository.getById(documentId);
    if (document == null) return;

    await _documentRepository.update(
      document.copyWith(
        status: DocumentStatus.extracting,
        updatedAt: DateTime.now(),
        errorMessage: null,
      ),
    );

    final extractor = _extractors[document.sourceType];
    if (extractor == null) {
      // Can't happen with the current fixed set of DocumentSourceType
      // values and the DI wiring in app_providers.dart, which registers
      // one extractor per value - guarded anyway so a future format added
      // to the enum without a matching extractor fails loudly and
      // diagnosably instead of throwing a raw "null check" error.
      await _documentRepository.update(
        document.copyWith(
          status: DocumentStatus.error,
          updatedAt: DateTime.now(),
          errorMessage: 'No text extractor is registered for '
              '${document.sourceType.name} files.',
        ),
      );
      return;
    }

    try {
      final text = await extractor.extractText(document.filePath);
      if (text == null) {
        await _documentRepository.update(
          document.copyWith(
            status: DocumentStatus.error,
            updatedAt: DateTime.now(),
            errorMessage: 'No readable text was found in this file '
                '(scanned/image-only PDFs aren\'t supported yet).',
          ),
        );
        return;
      }

      // Next pipeline stage is AI summarization, same as a meeting sits in
      // `summarizing` until GenerateMeetingSummaryUseCase picks it up.
      await _documentRepository.update(
        document.copyWith(
          status: DocumentStatus.summarizing,
          updatedAt: DateTime.now(),
          extractedText: text,
        ),
      );
    } catch (e, stackTrace) {
      await _documentRepository.update(
        document.copyWith(
          status: DocumentStatus.error,
          updatedAt: DateTime.now(),
          errorMessage: 'Text extraction failed: $e',
        ),
      );
      _log.error('Extraction failed for document $documentId', error: e, stackTrace: stackTrace);
    }
  }
}
