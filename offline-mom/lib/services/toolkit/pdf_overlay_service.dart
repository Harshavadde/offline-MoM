import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'pdf_document_builder.dart';
import 'pdf_overlay.dart';
import 'pdf_page_rendering_service.dart';
import 'pdf_searchable_text_preservation.dart';

/// Applies [PdfOverlayElement]s to specific pages of an existing PDF and
/// rebuilds it - the shared "commit an overlay, produce a real PDF" step
/// every overlay-based PDF Tool (Add Text, Signatures, Highlight/
/// Underline/Strikethrough/Freehand/Shapes, Watermark) reuses, per the
/// Productivity Toolkit productization audit's own recommendation (see
/// `pdf_overlay.dart`'s doc comment for the full rationale). Mirrors
/// `PdfCompressionService`'s exact rasterize-then-rebuild loop structure
/// and its same `try/finally` temp-file discipline (ADR-032).
///
/// [overlaysByPage] is keyed by 0-based page index; a page with no entry
/// (or an empty list) rebuilds unchanged, byte-identical to what
/// `PdfCompressionService`/`PdfMergeService`/etc. would already produce
/// for that page - this service is a strict superset of the plain
/// rebuild, never a second, diverging PDF-writing implementation.
///
/// Inherits the same disclosed tradeoff every PDF Tool already carries
/// (R-33, `docs/v2/implementation/04-risk-register.md`): even a page with
/// no overlay at all still passes through rasterize-and-JPEG-re-encode,
/// since that's this app's whole PDF-manipulation strategy (ADR-034) -
/// [jpegQuality] defaults higher than `PdfCompressionService`'s own
/// (90 vs. 80) since overlay operations aren't *intended* to compress,
/// but some re-encode loss is unavoidable here, not eliminable without a
/// different PDF stack entirely.
class PdfOverlayService {
  Future<Uint8List> applyOverlays(
    Uint8List sourceBytes, {
    required PdfPageRenderingService renderingService,
    required Map<int, List<PdfOverlayElement>> overlaysByPage,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 90,
    PdfSearchableTextPreserver? textPreserver,
    // See PdfMergeService.merge's own doc comment on this parameter. Only
    // ever applies to the reconstructed searchable-text portion of
    // [overlay] below - the user's own visible annotations
    // ([overlaysByPage]) already carry whatever font they need and are
    // unaffected.
    List<pw.Font> overlayTextFontFallback = const [],
    // See PdfMergeService.merge's own doc comment. **Must** match whatever
    // was passed wherever [overlaysByPage]'s regions were originally
    // captured against a displayed page (the edit canvas,
    // `pdf_edit_providers.dart`'s own `rasterizePages` call) - a mismatch
    // would silently misplace the user's own annotations. Same reasoning
    // as `PdfRedactionService.applyRedactions`'s identical parameter.
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
        final jpegBytes = await File(page.tempFilePath).readAsBytes();
        // Reconstructed searchable text goes first (invisible - draws
        // nothing), the user's own visible annotations after, so an
        // annotation is never accidentally hidden behind anything.
        final overlay = <PdfOverlayElement>[
          ...overlayForExistingText(existingText[page.pageIndex], page.width, page.height, dpi),
          ...overlaysByPage[page.pageIndex] ?? const [],
        ];
        addOverlaidImagePageToDocument(
          doc,
          jpegBytes,
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
}
