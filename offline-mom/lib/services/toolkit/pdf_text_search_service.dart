import 'package:flutter/services.dart' show PlatformException;
import 'package:read_pdf_text/read_pdf_text.dart';

/// Thrown when a PDF's text genuinely couldn't be read at all (corrupted,
/// password-protected, or not a valid PDF) - distinct from a successful
/// extraction returning only empty/whitespace pages, which means "read
/// fine, no text layer found" (a scanned/image-only PDF) rather than a
/// failure. Mirrors `PdfReadException`'s exact same distinction in
/// `lib/services/documents/parsers/pdf_parser.dart` - this is a
/// Toolkit-scoped equivalent, not a duplicate of that one, since Documents'
/// `PdfParser` returns one flat whole-document string (for RAG/embedding)
/// while PDF Search needs per-page text (to report *which* page a match is
/// on) - `read_pdf_text` exposes both as separate native calls.
class PdfTextSearchException implements Exception {
  const PdfTextSearchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Extracts a PDF's text, one page at a time, for the Student Toolkit's PDF
/// Search (P0-6) - a real, page-indexed extraction, not OCR. For a
/// scanned/image-only PDF (no embedded text layer), every page's extracted
/// string is empty - this is a correct, honest "no searchable text found"
/// result, not a failure (ADR-015: OCR is explicitly out of scope; this
/// service never attempts to read pixels as text).
abstract class PdfTextSearchService {
  /// Returns one string per page, in page order (`result[i]` is page `i`'s
  /// text, empty if that page has no extractable text layer).
  Future<List<String>> extractPagesText(String pdfFilePath);
}

/// Backed by `read_pdf_text`'s `getPDFtextPaginated` (already a pinned
/// dependency, used elsewhere in this app by Documents' `PdfParser` for its
/// own whole-document `getPDFtext` call) - confirmed by reading the
/// package's own Android plugin source directly
/// (`ReadPdfTextPlugin.java`) that `getPDFtextPaginated` is a real, natively
/// implemented method, not a Dart-only stub.
class ReadPdfTextSearchService implements PdfTextSearchService {
  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async {
    try {
      return await ReadPdfText.getPDFtextPaginated(pdfFilePath);
    } on PlatformException catch (e) {
      throw PdfTextSearchException(
        'This PDF could not be read (it may be corrupted or '
        'password-protected)${e.message != null ? ': ${e.message}' : '.'}',
      );
    }
  }
}

/// A fake for controller tests - `read_pdf_text` is a real native plugin
/// with no implementation under `flutter test`, the same standing
/// limitation as `Printing.raster()` (R-32) - mirrors
/// `FakeToolkitImagePickerService`'s existing precedent of shipping the
/// fake alongside the interface it implements.
class FakePdfTextSearchService implements PdfTextSearchService {
  FakePdfTextSearchService({this.pagesByPath = const {}, this.throwForPath});

  Map<String, List<String>> pagesByPath;
  String? throwForPath;

  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async {
    if (throwForPath == pdfFilePath) {
      throw const PdfTextSearchException('This PDF could not be read.');
    }
    return pagesByPath[pdfFilePath] ?? const [];
  }
}
