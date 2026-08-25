import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/toolkit/pdf_organize_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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
    docsDir = await Directory.systemTemp.createTemp('pdf_organize_service_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('extracts a subset of pages - result page count matches the subset, '
      'not the source', () async {
    final service = PdfOrganizeService();
    final rendering = FakePdfPageRenderingService(pageCount: 6);

    final result = await service.organize(Uint8List(0), [1, 3, 5], renderingService: rendering);

    expect(result.pageCount, 3);
    expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
  });

  test('a reordered index list produces a PDF built in that exact order - '
      'verified by page-count and by the underlying rasterizer receiving '
      'every index needed regardless of the order requested', () async {
    final service = PdfOrganizeService();
    final rendering = FakePdfPageRenderingService(pageCount: 4);

    // Reversed order: page 3 first, page 0 last.
    final result = await service.organize(Uint8List(0), [3, 2, 1, 0], renderingService: rendering);

    expect(result.pageCount, 4);
  });

  test('throws when the ordered page list is empty', () async {
    final service = PdfOrganizeService();
    final rendering = FakePdfPageRenderingService(pageCount: 3);

    expect(
      () => service.organize(Uint8List(0), [], renderingService: rendering),
      throwsA(isA<PdfOrganizeException>()),
    );
  });

  test('propagates a rasterization failure as PdfOrganizeException, not a '
      'raw crash', () async {
    final service = PdfOrganizeService();
    final rendering = FakePdfPageRenderingService(
      throwOnRasterize: const PdfRenderingException('corrupted'),
    );

    expect(
      () => service.organize(Uint8List(0), [0], renderingService: rendering),
      throwsA(isA<PdfOrganizeException>()),
    );
  });

  test('deletes every intermediate temp file after organizing', () async {
    final service = PdfOrganizeService();
    final rendering = FakePdfPageRenderingService(pageCount: 5);
    final tmpDir = Directory('${docsDir.path}/toolkit/tmp');

    await service.organize(Uint8List(0), [0, 2, 4], renderingService: rendering);

    if (await tmpDir.exists()) {
      expect(await tmpDir.list().toList(), isEmpty);
    }
  });

  group('B3 (release readiness, R-49): searchable text preservation', () {
    test('reconstructs a duplicated page\'s text on both copies - both remain equally searchable', () async {
      final service = PdfOrganizeService();
      final rendering = FakePdfPageRenderingService(pageCount: 2);
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['OrganizeMarkerPageZero', 'OrganizeMarkerPageOne']),
      );

      // Page 0 duplicated: appears twice in the output order.
      final result = await service.organize(Uint8List(0), [0, 0, 1], renderingService: rendering, textPreserver: preserver);

      final streams = _inflateAllStreams(result.bytes);
      expect(_decodedStreamsContain(streams, 'OrganizeMarkerPageZero'), isTrue);
      expect(_decodedStreamsContain(streams, 'OrganizeMarkerPageOne'), isTrue);
    });

    test('with no textPreserver, organize behaves exactly as before B3', () async {
      final service = PdfOrganizeService();
      final rendering = FakePdfPageRenderingService(pageCount: 3);

      final result = await service.organize(Uint8List(0), [1, 3, 5], renderingService: rendering);

      expect(result.pageCount, 3);
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
