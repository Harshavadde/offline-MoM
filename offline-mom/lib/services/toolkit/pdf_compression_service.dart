import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'pdf_document_builder.dart';
import 'pdf_page_rendering_service.dart';
import 'pdf_searchable_text_preservation.dart';

/// Named compression presets (V2 Phase 5B) - each a concrete (DPI, JPEG
/// quality) pair tuned for a named real-world use case, mirroring
/// `ImageCompressionPreset`'s (Phase 5A) preset shape. **Deliberately not
/// a target-byte-size search** the way `ImageCompressionService` is: each
/// retry there costs one pure-Dart re-encode (cheap), but here each retry
/// would mean re-rasterizing every page of the source PDF through the
/// native platform renderer again (expensive, and genuinely slow for a
/// many-page document) - a real cost asymmetry, not a corner cut. A fixed
/// preset tier (this preset's own disclaimer says so explicitly) is the
/// honest, single-pass alternative real tools like this use for exactly
/// this reason.
enum PdfCompressionPreset {
  resumeUpload,
  scholarship,
  governmentExam,
  university,
  emailAttachment,
  custom,
}

class PdfCompressSpec {
  const PdfCompressSpec({required this.dpi, required this.jpegQuality});
  final double dpi;
  final int jpegQuality;
}

class PdfCompressPresetSpecs {
  PdfCompressPresetSpecs._();

  static const String disclaimer =
      'Each preset applies a fixed image quality and resolution tuned for its '
      'use case in a single pass - unlike Image Compress, it does not retry at '
      'progressively lower quality to hit an exact size, since that would mean '
      'reprocessing every page again. Works best on scanned/photographed '
      'documents; a text-only PDF may not shrink much, since compression '
      "re-renders each page as a compressed image.";

  static PdfCompressSpec specFor(PdfCompressionPreset preset) => switch (preset) {
        PdfCompressionPreset.resumeUpload => const PdfCompressSpec(dpi: 150, jpegQuality: 80),
        PdfCompressionPreset.scholarship => const PdfCompressSpec(dpi: 120, jpegQuality: 70),
        PdfCompressionPreset.governmentExam => const PdfCompressSpec(dpi: 100, jpegQuality: 60),
        PdfCompressionPreset.university => const PdfCompressSpec(dpi: 150, jpegQuality: 85),
        PdfCompressionPreset.emailAttachment => const PdfCompressSpec(dpi: 150, jpegQuality: 80),
        PdfCompressionPreset.custom => const PdfCompressSpec(dpi: 150, jpegQuality: 80),
      };

  static String labelFor(PdfCompressionPreset preset) => switch (preset) {
        PdfCompressionPreset.resumeUpload => 'Resume Upload',
        PdfCompressionPreset.scholarship => 'Scholarship',
        PdfCompressionPreset.governmentExam => 'Government Exam',
        PdfCompressionPreset.university => 'University',
        PdfCompressionPreset.emailAttachment => 'Email Attachment',
        PdfCompressionPreset.custom => 'Custom',
      };
}

class PdfCompressionResult {
  const PdfCompressionResult({
    required this.bytes,
    required this.originalSizeBytes,
    required this.pageCount,
  });

  final Uint8List bytes;
  final int originalSizeBytes;
  final int pageCount;

  int get resultSizeBytes => bytes.lengthInBytes;
}

/// Compresses an existing PDF by rasterizing every page at [dpi] and
/// re-encoding it as a JPEG at [jpegQuality], then rebuilding a new PDF
/// from those pages - see ADR-034 for why this rasterize-and-rebuild
/// strategy is this app's PDF-manipulation approach. Every intermediate
/// per-page file is deleted before this returns, success or failure -
/// `try/finally`, matching Phase 4B's leaked-temp-file lesson (ADR-032).
class PdfCompressionService {
  Future<PdfCompressionResult> compress(
    Uint8List sourceBytes, {
    required PdfPageRenderingService renderingService,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 80,
    PdfSearchableTextPreserver? textPreserver,
    // See PdfMergeService.merge's own doc comment on this parameter - the
    // same broader-Unicode-coverage fallback for the invisible search-text
    // layer, now threaded through every rasterize-and-rebuild PDF Tool for
    // consistency, not just Merge.
    List<pw.Font> overlayTextFontFallback = const [],
    // See PdfMergeService.merge's own doc comment on this parameter.
    bool cropToContent = false,
  }) async {
    final tempPaths = <String>[];
    try {
      final existingText = textPreserver == null ? const <int, String>{} : await textPreserver.extractExistingText(sourceBytes);
      final doc = pw.Document();
      var pageCount = 0;
      await for (final page in renderingService.rasterizePages(
        sourceBytes,
        dpi: dpi,
        jpegQuality: jpegQuality,
        cropToContent: cropToContent,
      )) {
        tempPaths.add(page.tempFilePath);
        final jpegBytes = await File(page.tempFilePath).readAsBytes();
        final overlay = overlayForExistingText(existingText[page.pageIndex], page.width, page.height, dpi);
        addOverlaidImagePageToDocument(
          doc,
          jpegBytes,
          page.width,
          page.height,
          dpi,
          overlay,
          textFontFallback: overlayTextFontFallback,
        );
        pageCount++;
      }
      final bytes = await doc.save();
      return PdfCompressionResult(
        bytes: bytes,
        originalSizeBytes: sourceBytes.lengthInBytes,
        pageCount: pageCount,
      );
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }
}
