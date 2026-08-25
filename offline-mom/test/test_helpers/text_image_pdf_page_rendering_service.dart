import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:offline_mom/core/utils/toolkit_paths.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';

/// A fake [PdfPageRenderingService] that yields pages containing genuinely
/// rendered text (via `package:image`'s own bitmap-font drawing, not a
/// solid color) plus a distinct colored block standing in for an image -
/// used by P0-4's redaction security proof (both the automated
/// "no extractable text anywhere in the output PDF bytes" regression test
/// and the manual visual-verification script) to demonstrate redaction
/// against content that actually *looks like* text and an image, not just
/// an arbitrary flat color.
///
/// Still a fake for the same unavoidable reason every other PDF Tool test
/// in this codebase uses one: `Printing.raster` is a platform channel with
/// no implementation under `flutter test`. The point of this particular
/// fake is not to simulate real PDF text objects (this app has none - see
/// ADR-034) but to give the redaction pixel-burn step something visually
/// meaningful to redact, for a stronger, more concrete proof than a plain
/// solid-color page would provide.
class TextImagePdfPageRenderingService implements PdfPageRenderingService {
  TextImagePdfPageRenderingService({
    this.pageWidth = 600,
    this.pageHeight = 800,
    this.text = 'CONFIDENTIAL: SSN 123-45-6789',
    this.textX = 40,
    this.textY = 60,
  });

  final int pageWidth;
  final int pageHeight;
  final String text;
  final int textX;
  final int textY;

  @override
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 90,
    bool cropToContent = false,
  }) async* {
    final image = img.Image(width: pageWidth, height: pageHeight);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    // Rendered text - visually and byte-wise "real text", the exact thing
    // a redaction feature must be able to remove.
    img.drawString(image, text, font: img.arial24, x: textX, y: textY, color: img.ColorRgb8(0, 0, 0));

    // A distinct colored block standing in for an embedded image/photo -
    // a filled rect is a fine stand-in, since redaction is content-agnostic
    // by construction (see pdf_redaction.dart's own doc comment): it
    // overwrites pixels regardless of what produced them.
    img.fillRect(image, x1: 60, y1: 300, x2: 260, y2: 420, color: img.ColorRgb8(40, 110, 200));
    img.drawString(image, 'photo.jpg', font: img.arial14, x: 100, y: 350, color: img.ColorRgb8(255, 255, 255));

    // Unredacted control text - proves content OUTSIDE the redacted
    // region survives untouched.
    img.drawString(image, 'This paragraph is not redacted.', font: img.arial14, x: 40, y: 500, color: img.ColorRgb8(0, 0, 0));

    final jpegBytes = img.encodeJpg(image, quality: jpegQuality);
    final tempPath = await newToolkitTempFilePath('jpg');
    await File(tempPath).writeAsBytes(jpegBytes);
    yield RasterizedPdfPage(tempFilePath: tempPath, width: pageWidth, height: pageHeight, pageIndex: 0);
  }
}
