import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'package:pdf/pdf.dart' show PdfPageRotation;

import '../../core/utils/toolkit_paths.dart';
import '../toolkit/pdf_document_builder.dart';
import '../toolkit/pdf_overlay.dart' show PdfOverlayElement;
import '../toolkit/pdf_page_rendering_service.dart' show kPdfOutputDpi;
import 'ocr_page_text_layout.dart';
import 'ocr_text_extraction_service.dart';

/// One page to run through the searchable-PDF pipeline - the unified input
/// shape every P0-7 entry point (Scanner, Images to PDF, an existing PDF
/// picked in View PDF) converts its own source into before reaching
/// [SearchablePdfBuilderService], mirroring [PdfPageInput]'s identical role
/// for P0-5's plain page-composition pipeline.
class OcrSourcePage {
  const OcrSourcePage({
    required this.jpegBytes,
    required this.width,
    required this.height,
    this.existingText,
    this.rotation = PdfPageRotation.none,
  });

  final Uint8List jpegBytes;
  final int width;
  final int height;

  /// Real PDF `/Rotate` presentation rotation (P0-5's mechanism,
  /// `PdfPageInput.rotation`'s own doc comment) - applied to the whole
  /// page (image and invisible text layer together) after it's built, so
  /// a page rotated before OCR (e.g. Images to PDF's rotate action) stays
  /// correctly oriented, and the OCR word boxes - measured against the
  /// image's own un-rotated pixels - remain correctly aligned, since
  /// `/Rotate` rotates the whole page presentation uniformly rather than
  /// moving content within it.
  final PdfPageRotation rotation;

  /// Real, already-extracted text for this page (from
  /// `PdfTextSearchService`, P0-6) if it existed *before* this document was
  /// rasterized - a non-null, non-blank value means "reuse this, don't run
  /// OCR on this page" (scenario 26). `null`/blank means "no known existing
  /// text, run OCR."
  final String? existingText;
}

class SearchablePdfBuilderException implements Exception {
  const SearchablePdfBuilderException(this.message, {this.wasCancelled = false});
  final String message;

  /// True when this represents a user-requested cancellation, not a real
  /// failure - mirrors [ModelDownloadException.wasCancelled]'s identical
  /// distinction, for the same reason: the caller decides whether to show
  /// an error banner or a quiet "cancelled" state.
  final bool wasCancelled;

  @override
  String toString() => message;
}

/// Builds a real, searchable PDF from an ordered list of page images -
/// P0-7's central pipeline, reused by every "make this searchable" entry
/// point (Scan → Searchable PDF, Images → Searchable PDF, an existing
/// PDF's "Run OCR"). For each page: either reuse already-known real text
/// (no OCR call - scenario 26) or run offline OCR via
/// [OcrTextExtractionService] and place the recognized words as a real,
/// invisible, per-word-positioned PDF text layer
/// (`ocr_page_text_layout.dart`) on top of the same rasterized page image
/// every other PDF Tool already draws - the page's *visual* appearance is
/// never touched (`addOverlaidImagePageToDocument`, the exact primitive
/// P0-3's Add Text/Signatures/Watermark already share), only made
/// searchable underneath it. Streams one page's temp JPEG file into OCR at
/// a time (never holds more than one page's working file on disk at once),
/// and never calls `doc.save()` until every page has succeeded - a
/// cancellation or failure partway through therefore can never produce a
/// truncated or corrupt output PDF; nothing is written until the whole
/// document is ready.
class SearchablePdfBuilderService {
  SearchablePdfBuilderService({required OcrTextExtractionService ocrService}) : _ocrService = ocrService;

  final OcrTextExtractionService _ocrService;

  /// [onProgress] reports pages completed so far (1-based) out of the
  /// total, called once per page immediately after that page is fully
  /// placed into the document - genuine per-page progress, never simulated
  /// (Phase 3's "do not fake progress" requirement). [isCancelled] is
  /// polled once per page, before starting that page's work - cooperative
  /// cancellation, the same shape `PdfToImagesController.exportSelected`
  /// already established (P0-6): a page whose OCR call is already in
  /// flight still completes before the next check, a disclosed limitation
  /// shared with that controller.
  Future<Uint8List> build(
    List<OcrSourcePage> pages, {
    required String language,
    double dpi = kPdfOutputDpi,
    void Function(int pagesDone, int pagesTotal)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (pages.isEmpty) {
      throw const SearchablePdfBuilderException('Add at least one page before generating a searchable PDF.');
    }
    final doc = pw.Document();
    for (var i = 0; i < pages.length; i++) {
      if (isCancelled?.call() ?? false) {
        throw const SearchablePdfBuilderException('Cancelled.', wasCancelled: true);
      }
      final page = pages[i];
      final overlay = await _overlayFor(page, language, dpi);
      addOverlaidImagePageToDocument(doc, page.jpegBytes, page.width, page.height, dpi, overlay);
      if (page.rotation != PdfPageRotation.none) {
        doc.document.pdfPageList.pages.last.rotate = page.rotation;
      }
      onProgress?.call(i + 1, pages.length);
    }
    return doc.save();
  }

  Future<List<PdfOverlayElement>> _overlayFor(OcrSourcePage page, String language, double dpi) async {
    final existing = page.existingText;
    if (existing != null && existing.trim().isNotEmpty) {
      return buildEvenlySpacedLineOverlay(existing, page.width, page.height, dpi);
    }

    final tempPath = await newToolkitTempFilePath('jpg');
    try {
      await File(tempPath).writeAsBytes(page.jpegBytes);
      final words = await _ocrService.extractWords(tempPath, language: language);
      return buildInvisibleWordOverlay(words, page.width, page.height, dpi);
    } on OcrExtractionException catch (e) {
      throw SearchablePdfBuilderException(e.message);
    } finally {
      final file = File(tempPath);
      if (await file.exists()) await file.delete();
    }
  }
}
