import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/widgets.dart' as pw;

import 'pdf_document_builder.dart';

/// One page in an in-progress scan session (before "Generate PDF") - the
/// working image state after whatever crop/perspective-correction/rotation
/// has been applied so far. A plain value class (no controller/BuildContext),
/// so it's safe to pass across an isolate boundary via [compute].
class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.jpegBytes,
    required this.width,
    required this.height,
  });

  /// Locally-unique within one scan session (not a database id) - lets the
  /// UI reference/reorder/delete a specific page without relying on list
  /// index, which shifts under reorder/delete.
  final String id;

  /// Always JPEG-encoded (both camera-captured and gallery-imported pages
  /// are normalized to JPEG on import, and every edit re-encodes to JPEG) -
  /// keeps `ScannerPdfService` and the perspective-correction pipeline
  /// working with one format throughout, mirroring `ImageCompressionService`'s
  /// existing JPEG-centric convention for this module.
  final Uint8List jpegBytes;
  final int width;
  final int height;
}

class ScannerPdfException implements Exception {
  const ScannerPdfException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Builds a single PDF from an ordered list of scanned page images -
/// Scanner's "Generate PDF" step. Each page becomes one PDF page sized to
/// match that image's own pixel dimensions at [dpi] (not a fixed A4/Letter
/// page with the image awkwardly fit/padded inside it), matching how real
/// scanner apps size PDF pages to the captured content.
abstract class ScannerPdfService {
  Future<Uint8List> buildPdf(List<ScannedPage> pages, {double dpi});
}

class PwScannerPdfService implements ScannerPdfService {
  @override
  Future<Uint8List> buildPdf(List<ScannedPage> pages, {double dpi = 150}) {
    if (pages.isEmpty) {
      throw const ScannerPdfException('Add at least one page before generating a PDF.');
    }
    return compute(
      _buildPdfBytes,
      _BuildPdfRequest(pages: pages, dpi: dpi),
    );
  }
}

class _BuildPdfRequest {
  const _BuildPdfRequest({required this.pages, required this.dpi});
  final List<ScannedPage> pages;
  final double dpi;
}

Future<Uint8List> _buildPdfBytes(_BuildPdfRequest request) async {
  final doc = pw.Document();
  for (final page in request.pages) {
    addImagePageToDocument(doc, page.jpegBytes, page.width, page.height, request.dpi);
  }
  return doc.save();
}
