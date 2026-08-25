import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/toolkit_paths.dart';
import '../ocr/ocr_page_text_layout.dart' show buildInvisibleWordOverlay;
import '../ocr/ocr_text_extraction_service.dart';
import 'pdf_document_builder.dart';
import 'pdf_overlay.dart';
import 'pdf_page_rendering_service.dart';
import 'pdf_redaction.dart';
import 'pdf_searchable_text_preservation.dart';

/// Applies [RedactionRegion]s to specific pages of an existing PDF and
/// rebuilds it as a genuinely sanitized document - the "commit a
/// redaction, produce a real PDF" step for the Redact PDF tool. Structurally
/// mirrors `PdfOverlayService.applyOverlays`'s exact rasterize-then-rebuild
/// loop and `try/finally` temp-file discipline (ADR-032), but is a
/// deliberately **separate class**, not a variant of `PdfOverlayService` -
/// see ADR-040/ADR-041 (`docs/v2/implementation/03-decisions.md`) for why
/// redaction must not reuse the overlay mechanism, and this class's own
/// security argument below for what it does instead.
///
/// **Why this is a real, non-recoverable redaction, not a black box drawn
/// on top:** every page this app's PDF Tools produce (Compress/Merge/
/// Split/Organize/Overlay, and now Redact) is already rasterized to a
/// flat JPEG image with no text or vector layer at all - that has been
/// this app's whole PDF strategy since ADR-034, and is why R-33
/// (`docs/v2/implementation/04-risk-register.md`) already discloses
/// permanent loss of text-selectability for every PDF this app touches.
/// `PdfOverlayService` draws *additional* vector content on top of that
/// still-intact base image - fine for Highlight/Watermark/etc., where the
/// point is to add something visible, but wrong for redaction, since the
/// original image XObject is still embedded underneath and separately
/// extractable. This class instead calls [redactJpegBytes] - which
/// decodes the rasterized JPEG, overwrites the redacted region's pixels
/// with opaque black (a genuine full-channel pixel replacement, see
/// `pdf_redaction.dart`'s own doc comment), and re-encodes - **before**
/// that image is ever embedded as a page. The pixel data selected for
/// redaction is gone from the produced file's own bytes; there is no
/// "underneath" left to recover, because the redacted page's only
/// representation in the output PDF is this already-sanitized image.
///
/// [regionsByPage] is keyed by 0-based page index; a page with no entry
/// (or an empty list) rebuilds with its original rasterized bytes
/// unchanged - this service is a strict superset of the plain rebuild
/// every other PDF Tool already produces for that page, never a second,
/// diverging PDF-writing implementation. The pixel-burn step
/// (decode/fillRect/re-encode) itself only runs for pages that actually
/// have a region, via `compute()` (an isolate) - the same reasoning
/// `pdf_page_rendering_service.dart`'s own JPEG-encode step already uses,
/// since this is pure-Dart CPU work with no reason to block the UI
/// isolate.
class PdfRedactionService {
  /// B3 (release readiness, R-49) - [textPreserver]/[ocrService] restore
  /// approximate searchable text on the rebuilt output, with Permanent
  /// Redaction's own, stricter security rule applied per page:
  ///
  /// - A page with **no** redaction region on it is completely unaffected
  ///   by redaction - its pre-existing text (if any) is safely reused
  ///   verbatim via [textPreserver], identical to every other rasterize-
  ///   and-rebuild PDF Tool (`PdfSearchableTextPreserver`'s own doc
  ///   comment).
  /// - A page **with** at least one redaction region **never** reuses its
  ///   pre-redaction text this way - `PdfTextSearchService` returns flat
  ///   per-page text with no word-level position, so there is no safe way
  ///   to prove which words fall outside the redacted region from that
  ///   source alone. Instead, if [ocrService] is provided (the caller's
  ///   own job to decide - only when a real OCR model is actually
  ///   installed, since this must never force one to download just to
  ///   preserve text), fresh OCR runs **only on that page**, against its
  ///   **pre-redaction** rasterized pixels (never the already-redacted
  ///   ones - a word burned to black pixels first would never be
  ///   recognized at all, silently and unverifiably "safe" for the wrong
  ///   reason). Every recognized word whose bounding box intersects *any*
  ///   redaction region at all, even partially
  ///   ([wordIntersectsRedactionRegion]'s own conservative rule), is
  ///   dropped; only words demonstrably outside every region are kept, as
  ///   a real per-word invisible overlay. If [ocrService] is `null`
  ///   (no model installed), the page's text layer is dropped entirely -
  ///   the safe default this feature's own spec explicitly sanctions
  ///   ("if precise word-level filtering cannot be guaranteed safely,
  ///   remove the OCR text layer from the affected page"). Either way, the
  ///   already-redacted pixels themselves are always used for the embedded
  ///   page image - OCR only ever *reads* the pre-redaction pixels in a
  ///   short-lived temp file to decide what text is safe, it never changes
  ///   what gets embedded.
  ///
  /// This asymmetry (other PDF Tools reuse flat text unconditionally;
  /// Redaction only does on unaffected pages, and uses real per-word OCR
  /// geometry - never flat text - to decide anything about an affected
  /// one) is deliberate: "a false removal is acceptable, a false
  /// preservation of sensitive text is not," this feature's own governing
  /// rule.
  Future<Uint8List> applyRedactions(
    Uint8List sourceBytes, {
    required PdfPageRenderingService renderingService,
    required Map<int, List<RedactionRegion>> regionsByPage,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 90,
    PdfSearchableTextPreserver? textPreserver,
    OcrTextExtractionService? ocrService,
    String ocrLanguage = 'eng',
    // See PdfMergeService.merge's own doc comment on this parameter.
    List<pw.Font> overlayTextFontFallback = const [],
    // See PdfMergeService.merge's own doc comment on this parameter too -
    // **must** be passed identically here and wherever [regionsByPage] was
    // originally captured against a displayed page (the redaction canvas,
    // `pdf_redact_providers.dart`'s own `rasterizePages` call): content-bbox
    // detection is deterministic for the same source bytes/DPI, so the same
    // flag in both places keeps normalized region coordinates aligned with
    // this method's own re-rasterization. A mismatch here would silently
    // redact the wrong area - never change this independently of the
    // canvas's own loading call.
    bool cropToContent = false,
  }) async {
    final tempPaths = <String>[];
    try {
      final existingText = textPreserver == null ? const <int, String>{} : await textPreserver.extractExistingText(sourceBytes);
      final doc = pw.Document();
      await for (final page in renderingService.rasterizePages(
        sourceBytes,
        dpi: dpi,
        jpegQuality: jpegQuality,
        cropToContent: cropToContent,
      )) {
        tempPaths.add(page.tempFilePath);
        final originalJpegBytes = await File(page.tempFilePath).readAsBytes();
        final regions = regionsByPage[page.pageIndex] ?? const [];
        List<PdfOverlayElement> overlay;
        Uint8List pageBytes;
        if (regions.isEmpty) {
          pageBytes = originalJpegBytes;
          overlay = overlayForExistingText(existingText[page.pageIndex], page.width, page.height, dpi);
        } else {
          pageBytes = await compute(
            _redactPage,
            _RedactPageRequest(
              jpegBytes: originalJpegBytes,
              regions: regions,
              width: page.width,
              height: page.height,
              quality: jpegQuality,
            ),
          );
          overlay = await _safeOverlayForRedactedPage(
            originalJpegBytes,
            regions,
            page.width,
            page.height,
            dpi,
            ocrService,
            ocrLanguage,
          );
        }
        addOverlaidImagePageToDocument(
          doc,
          pageBytes,
          page.width,
          page.height,
          dpi,
          overlay,
          textFontFallback: overlayTextFontFallback,
        );
      }
      return doc.save();
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// Never reuses pre-redaction flat text - see this class's own doc
  /// comment for why. Returns an empty overlay (page loses its text layer
  /// entirely) whenever [ocrService] is `null` or OCR itself fails for this
  /// page - both safe defaults, never a thrown exception that would abort
  /// the redaction the user actually asked for.
  Future<List<PdfOverlayElement>> _safeOverlayForRedactedPage(
    Uint8List preRedactionJpegBytes,
    List<RedactionRegion> regions,
    int width,
    int height,
    double dpi,
    OcrTextExtractionService? ocrService,
    String ocrLanguage,
  ) async {
    if (ocrService == null) return const [];
    final tempPath = await newToolkitTempFilePath('jpg');
    try {
      await File(tempPath).writeAsBytes(preRedactionJpegBytes);
      final words = await ocrService.extractWords(tempPath, language: ocrLanguage);
      final safeWords = words
          .where((word) => !regions.any((region) => wordIntersectsRedactionRegion(word, region, width, height)))
          .toList();
      return buildInvisibleWordOverlay(safeWords, width, height, dpi);
    } catch (_) {
      return const [];
    } finally {
      final file = File(tempPath);
      if (await file.exists()) await file.delete();
    }
  }
}

class _RedactPageRequest {
  const _RedactPageRequest({
    required this.jpegBytes,
    required this.regions,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List jpegBytes;
  final List<RedactionRegion> regions;
  final int width;
  final int height;
  final int quality;
}

Uint8List _redactPage(_RedactPageRequest request) {
  return redactJpegBytes(request.jpegBytes, request.regions, request.width, request.height, quality: request.quality);
}
