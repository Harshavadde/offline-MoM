import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'pdf_page_composer.dart';
import 'pdf_page_rendering_service.dart';
import 'pdf_searchable_text_preservation.dart';

class PdfOrganizeResult {
  const PdfOrganizeResult({required this.bytes, required this.pageCount});
  final Uint8List bytes;
  final int pageCount;
}

class PdfOrganizeException implements Exception {
  const PdfOrganizeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Rebuilds a PDF from a chosen, ordered subset of an existing PDF's pages
/// - covers both "Extract Pages" (a subset) and "Reorder Pages" (any
/// order) from the product brief in one operation, since both are the
/// same underlying transform (see ADR-034 for why this is one tool, not
/// two near-identical page-list screens). [orderedPageIndices] is the
/// *exact* final page order (0-based indices into the source PDF,
/// duplicates and omissions both allowed - a page can be dropped
/// entirely, or, less commonly, repeated).
///
/// The actual page-building step delegates to [PdfPageComposerService]
/// (P0-5, ADR-043) - this class's own job is just rasterizing the needed
/// pages from [sourceBytes] and handing them over in the right order;
/// there is exactly one "build a `pw.Document` from rasterized pages"
/// implementation in this codebase, not a second one duplicated here.
class PdfOrganizeService {
  Future<PdfOrganizeResult> organize(
    Uint8List sourceBytes,
    List<int> orderedPageIndices, {
    required PdfPageRenderingService renderingService,
    double dpi = kPdfOutputDpi,
    PdfSearchableTextPreserver? textPreserver,
    // See PdfMergeService.merge's own doc comment on this parameter.
    List<pw.Font> overlayTextFontFallback = const [],
  }) async {
    if (orderedPageIndices.isEmpty) {
      throw const PdfOrganizeException('Keep at least one page.');
    }
    final tempPaths = <String>[];
    final pagesByIndex = <int, RasterizedPdfPage>{};
    try {
      final existingText = textPreserver == null ? const <int, String>{} : await textPreserver.extractExistingText(sourceBytes);
      await for (final page in renderingService.rasterizePages(
        sourceBytes,
        pageIndices: orderedPageIndices,
        dpi: dpi,
      )) {
        tempPaths.add(page.tempFilePath);
        pagesByIndex[page.pageIndex] = page;
      }

      final inputs = <PdfPageInput>[];
      for (final index in orderedPageIndices) {
        final page = pagesByIndex[index];
        if (page == null) continue;
        final jpegBytes = await File(page.tempFilePath).readAsBytes();
        final overlay = overlayForExistingText(existingText[index], page.width, page.height, dpi);
        inputs.add(PdfPageInput(jpegBytes: jpegBytes, width: page.width, height: page.height, overlayElements: overlay));
      }
      final bytes = await PdfPageComposerService().compose(
        inputs,
        dpi: dpi,
        overlayTextFontFallback: overlayTextFontFallback,
      );
      return PdfOrganizeResult(bytes: bytes, pageCount: orderedPageIndices.length);
    } on PdfRenderingException catch (e) {
      throw PdfOrganizeException(e.message);
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }
}
