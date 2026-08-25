import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Small hand-drawn vector glyphs for the header contact row (phone,
/// email, location, link) - **product visual-audit pass**. `package:pdf`'s
/// only glyph-based icon widget (`pw.Icon`) requires an *icon font* mapping
/// codepoints to pictograms (`ThemeData.iconTheme.font`); this project
/// bundles Inter (a text typeface with no icon glyphs) and deliberately
/// does not bundle a second, much larger icon font (Material Symbols is
/// several hundred KB to a few MB) just to draw four small glyphs. Unicode
/// dingbats (☎ ✉ 📍 🔗) were considered and rejected: Inter has no glyphs
/// for them and `ResumeTemplateRenderer`'s `pw.ThemeData.withFont` sets no
/// `fontFallback`, so an unmapped codepoint renders as a missing-glyph box
/// - worse than no icon at all. Hand-drawn vector paths via `pw.CustomPaint`
/// avoid both problems: no extra bundled asset, and every glyph is drawn
/// directly from the same primitives (`moveTo`/`lineTo`/`drawEllipse`/
/// `fillPath`/`strokePath`) `package:pdf` itself uses internally - a real,
/// investigated answer to "can we have icons," not a declared impossibility.
enum ContactIconKind { phone, email, location, link }

/// Builds one small square icon glyph, vertically centered against a text
/// baseline via [size] (matched to the caller's caption font size).
pw.Widget buildContactIcon(ContactIconKind kind, {required double size, required PdfColor color}) {
  return pw.CustomPaint(
    size: PdfPoint(size, size),
    painter: (canvas, pdfSize) {
      switch (kind) {
        case ContactIconKind.phone:
          _paintPhone(canvas, pdfSize, color);
        case ContactIconKind.email:
          _paintEmail(canvas, pdfSize, color);
        case ContactIconKind.location:
          _paintLocation(canvas, pdfSize, color);
        case ContactIconKind.link:
          _paintLink(canvas, pdfSize, color);
      }
    },
  );
}

/// A diagonal rounded-cap stroke between two filled dots - a minimalist
/// "call" glyph (the same simplification many flat icon sets use for a
/// handset), built entirely from `drawEllipse`/`moveTo`/`lineTo`/`strokePath`.
void _paintPhone(PdfGraphics canvas, PdfPoint size, PdfColor color) {
  final r = size.y * 0.15;
  canvas
    ..setStrokeColor(color)
    ..setLineWidth(size.y * 0.22)
    ..moveTo(size.x * 0.24, size.y * 0.76)
    ..lineTo(size.x * 0.76, size.y * 0.24)
    ..strokePath();
  canvas
    ..setFillColor(color)
    ..drawEllipse(size.x * 0.24, size.y * 0.76, r, r)
    ..fillPath();
  canvas
    ..drawEllipse(size.x * 0.76, size.y * 0.24, r, r)
    ..fillPath();
}

/// An envelope: a stroked rectangle with a "V" flap line from the top
/// corners to the vertical center - the standard email-glyph silhouette.
void _paintEmail(PdfGraphics canvas, PdfPoint size, PdfColor color) {
  final w = size.x, h = size.y;
  canvas
    ..setStrokeColor(color)
    ..setLineWidth(h * 0.09)
    ..drawRect(w * 0.05, h * 0.18, w * 0.9, h * 0.64)
    ..strokePath();
  canvas
    ..moveTo(w * 0.08, h * 0.8)
    ..lineTo(w * 0.5, h * 0.45)
    ..lineTo(w * 0.92, h * 0.8)
    ..strokePath();
}

/// A map-pin: a filled circle (the head) sitting on a filled downward
/// triangle (the point) - PDF's coordinate origin is bottom-left with y
/// increasing upward, so the circle sits near the top of the glyph box and
/// the triangle's point reaches down to y=0.
void _paintLocation(PdfGraphics canvas, PdfPoint size, PdfColor color) {
  final w = size.x, h = size.y;
  final cx = w * 0.5;
  final headCy = h * 0.68;
  final headR = w * 0.32;
  canvas
    ..setFillColor(color)
    ..drawEllipse(cx, headCy, headR, headR)
    ..fillPath();
  canvas
    ..moveTo(cx - headR * 0.78, headCy - headR * 0.55)
    ..lineTo(cx + headR * 0.78, headCy - headR * 0.55)
    ..lineTo(cx, 0)
    ..closePath()
    ..fillPath();
}

/// Two overlapping stroked rings - a simplified "chain link" glyph for a
/// portfolio/LinkedIn URL.
void _paintLink(PdfGraphics canvas, PdfPoint size, PdfColor color) {
  final w = size.x, h = size.y;
  final r = h * 0.28;
  canvas
    ..setStrokeColor(color)
    ..setLineWidth(h * 0.14)
    ..drawEllipse(w * 0.36, h * 0.5, r, r)
    ..strokePath();
  canvas
    ..drawEllipse(w * 0.64, h * 0.5, r, r)
    ..strokePath();
}
