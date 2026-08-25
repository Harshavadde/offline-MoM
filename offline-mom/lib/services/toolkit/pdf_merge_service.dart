import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import 'image_compression_service.dart' show decodeToolkitImageOrThrow, ImageCompressionException;
import 'pdf_document_builder.dart';
import 'pdf_page_rendering_service.dart';
import 'pdf_searchable_text_preservation.dart';

/// One source item to merge - either an existing PDF (rasterized page by
/// page) or a single image (treated as one page) - "combine a mix of PDFs
/// and images into one" is exactly what the product brief's "Merge" asks
/// for.
class PdfMergeInput {
  const PdfMergeInput.pdf(this.bytes) : isPdf = true;
  const PdfMergeInput.image(this.bytes) : isPdf = false;

  final Uint8List bytes;
  final bool isPdf;
}

class PdfMergeResult {
  const PdfMergeResult({required this.bytes, required this.pageCount});
  final Uint8List bytes;
  final int pageCount;
}

class PdfMergeException implements Exception {
  const PdfMergeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Merges [inputs], in order, into one new PDF - every PDF input's pages
/// are rasterized (see ADR-034) and every image input becomes one page,
/// all at a consistent [dpi] so the merged document doesn't visibly jump
/// in resolution between sources.
class PdfMergeService {
  Future<PdfMergeResult> merge(
    List<PdfMergeInput> inputs, {
    required PdfPageRenderingService renderingService,
    double dpi = kPdfOutputDpi,
    int imageJpegQuality = 90,
    PdfSearchableTextPreserver? textPreserver,
    // A broader-Unicode-coverage font (e.g. this app's own bundled Inter,
    // loaded once by the caller - see `pdfMergeControllerProvider`) used
    // only as a *fallback* for the invisible search-text layer below when
    // the base Helvetica font can't represent a character (a bullet/arrow
    // glyph, most commonly) - see `pdf_overlay.dart`'s own doc comment on
    // why that previously showed as a visible box despite the text being
    // invisible. Deliberately not loaded internally: this class stays
    // Flutter-binding-free (no `rootBundle`), matching every existing
    // caller/test of `merge()` that constructs it with plain `dart:io`
    // dependencies only. Empty by default - existing behavior for any
    // caller that doesn't pass one.
    List<pw.Font> overlayTextFontFallback = const [],
    // Crops each source page down to its own content instead of the
    // source's full physical page size - see [detectContentBounds]
    // (pdf_page_rendering_service.dart) and `docs/architecture/hld.md` for
    // why this is a deliberate, requested behavior for Merge specifically
    // (a real, disclosed content characteristic of some source PDFs, not a
    // rendering defect). Off by default - `pdfMergeControllerProvider` is
    // the one real caller that turns it on.
    bool cropToContent = false,
  }) async {
    if (inputs.length < 2) {
      throw const PdfMergeException('Add at least two files to merge.');
    }
    final tempPaths = <String>[];
    try {
      final doc = pw.Document();
      var pageCount = 0;
      for (final input in inputs) {
        if (input.isPdf) {
          // Extracted per source PDF, not once for the whole merge - each
          // input has its own independent 0-based page-index space that a
          // single merged-output map could not distinguish between inputs.
          final existingText =
              textPreserver == null ? const <int, String>{} : await textPreserver.extractExistingText(input.bytes);
          await for (final page
              in renderingService.rasterizePages(input.bytes, dpi: dpi, cropToContent: cropToContent)) {
            tempPaths.add(page.tempFilePath);
            final jpegBytes = await File(page.tempFilePath).readAsBytes();
            // The renderer producing a near-blank page for a source page
            // that had real, extractable text is exactly the failure mode
            // that motivated switching rasterizers in the first place
            // (see `PdfiumPdfPageRenderingService`'s own doc comment) -
            // this is a defensive backstop for the renderer genuinely
            // failing on some *other* PDF in the future, not something
            // expected to trigger in normal use. A page with no
            // extractable text (a real scanned/image-only page, or a
            // genuinely blank page) is never flagged - there is no
            // independent signal it should have looked any different.
            final sourceText = existingText[page.pageIndex];
            if (sourceText != null && sourceText.trim().isNotEmpty) {
              final decoded = img.decodeJpg(jpegBytes);
              if (decoded != null && looksLikeBlankRenderFailure(decoded)) {
                throw const PdfMergeException(
                  'A page in one of the PDFs could not be rendered correctly and appears blank. '
                  'Please try a different file.',
                );
              }
            }
            final overlay = overlayForExistingText(existingText[page.pageIndex], page.width, page.height, dpi);
            addOverlaidImagePageToDocument(
              doc,
              jpegBytes,
              page.width,
              page.height,
              dpi,
              overlay,
              textFontFallback: overlayTextFontFallback,
            );
            pageCount++;
          }
        } else {
          final img.Image decoded;
          try {
            decoded = decodeToolkitImageOrThrow(input.bytes);
          } on ImageCompressionException catch (e) {
            throw PdfMergeException(e.message);
          }
          final jpegBytes = img.encodeJpg(decoded, quality: imageJpegQuality);
          addImagePageToDocument(doc, jpegBytes, decoded.width, decoded.height, dpi);
          pageCount++;
        }
      }
      final bytes = await doc.save();
      return PdfMergeResult(bytes: bytes, pageCount: pageCount);
    } on PdfRenderingException catch (e) {
      throw PdfMergeException(e.message);
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }
}
