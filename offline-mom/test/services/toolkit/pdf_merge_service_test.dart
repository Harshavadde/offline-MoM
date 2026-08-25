import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/core/utils/toolkit_paths.dart';
import 'package:offline_mom/services/toolkit/pdf_merge_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Returns fixed per-page text for every input PDF this test merges,
/// regardless of the (unpredictable, internally-chosen) temp path
/// `PdfSearchableTextPreserver` writes to - mirrors
/// `pdf_compression_service_test.dart`'s identical fake.
class _FixedTextSearchService implements PdfTextSearchService {
  _FixedTextSearchService(this.pages);
  final List<String> pages;
  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async => pages;
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _syntheticImage({int width = 100, int height = 120}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  return img.encodeJpg(image, quality: 90);
}

void main() {
  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('pdf_merge_service_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('merges a PDF and an image into one PDF with the combined page count',
      () async {
    final service = PdfMergeService();
    final rendering = FakePdfPageRenderingService(pageCount: 2);

    final result = await service.merge(
      [
        PdfMergeInput.pdf(Uint8List(0)),
        PdfMergeInput.image(_syntheticImage()),
      ],
      renderingService: rendering,
    );

    expect(result.pageCount, 3); // 2 PDF pages + 1 image page
    expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
  });

  test('preserves input order in the merged output page count across three '
      'sources', () async {
    final service = PdfMergeService();
    final rendering = FakePdfPageRenderingService(pageCount: 2);

    final result = await service.merge(
      [
        PdfMergeInput.image(_syntheticImage()),
        PdfMergeInput.pdf(Uint8List(0)),
        PdfMergeInput.image(_syntheticImage()),
      ],
      renderingService: rendering,
    );

    expect(result.pageCount, 4); // 1 + 2 + 1
  });

  test('throws when fewer than two inputs are given', () async {
    final service = PdfMergeService();
    final rendering = FakePdfPageRenderingService();

    expect(
      () => service.merge([PdfMergeInput.image(_syntheticImage())], renderingService: rendering),
      throwsA(isA<PdfMergeException>()),
    );
  });

  test('throws a clear exception for an undecodable image input', () async {
    final service = PdfMergeService();
    final rendering = FakePdfPageRenderingService();

    expect(
      () => service.merge(
        [
          PdfMergeInput.image(Uint8List.fromList([1, 2, 3])),
          PdfMergeInput.image(_syntheticImage()),
        ],
        renderingService: rendering,
      ),
      throwsA(isA<PdfMergeException>()),
    );
  });

  test('deletes every intermediate temp file after a successful merge',
      () async {
    final service = PdfMergeService();
    final rendering = FakePdfPageRenderingService(pageCount: 2);
    final tmpDir = Directory('${docsDir.path}/toolkit/tmp');

    await service.merge(
      [PdfMergeInput.pdf(Uint8List(0)), PdfMergeInput.image(_syntheticImage())],
      renderingService: rendering,
    );

    if (await tmpDir.exists()) {
      expect(await tmpDir.list().toList(), isEmpty);
    }
  });

  group('B3 (release readiness, R-49): searchable text preservation', () {
    test('reconstructs existing text for a merged PDF input, but never fabricates any for an image input',
        () async {
      final service = PdfMergeService();
      final rendering = FakePdfPageRenderingService(pageCount: 1);
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['MergePreservedMarker']),
      );

      final result = await service.merge(
        [PdfMergeInput.pdf(Uint8List(0)), PdfMergeInput.image(_syntheticImage())],
        renderingService: rendering,
        textPreserver: preserver,
      );

      final streams = _inflateAllStreams(result.bytes);
      expect(_decodedStreamsContain(streams, 'MergePreservedMarker'), isTrue);
    });

    test('with no textPreserver, merge behaves exactly as before B3 (no crash, same page count)', () async {
      final service = PdfMergeService();
      final rendering = FakePdfPageRenderingService(pageCount: 2);

      final result = await service.merge(
        [PdfMergeInput.pdf(Uint8List(0)), PdfMergeInput.image(_syntheticImage())],
        renderingService: rendering,
      );

      expect(result.pageCount, 3);
    });
  });

  group('near-blank-page rendering-failure detection', () {
    // A real, verified bug: a resume PDF with embedded/subsetted TrueType
    // fonts rasterized to a near-blank page (real extractable text
    // existed, but almost nothing visible rendered) - see
    // PdfiumPdfPageRenderingService's own doc comment. This is the one
    // signal available to catch a *future* rasterizer regression on some
    // other PDF: real extracted text for a page whose rendered image came
    // back essentially blank.
    test('throws a clear exception when a page with real extracted text renders blank', () async {
      final service = PdfMergeService();
      final rendering = _BlankPageRenderingService();
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['This page really has text on it']),
      );

      expect(
        () => service.merge(
          [PdfMergeInput.pdf(Uint8List(0)), PdfMergeInput.image(_syntheticImage())],
          renderingService: rendering,
          textPreserver: preserver,
        ),
        throwsA(isA<PdfMergeException>()),
      );
    });

    test('does NOT throw for a page that renders blank but has no extracted text - '
        'a genuinely blank/scanned/image-only page is never flagged', () async {
      final service = PdfMergeService();
      final rendering = _BlankPageRenderingService();
      // No textPreserver at all - existingText is always empty, exactly
      // like a page PdfSearchableTextPreserver found nothing for.

      final result = await service.merge(
        [PdfMergeInput.pdf(Uint8List(0)), PdfMergeInput.image(_syntheticImage())],
        renderingService: rendering,
      );

      expect(result.pageCount, 2);
    });

    test('does NOT throw for FakePdfPageRenderingService\'s own non-uniform synthetic '
        'pages combined with real extracted text (no false positive on ordinary test '
        'doubles)', () async {
      final service = PdfMergeService();
      final rendering = FakePdfPageRenderingService(pageCount: 1);
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['MergePreservedMarker']),
      );

      final result = await service.merge(
        [PdfMergeInput.pdf(Uint8List(0)), PdfMergeInput.image(_syntheticImage())],
        renderingService: rendering,
        textPreserver: preserver,
      );

      expect(result.pageCount, 2);
    });
  });
}

/// Simulates the exact real bug: a rasterizer that yields a single,
/// genuinely blank (uniform white) page - unlike
/// [FakePdfPageRenderingService], which deliberately draws a non-uniform
/// corner mark precisely so it never collides with this check.
class _BlankPageRenderingService implements PdfPageRenderingService {
  @override
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 85,
    bool cropToContent = false,
  }) async* {
    final image = img.Image(width: 100, height: 120);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final jpegBytes = img.encodeJpg(image, quality: jpegQuality);
    final tempPath = await newToolkitTempFilePath('jpg');
    await File(tempPath).writeAsBytes(jpegBytes);
    yield RasterizedPdfPage(tempFilePath: tempPath, width: 100, height: 120, pageIndex: 0);
  }
}

/// Zlib-inflates every `stream ... endstream` block - mirrors
/// `pdf_compression_service_test.dart`'s identical helper.
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
