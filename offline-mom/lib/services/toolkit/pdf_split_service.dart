import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'pdf_document_builder.dart';
import 'pdf_page_rendering_service.dart';
import 'pdf_searchable_text_preservation.dart';

class PdfSplitOutput {
  const PdfSplitOutput({required this.bytes, required this.pageCount, required this.label});
  final Uint8List bytes;
  final int pageCount;

  /// e.g. "Pages 1-3" - used for the output file's default title.
  final String label;
}

class PdfSplitException implements Exception {
  const PdfSplitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Splits an existing PDF into multiple new PDFs, one per group in
/// [pageGroups] (0-based page indices, each group in the order its own
/// pages should appear in that output). Grouping (page ranges, or "every N
/// pages") is pure list arithmetic the caller (`PdfSplitController`) does
/// itself - this service's only job is turning page-index groups into
/// actual PDF bytes. Every page actually needed across every group is
/// rasterized exactly once (not once per output file it appears in),
/// since a single rasterization pass is the expensive step.
class PdfSplitService {
  Future<List<PdfSplitOutput>> split(
    Uint8List sourceBytes,
    List<List<int>> pageGroups, {
    required PdfPageRenderingService renderingService,
    double dpi = kPdfOutputDpi,
    PdfSearchableTextPreserver? textPreserver,
    // See PdfMergeService.merge's own doc comment on this parameter.
    List<pw.Font> overlayTextFontFallback = const [],
    // See PdfMergeService.merge's own doc comment on this parameter too.
    bool cropToContent = false,
  }) async {
    if (pageGroups.isEmpty || pageGroups.every((g) => g.isEmpty)) {
      throw const PdfSplitException('Choose at least one page range to split into.');
    }
    final neededIndices = pageGroups.expand((g) => g).toSet().toList();
    final tempPaths = <String>[];
    final pagesByIndex = <int, RasterizedPdfPage>{};
    try {
      final existingText = textPreserver == null ? const <int, String>{} : await textPreserver.extractExistingText(sourceBytes);
      await for (final page in renderingService.rasterizePages(
        sourceBytes,
        pageIndices: neededIndices,
        dpi: dpi,
        cropToContent: cropToContent,
      )) {
        tempPaths.add(page.tempFilePath);
        pagesByIndex[page.pageIndex] = page;
      }

      final outputs = <PdfSplitOutput>[];
      for (final group in pageGroups) {
        if (group.isEmpty) continue;
        final doc = pw.Document();
        for (final index in group) {
          final page = pagesByIndex[index];
          if (page == null) continue;
          final jpegBytes = await File(page.tempFilePath).readAsBytes();
          final overlay = overlayForExistingText(existingText[index], page.width, page.height, dpi);
          addOverlaidImagePageToDocument(
            doc,
            jpegBytes,
            page.width,
            page.height,
            dpi,
            overlay,
            textFontFallback: overlayTextFontFallback,
          );
        }
        final bytes = await doc.save();
        final label = group.length == 1
            ? 'Page ${group.first + 1}'
            : 'Pages ${group.first + 1}-${group.last + 1}';
        outputs.add(PdfSplitOutput(bytes: bytes, pageCount: group.length, label: label));
      }
      return outputs;
    } on PdfRenderingException catch (e) {
      throw PdfSplitException(e.message);
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }
}
