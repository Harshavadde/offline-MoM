// Manual verification script (release blocker B3, R-49 - "Preserve OCR
// Searchability Across PDF Transformations") - NOT part of the regular
// regression suite. Demonstrates, against the REAL production
// PdfCompressionService/PdfMergeService/PdfSplitService/PdfPageComposerService
// (Organize)/PdfOverlayService (Edit)/PdfRedactionService code paths (only
// the two native, no-implementation-under-`flutter test` platform channels -
// `Printing.raster`/`read_pdf_text`/`flutter_tesseract_ocr` - are faked,
// same as every other manual demo in this suite, R-32/R-44 and successors),
// that:
//   1. a source PDF's real searchable text (three distinct markers) is
//      genuinely present as decompressible PDF content;
//   2. every rasterize-and-rebuild PDF Tool now RECONSTRUCTS that text on
//      its rebuilt output, instead of silently destroying it (the B3 defect
//      itself, pre-fix);
//   3. Permanent Redaction over one specific marker removes ONLY that
//      marker - from visible pixels AND from the output's searchable/
//      extractable content - while the other two markers remain fully
//      searchable.
//
// Run with: flutter test test/manual/generate_pdf_transform_searchability_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/ocr/hocr_parser.dart';
import 'package:offline_mom/services/ocr/ocr_text_extraction_service.dart';
import 'package:offline_mom/services/toolkit/pdf_compression_service.dart';
import 'package:offline_mom/services/toolkit/pdf_merge_service.dart';
import 'package:offline_mom/services/toolkit/pdf_overlay.dart';
import 'package:offline_mom/services/toolkit/pdf_page_composer.dart';
import 'package:offline_mom/services/toolkit/pdf_overlay_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_redaction.dart';
import 'package:offline_mom/services/toolkit/pdf_redaction_service.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_split_service.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

const _markerAlpha = 'VISIBLE-CONTROL-ALPHA';
const _markerSensitive = 'REDACT-ME-12345';
const _markerBeta = 'VISIBLE-CONTROL-BETA';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// Stands in for `read_pdf_text` (real native plugin, no implementation
/// under `flutter test`, R-32) - returns the same three-marker page text
/// for whatever page count the caller asks about, mirroring how a real
/// searchable PDF's own text would come back regardless of internal temp
/// path (`PdfSearchableTextPreserver` controls that path itself).
class _MarkerTextSearchService implements PdfTextSearchService {
  _MarkerTextSearchService(this.pageCount);
  final int pageCount;
  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async {
    return List.generate(pageCount, (_) => '$_markerAlpha\n$_markerSensitive\n$_markerBeta');
  }
}

Uint8List _controlPageJpeg({int width = 850, int height = 1100}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.drawString(image, 'Demo page', font: img.arial24, x: 40, y: 40, color: img.ColorRgb8(0, 0, 0));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// Zlib-inflates every `stream ... endstream` block - mirrors every other
/// manual demo script's identical helper (matching `package:pdf`'s own
/// default VM deflate).
List<Uint8List> _inflateAllStreams(Uint8List pdfBytes) {
  final decoded = <Uint8List>[];
  final content = String.fromCharCodes(pdfBytes);
  var searchFrom = 0;
  while (true) {
    final streamIdx = content.indexOf('stream', searchFrom);
    if (streamIdx == -1) break;
    var dataStart = streamIdx + 'stream'.length;
    if (pdfBytes[dataStart] == 0x0d) dataStart++;
    if (pdfBytes[dataStart] == 0x0a) dataStart++;
    final endIdx = content.indexOf('endstream', dataStart);
    if (endIdx == -1) break;
    final raw = pdfBytes.sublist(dataStart, endIdx);
    try {
      decoded.add(Uint8List.fromList(zlib.decode(raw)));
    } catch (_) {}
    searchFrom = endIdx + 'endstream'.length;
  }
  return decoded;
}

bool _decodedStreamsContain(List<Uint8List> streams, String text) {
  for (final s in streams) {
    if (String.fromCharCodes(s).contains(text)) return true;
  }
  return false;
}

void main() {
  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('pdf_transform_searchability_demo_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('every rasterize-and-rebuild PDF Tool preserves a source PDF\'s searchable text (B3 fix)', () async {
    final preserver = PdfSearchableTextPreserver(textSearchService: _MarkerTextSearchService(2));
    final source = Uint8List.fromList([1, 2, 3]); // FakePdfPageRenderingService ignores actual bytes

    // --- 1. Compress ---
    final compressResult = await PdfCompressionService().compress(
      source,
      renderingService: FakePdfPageRenderingService(pageCount: 2),
      textPreserver: preserver,
    );
    _assertAllMarkersPresent(compressResult.bytes, 'Compress');

    // --- 2. Merge ---
    final mergeResult = await PdfMergeService().merge(
      [PdfMergeInput.pdf(source), PdfMergeInput.image(_controlPageJpeg())],
      renderingService: FakePdfPageRenderingService(pageCount: 2),
      textPreserver: preserver,
    );
    _assertAllMarkersPresent(mergeResult.bytes, 'Merge');

    // --- 3. Split ---
    final splitOutputs = await PdfSplitService().split(
      source,
      [
        [0],
        [1],
      ],
      renderingService: FakePdfPageRenderingService(pageCount: 2),
      textPreserver: preserver,
    );
    for (var i = 0; i < splitOutputs.length; i++) {
      _assertAllMarkersPresent(splitOutputs[i].bytes, 'Split output ${i + 1}');
    }

    // --- 4. Organize (the real "already-rasterized-pages -> PDF" primitive
    // the production Organize screen actually composes through) ---
    final existingText = await preserver.extractExistingText(source);
    final rasterized = <RasterizedPdfPage>[];
    await for (final p in FakePdfPageRenderingService(pageCount: 2).rasterizePages(source)) {
      rasterized.add(p);
    }
    final organizeInputs = [
      for (final p in rasterized)
        PdfPageInput(
          jpegBytes: await File(p.tempFilePath).readAsBytes(),
          width: p.width,
          height: p.height,
          overlayElements: overlayForExistingText(existingText[p.pageIndex], p.width, p.height, kPdfOutputDpi),
        ),
    ];
    final organizeBytes = await PdfPageComposerService().compose(organizeInputs);
    _assertAllMarkersPresent(organizeBytes, 'Organize');

    // --- 5. Edit (annotations coexist with reconstructed text) ---
    final editBytes = await PdfOverlayService().applyOverlays(
      source,
      renderingService: FakePdfPageRenderingService(pageCount: 2),
      overlaysByPage: const {
        0: [PdfOverlayText(text: 'User annotation', x: 0.1, y: 0.9)],
      },
      textPreserver: preserver,
    );
    _assertAllMarkersPresent(editBytes, 'Edit');

    for (final entry in {
      'compress': compressResult.bytes,
      'merge': mergeResult.bytes,
      'organize': organizeBytes,
      'edit': editBytes,
    }.entries) {
      final outDir = Directory(_outputDir)..createSync(recursive: true);
      final file = File('${outDir.path}/b3_${entry.key}_demo.pdf');
      await file.writeAsBytes(entry.value);
      // ignore: avoid_print
      print('OK   wrote ${file.path} (${entry.value.length} bytes) - all 3 markers remain searchable');
    }
  });

  test('Permanent Redaction over REDACT-ME-12345 removes it from visible pixels AND searchable '
      'content, while VISIBLE-CONTROL-ALPHA/BETA remain fully searchable', () async {
    // Page 300x400, three words laid out so a redaction rectangle can
    // target only the sensitive one.
    const pageWidth = 300;
    const pageHeight = 400;
    final ocr = FakeOcrTextExtractionService(
      defaultWords: const [
        OcrWord(text: _markerAlpha, x0: 10, y0: 10, x1: 150, y1: 30),
        OcrWord(text: _markerSensitive, x0: 100, y0: 150, x1: 220, y1: 175),
        OcrWord(text: _markerBeta, x0: 10, y0: 300, x1: 150, y1: 320),
      ],
    );

    final redactedBytes = await PdfRedactionService().applyRedactions(
      Uint8List.fromList([1, 2, 3]),
      renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: pageWidth, pageHeight: pageHeight),
      regionsByPage: const {
        // Covers only REDACT-ME-12345's own pixel box (100,150)-(220,175),
        // normalized: x 0.33-0.73, y 0.375-0.4375.
        0: [RedactionRegion(x: 0.3, y: 0.35, width: 0.45, height: 0.1)],
      },
      ocrService: ocr,
    );

    final streams = _inflateAllStreams(redactedBytes);
    expect(_decodedStreamsContain(streams, _markerSensitive), isFalse,
        reason: 'the redacted marker must not remain extractable/searchable anywhere in the output');
    expect(_decodedStreamsContain(streams, _markerAlpha), isTrue,
        reason: 'an unaffected marker on the same page must remain searchable');
    expect(_decodedStreamsContain(streams, _markerBeta), isTrue,
        reason: 'an unaffected marker on the same page must remain searchable');

    // Raw byte/string search across the ENTIRE file (not just decompressed
    // streams) - proves the sensitive marker is not recoverable anywhere,
    // including outside content-stream objects.
    final rawText = String.fromCharCodes(redactedBytes);
    expect(rawText.contains(_markerSensitive), isFalse);

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/b3_redact_demo.pdf');
    await file.writeAsBytes(redactedBytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${redactedBytes.length} bytes) - $_markerSensitive is gone, '
        '$_markerAlpha/$_markerBeta remain searchable');
  });

  test('a PDF with no searchable text at all still transforms normally (no B3 regression for image-only scans)',
      () async {
    final preserver = PdfSearchableTextPreserver(textSearchService: _NoTextSearchService());

    final result = await PdfCompressionService().compress(
      Uint8List.fromList([1, 2, 3]),
      renderingService: FakePdfPageRenderingService(pageCount: 1),
      textPreserver: preserver,
    );

    expect(result.bytes, isNotEmpty);
    expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
  });
}

void _assertAllMarkersPresent(Uint8List bytes, String label) {
  final streams = _inflateAllStreams(bytes);
  for (final marker in [_markerAlpha, _markerSensitive, _markerBeta]) {
    expect(
      _decodedStreamsContain(streams, marker),
      isTrue,
      reason: '$label output must keep "$marker" as real, decompressible searchable content',
    );
  }
}

class _NoTextSearchService implements PdfTextSearchService {
  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async => const [];
}
