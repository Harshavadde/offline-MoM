import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One item drawn on top of an existing, already-rasterized PDF page -
/// the shared foundation every non-destructive PDF Tool that "adds
/// something to a page" builds on (Add Text, Signatures, Highlight/
/// Underline/Strikethrough/Freehand/Shapes, Watermark), per the
/// Productivity Toolkit productization audit's own recommendation
/// (`docs/v2/implementation/13-productivity-toolkit-productization-audit.md`
/// §3) to build ONE shared primitive rather than five separate ad hoc
/// features - this app's whole PDF strategy is rasterize-and-rebuild
/// (ADR-034), so "add new content to a page" is always "draw something on
/// top of the page image before the same rebuild step every PDF Tool
/// already runs."
///
/// **Deliberately NOT used for redaction.** A vector shape drawn on top of
/// a page in the *same* PDF page (this class's whole mechanism) still
/// leaves the underlying page image's own pixel data fully intact and
/// separately extractable from the output PDF (any tool that reads the
/// embedded image XObject directly, ignoring the vector content drawn
/// over it, recovers the "redacted" content underneath) - exactly the
/// "black box over live content, still recoverable" anti-pattern real
/// redaction must not be. Real redaction (`PdfRedactionService`, a
/// separate class) blacks out pixels of the rasterized image itself,
/// before it's ever embedded - see that class's own doc comment.
///
/// Every coordinate/size below is normalized to the page's own bounds
/// (0.0-1.0, top-left origin), not absolute points or source-image
/// pixels - this makes one overlay definition apply correctly regardless
/// of the DPI a page happens to be rasterized at.
sealed class PdfOverlayElement {
  const PdfOverlayElement();
}

/// Text drawn at a specific position - Add Text (#4) and the typed-
/// signature style (#24) both use this directly; annotation text/shape
/// labels (#31) reuse it too. [rotationDegrees]/[opacity]/[italic]
/// (P0-3, Watermark #35) are additive, backward-compatible extensions -
/// their defaults (0/1.0/false) reproduce the exact widget tree
/// `_positionedFor` built before they existed, so no prior caller's
/// output changes.
class PdfOverlayText extends PdfOverlayElement {
  const PdfOverlayText({
    required this.text,
    required this.x,
    required this.y,
    this.fontSize = 14,
    this.color = PdfColors.black,
    this.rotationDegrees = 0,
    this.opacity = 1.0,
    this.italic = false,
    this.invisible = false,
  });

  final String text;
  final double x;
  final double y;
  final double fontSize;
  final PdfColor color;

  /// Clockwise rotation around the text's own center - Watermark's
  /// conventional diagonal placement.
  final double rotationDegrees;

  /// Real graphics-state opacity (`pw.Opacity`, the same mechanism
  /// `PdfOverlayRect`'s own fix already established - `TextStyle.color`'s
  /// own alpha component is subject to the identical `setFillColor`
  /// alpha-ignoring behavior, confirmed by the same source read), not the
  /// color's own (ignored) alpha channel - Watermark's conventional
  /// semi-transparency.
  final double opacity;
  final bool italic;

  /// P0-7 (OCR/Searchable PDF): renders with the real PDF text-rendering
  /// mode 3 (`PdfTextRenderingMode.invisible`, confirmed by reading
  /// `package:pdf`'s own `graphics.dart`/`widgets/text.dart` - `pw.TextStyle
  /// .renderingMode` maps straight through to the `Tr` operator) instead of
  /// mode 0 (fill). The glyphs are never painted, but they are real PDF
  /// text objects - selectable, searchable, and copyable in any standards-
  /// compliant viewer - drawn directly on top of the same rasterized page
  /// image every other overlay element already draws over, so the visible
  /// page appearance is completely unchanged. This is the OCR text layer's
  /// entire "look like a normal scan, but be searchable" mechanism; every
  /// other overlay use (Add Text, Signatures, Watermark, ...) leaves this
  /// `false`.
  final bool invisible;

  /// Editor drag/resize (P0-3) - repositioning re-derives a whole new
  /// immutable element rather than mutating one in place, matching every
  /// other model in this codebase's own `copyWith` convention.
  PdfOverlayText copyWith({double? x, double? y}) {
    return PdfOverlayText(
      text: text,
      x: x ?? this.x,
      y: y ?? this.y,
      fontSize: fontSize,
      color: color,
      rotationDegrees: rotationDegrees,
      opacity: opacity,
      italic: italic,
      invisible: invisible,
    );
  }
}

/// An arbitrary image drawn at a specific position and size - drawn
/// signatures (rendered from a stroke path to a bitmap before reaching
/// here) and imported signature images (#24-25) both use this.
class PdfOverlayImage extends PdfOverlayElement {
  const PdfOverlayImage({
    required this.bytes,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final double x;
  final double y;
  final double width;
  final double height;

  /// Editor drag/resize (P0-3, Signature placement #24-25's own explicit
  /// "must support moving and resizing" requirement).
  PdfOverlayImage copyWith({double? x, double? y, double? width, double? height}) {
    return PdfOverlayImage(
      bytes: bytes,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// A filled or outlined rectangle - Highlight (#27, semi-transparent
/// fill) and rectangular Shape annotations (#31) both use this.
class PdfOverlayRect extends PdfOverlayElement {
  const PdfOverlayRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.color,
    this.filled = true,
    this.strokeWidth = 1,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final PdfColor color;
  final bool filled;
  final double strokeWidth;
}

/// A polyline through an ordered list of normalized points - Underline
/// and Strikethrough (#28-29, a 2-point horizontal line), Freehand
/// drawing (#30, many points from a captured stroke path), and Arrow
/// annotations (#31) all use this.
class PdfOverlayLine extends PdfOverlayElement {
  const PdfOverlayLine({
    required this.points,
    required this.color,
    this.strokeWidth = 2,
  });

  final List<(double x, double y)> points;
  final PdfColor color;
  final double strokeWidth;
}

/// Builds the `pw.Widget` tree for one page: the existing rasterized page
/// image as the base layer, with every [elements] item drawn on top via a
/// `pw.Stack`/`pw.Positioned` (package:pdf's own vector drawing widgets -
/// the added content stays crisp vector output, never re-rasterized), in
/// list order (later elements draw over earlier ones, matching normal
/// layering expectations). An empty [elements] list produces a widget
/// tree pixel-identical to a plain, non-overlaid page - callers can
/// unconditionally route every page through this function, overlaid or
/// not, without a separate code path for "no overlay on this page."
pw.Widget buildOverlaidPageContent(
  pw.ImageProvider baseImage,
  double pageWidth,
  double pageHeight,
  List<PdfOverlayElement> elements, {
  List<pw.Font> textFontFallback = const [],
}) {
  if (elements.isEmpty) {
    return pw.Image(baseImage, fit: pw.BoxFit.fill);
  }

  return pw.Stack(
    children: [
      pw.Positioned.fill(child: pw.Image(baseImage, fit: pw.BoxFit.fill)),
      for (final element in elements)
        _positionedFor(element, pageWidth, pageHeight, textFontFallback),
    ],
  );
}

pw.Widget _positionedFor(
  PdfOverlayElement element,
  double pageWidth,
  double pageHeight,
  List<pw.Font> textFontFallback,
) {
  return switch (element) {
    PdfOverlayText() => pw.Positioned(
        left: element.x * pageWidth,
        top: element.y * pageHeight,
        child: pw.Opacity(
          opacity: element.opacity,
          child: pw.Transform.rotate(
            angle: element.rotationDegrees * (3.141592653589793 / 180),
            child: pw.Text(
              element.text,
              style: pw.TextStyle(
                fontSize: element.fontSize,
                color: element.color,
                fontStyle: element.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
                renderingMode: element.invisible ? PdfTextRenderingMode.invisible : null,
                // A character the base font can't represent (e.g. a
                // bullet/arrow glyph the base-14 Helvetica font has no
                // WinAnsi code point for) otherwise falls through to
                // `package:pdf`'s own "unable to find a glyph" placeholder
                // box - a *different* drawing primitive from a text
                // glyph, which is why it stayed visible even for text set
                // to [PdfTextRenderingMode.invisible] above (confirmed by
                // reading `package:pdf`'s own `widgets/text.dart`: the
                // placeholder path is reached before the rendering-mode
                // check ever applies). Supplying a broader-coverage
                // fallback font here lets `package:pdf` draw the real
                // glyph instead - see `PdfMergeService`'s own doc comment
                // for where this list comes from and why. Empty by
                // default, so every other overlay caller (Add Text,
                // Signatures, Watermark) is completely unaffected.
                fontFallback: textFontFallback,
              ),
            ),
          ),
        ),
      ),
    PdfOverlayImage() => pw.Positioned(
        left: element.x * pageWidth,
        top: element.y * pageHeight,
        child: pw.SizedBox(
          width: element.width * pageWidth,
          height: element.height * pageHeight,
          child: pw.Image(pw.MemoryImage(element.bytes), fit: pw.BoxFit.fill),
        ),
      ),
    PdfOverlayRect() => pw.Positioned(
        left: element.x * pageWidth,
        top: element.y * pageHeight,
        // `pw.BoxDecoration`'s fill goes through `PdfGraphics.setFillColor`,
        // which only ever emits the PDF `rg` operator (red/green/blue) -
        // confirmed by reading decoration.dart/graphics.dart directly, and
        // by this exact discrepancy showing up in a real generated PDF
        // during this feature's own visual verification: a translucent
        // PdfColor's alpha component is silently ignored by that path,
        // rendering fully opaque regardless of the color's own alpha.
        // Real transparency (needed for Highlight, #27) requires the
        // PDF graphics-state `/ca` operator instead, which `pw.Opacity`
        // wraps correctly (`setGraphicState(PdfGraphicState(opacity:))`).
        child: pw.Opacity(
          opacity: element.color.alpha,
          child: pw.Container(
            width: element.width * pageWidth,
            height: element.height * pageHeight,
            decoration: pw.BoxDecoration(
              color: element.filled ? PdfColor(element.color.red, element.color.green, element.color.blue) : null,
              border: element.filled
                  ? null
                  : pw.Border.all(
                      color: PdfColor(element.color.red, element.color.green, element.color.blue),
                      width: element.strokeWidth,
                    ),
            ),
          ),
        ),
      ),
    PdfOverlayLine() => pw.Positioned.fill(
        child: pw.CustomPaint(
          size: PdfPoint(pageWidth, pageHeight),
          // PdfGraphics is bottom-left-origin (y increasing upward) -
          // see contact_icons.dart's own doc comment, the existing
          // precedent for CustomPaint in this codebase. This class's own
          // element coordinates are top-left-origin (matching every
          // other overlay element's Positioned usage), so y is flipped
          // here specifically, at the one point that touches the raw
          // canvas directly.
          painter: (canvas, size) {
            if (element.points.length < 2) return;
            canvas
              ..setStrokeColor(element.color)
              ..setLineWidth(element.strokeWidth)
              ..moveTo(element.points.first.$1 * pageWidth, size.y - element.points.first.$2 * pageHeight);
            for (final point in element.points.skip(1)) {
              canvas.lineTo(point.$1 * pageWidth, size.y - point.$2 * pageHeight);
            }
            canvas.strokePath();
          },
        ),
      ),
  };
}
