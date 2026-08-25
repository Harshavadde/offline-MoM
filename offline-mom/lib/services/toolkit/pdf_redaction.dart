import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../ocr/hocr_parser.dart' show OcrWord;

/// One rectangular region to permanently redact, normalized to the page's
/// own bounds (0.0-1.0, top-left origin) - same convention as
/// `PdfOverlayElement` (`pdf_overlay.dart`), so one region definition
/// applies correctly regardless of the DPI a page happens to be
/// rasterized at.
///
/// **Deliberately not a `PdfOverlayElement`.** `PdfOverlayElement` describes
/// content drawn *on top of* an unmodified base page image - the original
/// pixels underneath stay fully intact and separately extractable, exactly
/// the property redaction must NOT have (see ADR-040's own explicit
/// prohibition on reusing that mechanism for redaction, and ADR-041 for why
/// P0-3 did not attempt it either). [RedactionRegion] instead marks pixels
/// to be irreversibly overwritten - see [burnRedactions] below.
class RedactionRegion {
  const RedactionRegion({required this.x, required this.y, required this.width, required this.height});

  final double x;
  final double y;
  final double width;
  final double height;

  RedactionRegion copyWith({double? x, double? y, double? width, double? height}) {
    return RedactionRegion(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// Permanently overwrites every pixel inside [regions] with opaque black,
/// on the already-decoded [image] - the actual security-relevant operation
/// this whole feature exists for. Mutates and returns [image] (mirrors
/// `package:image`'s own `fillRect` convention, which does the same).
///
/// This is a genuine full-channel pixel overwrite, not a blend:
/// `img.fillRect` with a fully-opaque color takes its fast "replace every
/// channel" path (confirmed by reading `fill_rect.dart` directly - when
/// `color.a == color.maxChannelValue`, it calls `pixel.set(color)` for
/// every pixel in the rect, not an alpha-mixed blend) - once this runs,
/// the original pixel values in [regions] no longer exist anywhere in
/// [image]'s backing buffer. There is nothing left to recover, because
/// there is nothing left to read: unlike `PdfOverlayRect` (a *second*,
/// separate vector object drawn over an untouched base image, still
/// present underneath), this rewrites the base image's own pixel data
/// before it is ever embedded in a PDF.
///
/// Coordinates are converted from [regions]' normalized (0.0-1.0) space to
/// [image]'s own pixel space using [pageWidth]/[pageHeight] and clamped to
/// the image bounds, so a region that starts or extends slightly outside
/// the page (drawn near an edge, or with a stray sub-pixel rounding
/// difference between the canvas' display size and the source image's
/// pixel size) never throws - it silently clips to the page, the same way
/// every other overlay/canvas coordinate conversion in this codebase
/// already clamps (`_PdfEditCanvas`'s own `.clamp(0.0, 1.0)` calls,
/// `pdf_edit_screen.dart`).
img.Image burnRedactions(img.Image image, List<RedactionRegion> regions, int pageWidth, int pageHeight) {
  for (final region in regions) {
    final x1 = (region.x * pageWidth).round().clamp(0, pageWidth);
    final y1 = (region.y * pageHeight).round().clamp(0, pageHeight);
    final x2 = ((region.x + region.width) * pageWidth).round().clamp(0, pageWidth);
    final y2 = ((region.y + region.height) * pageHeight).round().clamp(0, pageHeight);
    if (x2 <= x1 || y2 <= y1) continue; // a degenerate (zero-area) region - nothing to burn.
    img.fillRect(image, x1: x1, y1: y1, x2: x2 - 1, y2: y2 - 1, color: img.ColorRgb8(0, 0, 0));
  }
  return image;
}

/// Decodes [jpegBytes], burns [regions] into it via [burnRedactions], and
/// re-encodes to JPEG - the synchronous, CPU-bound unit `PdfRedactionService`
/// runs inside `compute()` (an isolate) for each affected page, mirroring
/// `pdf_page_rendering_service.dart`'s own `_encodeRasterAsJpeg` pattern.
/// A public top-level function (not a private closure) so it can be passed
/// to `compute()` directly, and so it is independently unit-testable
/// without spinning up an isolate or a whole `PdfRedactionService` call -
/// this is the function the security regression test in
/// `pdf_redaction_test.dart` calls directly to prove the redacted region's
/// pixels are genuinely overwritten, not just visually covered.
Uint8List redactJpegBytes(Uint8List jpegBytes, List<RedactionRegion> regions, int pageWidth, int pageHeight, {int quality = 90}) {
  final image = img.decodeJpg(jpegBytes);
  if (image == null) {
    throw const FormatException('Could not decode page image for redaction.');
  }
  final redacted = burnRedactions(image, regions, pageWidth, pageHeight);
  return Uint8List.fromList(img.encodeJpg(redacted, quality: quality));
}

/// B3 (release readiness, R-49) - true if [word]'s pixel-space bounding box
/// overlaps [region] **at all** (any overlap, not full containment) -
/// scaled from [region]'s own normalized (0.0-1.0) space into [word]'s pixel
/// space via [pageWidth]/[pageHeight], the same conversion [burnRedactions]
/// already uses so both stay in one shared coordinate system with nothing
/// to transform across.
///
/// Deliberately conservative, per this feature's own security requirement:
/// "if there is uncertainty whether a sensitive word intersects a redaction
/// region, prefer removing that word rather than preserving it." A word
/// that only partially overlaps a redacted region is still excluded, never
/// partially preserved - this is what lets Permanent Redaction's OCR-
/// preservation path (`PdfRedactionService`) safely keep searchable text
/// only for words *demonstrably* outside every redaction region on a page,
/// rather than falling back to dropping the whole page's text (its own
/// safe default when this can't be evaluated at all - no OCR model
/// installed to even recognize the words in the first place).
///
/// A degenerate (zero-area) [region] never intersects anything, matching
/// [burnRedactions]' own "nothing to burn" skip rule for the same case.
bool wordIntersectsRedactionRegion(OcrWord word, RedactionRegion region, int pageWidth, int pageHeight) {
  final rx1 = region.x * pageWidth;
  final ry1 = region.y * pageHeight;
  final rx2 = (region.x + region.width) * pageWidth;
  final ry2 = (region.y + region.height) * pageHeight;
  if (rx2 <= rx1 || ry2 <= ry1) return false;
  return word.x0 < rx2 && word.x1 > rx1 && word.y0 < ry2 && word.y1 > ry1;
}
