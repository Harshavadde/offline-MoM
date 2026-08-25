import 'package:flutter/services.dart' show PlatformException;
import 'package:read_pdf_text/read_pdf_text.dart';

import '../../../models/document.dart';
import '../document_text_extraction_service.dart';

/// Thrown when the PDF itself couldn't be read at all (corrupted,
/// password-protected, or not a valid PDF) - distinct from
/// [DocumentTextExtractionService.extractText] returning null, which means
/// "read fine, but no text layer found" (e.g. a scanned/image-only PDF).
/// Callers (`ExtractDocumentTextUseCase`) use this distinction to show a
/// more specific error message than a generic extraction failure.
class PdfReadException implements Exception {
  PdfReadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backed by `read_pdf_text` (MIT, wraps the Android "PDFBox-Android" port
/// and iOS's own PDFKit natively - no mature, permissively-licensed
/// pure-Dart PDF parser exists, so a native wrapper is the only realistic
/// option; see ADR-016, docs/v2/implementation/03-decisions.md, for the
/// license-audit trail).
class PdfParser implements DocumentTextExtractionService {
  @override
  DocumentSourceType get supportedSourceType => DocumentSourceType.pdf;

  @override
  Future<String?> extractText(String filePath) async {
    final String raw;
    try {
      raw = await ReadPdfText.getPDFtext(filePath);
    } on PlatformException catch (e) {
      // The package's own docs don't enumerate specific failure reasons
      // (missing file, corrupted PDF, password-protected) - every
      // PlatformException from it means "this PDF could not be read," so
      // that's the one thing surfaced here rather than guessing at a more
      // specific cause than the package itself distinguishes.
      throw PdfReadException(
        'This PDF could not be read (it may be corrupted or '
        'password-protected)${e.message != null ? ': ${e.message}' : '.'}',
      );
    }

    final trimmed = raw.trim();
    // A scanned/image-only PDF reads successfully but yields nothing - per
    // ADR-015 (docs/v2/implementation/03-decisions.md), OCR is out of
    // scope, so this surfaces as "no text found," not a crash or an
    // empty-but-"ready" document.
    return trimmed.isEmpty ? null : trimmed;
  }
}
