// Tests pdf_overlay.dart's `textFontFallback` fix for a real, verified bug:
// a bullet character (U+25CF, used by a real resume PDF this bug was
// diagnosed against) has no glyph in the base Helvetica font every
// invisible search-text overlay used to draw with - `package:pdf` then
// draws its own "missing glyph" placeholder box for it, a *different*
// drawing primitive from a text glyph that bypasses the invisible
// render-mode check entirely (confirmed by reading `package:pdf`'s own
// `widgets/text.dart`), which is why it stayed visibly on the page. See
// `PdfMergeService`'s own doc comment and
// `services/toolkit/pdf_page_rendering_service.dart`'s
// `PdfiumPdfPageRenderingService` for the companion rasterizer fix.
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/toolkit/pdf_overlay.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real-world bullet character this bug was diagnosed against
  // (`●`, U+25CF - a real 4-page resume's actual list-item marker,
  // extracted verbatim via this app's own text-extraction pipeline).
  const bulletCodePoint = 0x25CF;

  group('the actual bug mechanism (package:pdf font glyph coverage)', () {
    test('the base Helvetica font cannot represent the bullet character - '
        'this is the exact precondition that produced a visible '
        'missing-glyph box', () {
      final document = PdfDocument();
      final helvetica = PdfFont.helvetica(document);
      expect(helvetica.isRuneSupported(bulletCodePoint), isFalse);
    });

    test('this app\'s own bundled Inter font (assets/fonts/Inter-Regular.ttf, '
        'already used by ResumeTemplateRenderer) can represent it', () async {
      final data = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
      final document = PdfDocument();
      final interFont = PdfTtfFont(document, data);
      expect(interFont.isRuneSupported(bulletCodePoint), isTrue);
    });

    test('the bundled Inter font also covers the arrow character U+2192 '
        '(the same resume\'s other non-WinAnsi character)', () async {
      final data = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
      final document = PdfDocument();
      final interFont = PdfTtfFont(document, data);
      expect(interFont.isRuneSupported(0x2192), isTrue);
    });
  });

  group('buildOverlaidPageContent - textFontFallback plumbing', () {
    Uint8List tinyJpeg() {
      final image = img.Image(width: 4, height: 4);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      return img.encodeJpg(image);
    }

    Future<Uint8List> buildDoc({required List<pw.Font> fallback}) async {
      final doc = pw.Document();
      final overlay = [
        PdfOverlayText(
          text: String.fromCharCode(bulletCodePoint),
          x: 0.05,
          y: 0.05,
          invisible: true,
        ),
      ];
      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(200, 260),
          margin: pw.EdgeInsets.zero,
          build: (context) => buildOverlaidPageContent(
            pw.MemoryImage(tinyJpeg()),
            200,
            260,
            overlay,
            textFontFallback: fallback,
          ),
        ),
      );
      return doc.save();
    }

    test('produces a valid PDF with no fallback font (existing behavior unchanged - '
        'empty default, per buildOverlaidPageContent\'s own signature)', () async {
      final bytes = await buildDoc(fallback: const []);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('produces a valid PDF when the Inter fallback font is supplied', () async {
      final data = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
      final bytes = await buildDoc(fallback: [pw.Font.ttf(data)]);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('an empty elements list is unaffected by textFontFallback (no overlay drawn at all)', () {
      final widget = buildOverlaidPageContent(
        pw.MemoryImage(tinyJpeg()),
        200,
        260,
        const [],
        textFontFallback: const [],
      );
      expect(widget, isA<pw.Image>());
    });
  });
}
