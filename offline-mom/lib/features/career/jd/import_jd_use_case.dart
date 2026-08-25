import '../../../models/document.dart';
import '../../../models/job_description.dart';
import '../../../services/career/jd_parser.dart';
import '../../../services/documents/document_text_extraction_service.dart';

/// Thrown when the extraction step cannot produce usable text for JD
/// import - mirrors `ResumeImportExtractionException`'s exact purpose
/// (lib/features/career/resume/import_resume_use_case.dart).
class JdImportExtractionException implements Exception {
  JdImportExtractionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Extracts and structures a picked JD file - mirrors
/// `ImportResumeUseCase.extractAndParse`'s exact shape and reasoning
/// (lib/features/career/resume/import_resume_use_case.dart), reusing the
/// same, unmodified `DocumentTextExtractionService` implementations/DI map
/// the Documents feature and Batch 7 already register.
///
/// Deliberately has no `confirmImport`/persistence counterpart - a
/// [ParsedJobDescription] is never written to the database in Batch 8 (see
/// the Batch 8 report for why); the caller holds the returned draft
/// in-memory for the lifetime of one analysis session.
class ImportJdUseCase {
  ImportJdUseCase({
    required Map<DocumentSourceType, DocumentTextExtractionService> extractors,
    required JdParser parser,
  })  : _extractors = extractors,
        _parser = parser;

  final Map<DocumentSourceType, DocumentTextExtractionService> _extractors;
  final JdParser _parser;

  /// Throws [JdImportExtractionException] if nothing readable was found;
  /// lets the extractor's own typed read-failure exception
  /// (`PdfReadException`/`DocxReadException`) propagate unchanged.
  Future<ParsedJobDescription> extractAndParse(String filePath, DocumentSourceType sourceType) async {
    final extractor = _extractors[sourceType];
    if (extractor == null) {
      throw JdImportExtractionException(
        'Importing .${sourceType.name} files is not supported.',
      );
    }

    final text = await extractor.extractText(filePath);
    if (text == null) {
      throw JdImportExtractionException(
        sourceType == DocumentSourceType.pdf
            ? 'This PDF has no extractable text - it may be a scanned or '
                'image-only document. Scanned-document import is not '
                'supported yet.'
            : 'No readable text was found in this file.',
      );
    }

    return _parser.parse(text);
  }
}
