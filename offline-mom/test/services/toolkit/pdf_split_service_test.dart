import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_split_service.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fixed per-page text for the whole source PDF, indexed by ORIGINAL page
/// index (0-based) - mirrors `pdf_compression_service_test.dart`'s fake,
/// extended here to a per-page list so a specific page's text can be
/// verified as landing in the correct output group.
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

void main() {
  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('pdf_split_service_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('splits into the requested number of output files with the right '
      'page counts and labels', () async {
    final service = PdfSplitService();
    final rendering = FakePdfPageRenderingService(pageCount: 5);

    final outputs = await service.split(
      Uint8List(0),
      [
        [0, 1],
        [2, 3],
        [4],
      ],
      renderingService: rendering,
    );

    expect(outputs, hasLength(3));
    expect(outputs[0].pageCount, 2);
    expect(outputs[0].label, 'Pages 1-2');
    expect(outputs[1].pageCount, 2);
    expect(outputs[2].pageCount, 1);
    expect(outputs[2].label, 'Page 5');
    for (final output in outputs) {
      expect(String.fromCharCodes(output.bytes.take(5)), '%PDF-');
    }
  });

  test('rasterizes each needed page only once even if referenced across '
      'multiple groups (efficiency: one pass, not one per output file)',
      () async {
    final service = PdfSplitService();
    var rasterizeCallCount = 0;
    final rendering = _CountingFakeRenderingService(
      pageCount: 4,
      onRasterizeCall: () => rasterizeCallCount++,
    );

    await service.split(
      Uint8List(0),
      [
        [0, 1],
        [2, 3],
      ],
      renderingService: rendering,
    );

    expect(rasterizeCallCount, 1);
  });

  test('throws when every group is empty', () async {
    final service = PdfSplitService();
    final rendering = FakePdfPageRenderingService(pageCount: 3);

    expect(
      () => service.split(Uint8List(0), [[], []], renderingService: rendering),
      throwsA(isA<PdfSplitException>()),
    );
  });

  test('deletes every intermediate temp file after splitting', () async {
    final service = PdfSplitService();
    final rendering = FakePdfPageRenderingService(pageCount: 4);
    final tmpDir = Directory('${docsDir.path}/toolkit/tmp');

    await service.split(
      Uint8List(0),
      [
        [0, 1],
        [2, 3],
      ],
      renderingService: rendering,
    );

    if (await tmpDir.exists()) {
      expect(await tmpDir.list().toList(), isEmpty);
    }
  });

  group('B3 (release readiness, R-49): searchable text preservation', () {
    test('each output group reconstructs the correct original page\'s text - never a different page\'s',
        () async {
      final service = PdfSplitService();
      final rendering = FakePdfPageRenderingService(pageCount: 3);
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['SplitMarkerPageZero', 'SplitMarkerPageOne', 'SplitMarkerPageTwo']),
      );

      final outputs = await service.split(
        Uint8List(0),
        [
          [0],
          [1, 2],
        ],
        renderingService: rendering,
        textPreserver: preserver,
      );

      final firstOutputStreams = _inflateAllStreams(outputs[0].bytes);
      expect(_decodedStreamsContain(firstOutputStreams, 'SplitMarkerPageZero'), isTrue);
      expect(_decodedStreamsContain(firstOutputStreams, 'SplitMarkerPageOne'), isFalse);

      final secondOutputStreams = _inflateAllStreams(outputs[1].bytes);
      expect(_decodedStreamsContain(secondOutputStreams, 'SplitMarkerPageOne'), isTrue);
      expect(_decodedStreamsContain(secondOutputStreams, 'SplitMarkerPageTwo'), isTrue);
      expect(_decodedStreamsContain(secondOutputStreams, 'SplitMarkerPageZero'), isFalse);
    });

    test('with no textPreserver, split behaves exactly as before B3', () async {
      final service = PdfSplitService();
      final rendering = FakePdfPageRenderingService(pageCount: 2);

      final outputs = await service.split(Uint8List(0), [[0], [1]], renderingService: rendering);

      expect(outputs, hasLength(2));
    });
  });
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

/// Wraps [FakePdfPageRenderingService] to count how many times
/// [rasterizePages] itself is *called* (not how many pages it yields) -
/// proves `PdfSplitService` rasterizes the union of needed pages in one
/// pass rather than once per output group.
class _CountingFakeRenderingService implements PdfPageRenderingService {
  _CountingFakeRenderingService({required int pageCount, required this.onRasterizeCall})
      : _delegate = FakePdfPageRenderingService(pageCount: pageCount);

  final FakePdfPageRenderingService _delegate;
  final void Function() onRasterizeCall;

  @override
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 85,
    bool cropToContent = false,
  }) {
    onRasterizeCall();
    return _delegate.rasterizePages(
      pdfBytes,
      pageIndices: pageIndices,
      dpi: dpi,
      jpegQuality: jpegQuality,
      cropToContent: cropToContent,
    );
  }
}
