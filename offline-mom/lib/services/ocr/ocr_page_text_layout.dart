import '../toolkit/pdf_overlay.dart';
import 'hocr_parser.dart';

/// Converts OCR'd words (pixel-space bounding boxes on the *rasterized*
/// page image) into an invisible, per-word-positioned text overlay for
/// that same page - Phase 4's "OCR text placed as an invisible/selectable/
/// searchable text layer aligned with the scanned image" requirement.
///
/// **What this genuinely achieves vs. what it doesn't, stated plainly:**
/// each word is placed at its own real bounding box from Tesseract's hOCR
/// output (`hocr_parser.dart`) - not a single page-level text blob, and
/// not an even-line-spacing guess - so search/select/copy land on
/// approximately the right word, not just "somewhere on the page." It is
/// **not** glyph-perfect: [word.height] is used to size an invisible
/// `pw.Text` run, whose own font metrics (character widths, baseline)
/// don't exactly reproduce the source glyph shapes Tesseract measured, so
/// a hand-drawn selection rectangle in a PDF viewer will not trace the
/// visual word outline pixel-for-pixel the way a true PDF-native OCR
/// pipeline (e.g. `tesseract --pdf`, which this Flutter plugin does not
/// expose) would. Documented as a known limitation (R-44), not hidden.
List<PdfOverlayText> buildInvisibleWordOverlay(
  List<OcrWord> words,
  int imageWidthPx,
  int imageHeightPx,
  double dpi,
) {
  if (imageWidthPx <= 0 || imageHeightPx <= 0) return const [];
  final overlays = <PdfOverlayText>[];
  for (final word in words) {
    if (word.width <= 0 || word.height <= 0) continue;
    final fontSize = (word.height / dpi) * 72.0;
    overlays.add(
      PdfOverlayText(
        text: word.text,
        x: word.x0 / imageWidthPx,
        y: word.y0 / imageHeightPx,
        fontSize: fontSize.clamp(4.0, 400.0),
        invisible: true,
      ),
    );
  }
  return overlays;
}

/// The other source of invisible text `SearchablePdfBuilderService` places:
/// a page that **already had real, extractable text** before this document
/// was rasterized (via `PdfTextSearchService`, P0-6) - reused verbatim
/// instead of re-running OCR over it (scenario 26: don't unnecessarily OCR
/// a page that's already searchable). Genuine real text is strictly more
/// accurate than an OCR reproduction of it would be, but this app's
/// rasterize-and-rebuild PDF strategy (ADR-034) still flattens every page
/// to an image, so the real text still needs to be re-embedded as an
/// invisible layer on the rebuilt page - just without ever calling the OCR
/// engine for it. No bounding-box data exists for this text (it was never
/// OCR'd), so it's spread evenly down the page by line instead of
/// per-word - a coarser placement than [buildInvisibleWordOverlay]'s real
/// per-word boxes, honestly reflecting that this path has less positional
/// information available, not more.
List<PdfOverlayText> buildEvenlySpacedLineOverlay(
  String flatText,
  int imageWidthPx,
  int imageHeightPx,
  double dpi,
) {
  final lines = flatText.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty || imageWidthPx <= 0 || imageHeightPx <= 0) return const [];
  final lineHeightPx = imageHeightPx / lines.length;
  final fontSize = ((lineHeightPx * 0.8) / dpi * 72.0).clamp(4.0, 400.0);
  return [
    for (var i = 0; i < lines.length; i++)
      PdfOverlayText(
        text: lines[i].trim(),
        x: 0.03,
        y: (i * lineHeightPx) / imageHeightPx,
        fontSize: fontSize,
        invisible: true,
      ),
  ];
}
