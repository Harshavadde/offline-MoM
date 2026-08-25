import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_overlay.dart';

/// Appends one image as a full PDF page, sized to match the image's own
/// pixel dimensions at [dpi] (not a fixed A4/Letter page) - the one
/// "build a page from an image" operation every PDF Tool
/// (Scanner/Compress/Merge/Split/Organize) needs, kept in one place
/// rather than copy-pasted at each of their call sites.
void addImagePageToDocument(
  pw.Document doc,
  Uint8List jpegBytes,
  int width,
  int height,
  double dpi,
) {
  addOverlaidImagePageToDocument(doc, jpegBytes, width, height, dpi, const []);
}

/// [addImagePageToDocument]'s superset - draws [overlayElements] on top of
/// the same base page image, via [buildOverlaidPageContent]
/// (`pdf_overlay.dart`). An empty [overlayElements] list produces a page
/// pixel-identical to [addImagePageToDocument]'s own output (that function
/// is now a thin wrapper around this one, not a separate code path), so
/// every existing PDF Tool's plain rebuild and every new overlay-based
/// tool share one page-construction implementation.
void addOverlaidImagePageToDocument(
  pw.Document doc,
  Uint8List jpegBytes,
  int width,
  int height,
  double dpi,
  List<PdfOverlayElement> overlayElements, {
  List<pw.Font> textFontFallback = const [],
}) {
  final image = pw.MemoryImage(jpegBytes);
  final pageWidth = width / dpi * PdfPageFormat.inch;
  final pageHeight = height / dpi * PdfPageFormat.inch;
  final pageFormat = PdfPageFormat(pageWidth, pageHeight);
  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.zero,
      build: (context) => buildOverlaidPageContent(
        image,
        pageWidth,
        pageHeight,
        overlayElements,
        textFontFallback: textFontFallback,
      ),
    ),
  );
}
