import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/toolkit_paths.dart';
import '../ocr/ocr_page_text_layout.dart' show buildEvenlySpacedLineOverlay;
import 'pdf_overlay.dart';
import 'pdf_text_search_service.dart';

/// Release blocker B3 (`docs/v2/implementation/04-risk-register.md`, R-49):
/// every rasterize-and-rebuild PDF Tool (Compress/Merge/Split/Organize/Edit/
/// Redact, ADR-034) flattens each page to a fresh image with no text layer
/// at all, silently destroying any searchable text - ordinary born-digital
/// text, or this app's own previously-embedded invisible OCR text layer
/// (P0-7/ADR-045) - the source page already had. This class restores it,
/// approximately, on the rebuilt page.
///
/// **Why `read_pdf_text` also finds this app's own invisible OCR text, not
/// just ordinary visible text:** the PDF text-rendering mode (`Tr`) is a
/// graphics-state parameter that only controls how a glyph is *painted*
/// (fill/stroke/clip/invisible, `PdfTextRenderingMode.invisible` = mode 3) -
/// it does not gate whether the underlying text-showing operator (`Tj`/`TJ`)
/// is present in the content stream. Any content-stream-based text
/// extractor reads it exactly the same as visible text; this is the exact
/// property that makes an "invisible OCR text layer" searchable in a real
/// PDF viewer's Ctrl+F in the first place (ADR-045's whole premise) - a
/// reader that special-cased invisible text out of extraction would defeat
/// every OCR-searchable-PDF product that has ever shipped, including
/// Tesseract's own `--pdf` output and Adobe's OCR feature. No new capability
/// is being assumed here, only reused.
///
/// **Why no per-word bounding boxes:** `PdfTextSearchService`
/// (`read_pdf_text`, P0-6) returns flat per-page text only, not word-level
/// geometry - there is no library in this app's dependency set that reads
/// positioned text runs back out of an arbitrary existing PDF's content
/// streams (this app's own OCR pipeline only ever produces bounding boxes
/// by *running* OCR against a rasterized image, never by reading them back
/// out of a PDF that already has text). The reconstructed text is therefore
/// placed with [buildEvenlySpacedLineOverlay] - the exact same "no bounding
/// boxes known" placement `SearchablePdfBuilderService` already uses for a
/// page whose text was known but never OCR'd (P0-7 scenario 26, ADR-045).
/// This reuses an already-tested primitive rather than inventing a second
/// text-placement mechanism for B3.
class PdfSearchableTextPreserver {
  const PdfSearchableTextPreserver({required this.textSearchService});
  final PdfTextSearchService textSearchService;

  /// Returns a `0-based page index -> extracted text` map for [sourceBytes]
  /// - **never throws**. Text-layer preservation is a best-effort addition
  /// on top of a PDF Tool's actual job; a source this library can't parse
  /// (password-protected, corrupted, or genuinely unsupported) degrades to
  /// "nothing to preserve" so the underlying transformation the user
  /// actually asked for is never blocked or failed because of this.
  /// `read_pdf_text` needs a real file path, not raw bytes - [sourceBytes]
  /// is written to a short-lived toolkit temp file, always deleted before
  /// this returns.
  Future<Map<int, String>> extractExistingText(Uint8List sourceBytes) async {
    final tempPath = await newToolkitTempFilePath('pdf');
    try {
      await File(tempPath).writeAsBytes(sourceBytes);
      final pages = await textSearchService.extractPagesText(tempPath);
      final result = <int, String>{};
      for (var i = 0; i < pages.length; i++) {
        if (pages[i].trim().isNotEmpty) result[i] = pages[i];
      }
      return result;
    } catch (_) {
      return const {};
    } finally {
      final file = File(tempPath);
      if (await file.exists()) await file.delete();
    }
  }
}

/// Builds the reconstructed invisible-text overlay for one rebuilt page,
/// given whatever existing text (if any) is already known for it - the one
/// shared call site every rasterize-and-rebuild PDF Tool reuses, instead of
/// six separate copies of "is this text non-blank, then place it."  Returns
/// an empty list (no overlay - unchanged, current behavior) for `null` or
/// blank [text].
List<PdfOverlayElement> overlayForExistingText(String? text, int width, int height, double dpi) {
  if (text == null || text.trim().isEmpty) return const [];
  return buildEvenlySpacedLineOverlay(text, width, height, dpi);
}
