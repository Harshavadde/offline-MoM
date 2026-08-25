import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_document_builder.dart';
import 'pdf_overlay.dart';
import 'pdf_page_rendering_service.dart' show kPdfOutputDpi;

/// One already-rasterized page to place in an output document, plus its
/// intended rotation - the shared "list of pages -> real PDF" primitive
/// behind every Page Management operation (Rotate/Delete/Extract/Insert/
/// Duplicate/Replace/Reorder, Productivity Toolkit productization pass,
/// P0-5, ADR-043). Deliberately does not rasterize anything itself - the
/// caller (`PdfOrganizeService`, `PdfOrganizeController`) already holds
/// rasterized bytes by the time it needs to build/rebuild a document, so
/// this stays a pure "compose these pages into a document" step, matching
/// `pdf_document_builder.dart`'s own precedent of small, focused,
/// synchronous-shaped helpers.
class PdfPageInput {
  const PdfPageInput({
    required this.jpegBytes,
    required this.width,
    required this.height,
    this.rotation = PdfPageRotation.none,
    this.overlayElements = const [],
  });

  final Uint8List jpegBytes;
  final int width;
  final int height;

  /// B3 (release readiness, R-49) - a reconstructed searchable-text overlay
  /// (or any other overlay content) to draw on this page, via the exact
  /// same [addOverlaidImagePageToDocument] primitive P0-3/P0-7 already
  /// share. Defaults to empty, which [PdfPageComposerService.compose]
  /// composes identically to a plain, non-overlaid page (see
  /// `pdf_overlay.dart`'s own doc comment) - every existing caller that
  /// never sets this field is completely unaffected.
  final List<PdfOverlayElement> overlayElements;

  /// Sets the real PDF page `/Rotate` dictionary entry (`PdfPage.rotate`,
  /// `package:pdf`) rather than rotating the pixel data - a genuine,
  /// standards-compliant, zero-recompute rotation every PDF viewer honors
  /// on display, confirmed by reading `pdf/obj/page.dart` directly
  /// (`params['/Rotate'] = PdfNum(rotate.index * 90)`). No re-rasterization,
  /// no re-encode, no quality loss - the image's own pixel data is
  /// untouched; only the page's presentation is rotated. See ADR-043 for
  /// why this is preferred over rotating the bitmap itself.
  final PdfPageRotation rotation;
}

class PdfPageComposerException implements Exception {
  const PdfPageComposerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Builds a real PDF from an ordered list of already-rasterized pages -
/// the one shared page-building step every Page Management operation
/// reduces to, once the caller has decided which pages (from which
/// sources), in which order, with which rotation, belong in the output.
/// Rotate/Delete/Duplicate/Extract/Reorder are all just different
/// [pages] lists into this same function; Insert/Replace additionally mix
/// in pages rasterized from a different source PDF/image - this service
/// itself doesn't need to know or care which case it's in.
class PdfPageComposerService {
  Future<Uint8List> compose(
    List<PdfPageInput> pages, {
    double dpi = kPdfOutputDpi,
    // See PdfMergeService.merge's own doc comment on this parameter - the
    // one shared choke point every Page Management operation composes
    // through, so wiring it in here covers Rotate/Delete/Duplicate/
    // Extract/Reorder/Insert/Replace uniformly.
    List<pw.Font> overlayTextFontFallback = const [],
  }) async {
    if (pages.isEmpty) {
      throw const PdfPageComposerException('Keep at least one page.');
    }
    final doc = pw.Document();
    for (final page in pages) {
      addOverlaidImagePageToDocument(
        doc,
        page.jpegBytes,
        page.width,
        page.height,
        dpi,
        page.overlayElements,
        textFontFallback: overlayTextFontFallback,
      );
      if (page.rotation != PdfPageRotation.none) {
        // Set immediately after adding this page (not in a second pass by
        // index afterward) so there's no risk of an index mismatch if
        // `pw.Document`'s internal page list is ever built any other way
        // than strictly append-in-order.
        doc.document.pdfPageList.pages.last.rotate = page.rotation;
      }
    }
    return doc.save();
  }
}
