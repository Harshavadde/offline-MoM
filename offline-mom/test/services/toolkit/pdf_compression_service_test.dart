import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/toolkit/pdf_compression_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// A test-only [PdfTextSearchService] that returns the same fixed per-page
/// text regardless of the path it's asked to read - the exact temp path
/// `PdfSearchableTextPreserver` writes source bytes to is internal/
/// unpredictable from the outside, so these tests only need "whatever gets
/// extracted flows through to the rebuilt output," not a specific path.
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
    docsDir = await Directory.systemTemp.createTemp('pdf_compression_service_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('compresses a multi-page PDF and reports the correct page count', () async {
    final service = PdfCompressionService();
    final rendering = FakePdfPageRenderingService(pageCount: 4);
    final source = Uint8List.fromList([1, 2, 3]); // fake service ignores actual bytes

    final result = await service.compress(source, renderingService: rendering, dpi: 100, jpegQuality: 70);

    expect(result.pageCount, 4);
    expect(result.originalSizeBytes, source.lengthInBytes);
    expect(result.bytes, isNotEmpty);
    // A real, valid PDF starts with the %PDF- magic header.
    expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
  });

  test('deletes every intermediate temp file, even on success', () async {
    final service = PdfCompressionService();
    final rendering = FakePdfPageRenderingService(pageCount: 3);
    final tmpDir = Directory('${docsDir.path}/toolkit/tmp');

    await service.compress(Uint8List(0), renderingService: rendering);

    if (await tmpDir.exists()) {
      expect(await tmpDir.list().toList(), isEmpty);
    }
  });

  test('deletes intermediate temp files even when rasterization fails partway',
      () async {
    final service = PdfCompressionService();
    // Throws immediately - simulates a real rasterization failure.
    final rendering = FakePdfPageRenderingService(
      throwOnRasterize: const PdfRenderingException('boom'),
    );
    final tmpDir = Directory('${docsDir.path}/toolkit/tmp');

    await expectLater(
      service.compress(Uint8List(0), renderingService: rendering),
      throwsA(isA<PdfRenderingException>()),
    );

    if (await tmpDir.exists()) {
      expect(await tmpDir.list().toList(), isEmpty);
    }
  });

  group('PdfCompressPresetSpecs', () {
    test('every preset has a positive DPI and quality', () {
      for (final preset in PdfCompressionPreset.values) {
        final spec = PdfCompressPresetSpecs.specFor(preset);
        expect(spec.dpi, greaterThan(0), reason: preset.name);
        expect(spec.jpegQuality, greaterThan(0), reason: preset.name);
        expect(spec.jpegQuality, lessThanOrEqualTo(100), reason: preset.name);
      }
    });

    test('governmentExam is more aggressive than university (lower or equal '
        'DPI and quality) - matches the presets\' own stated intent', () {
      final exam = PdfCompressPresetSpecs.specFor(PdfCompressionPreset.governmentExam);
      final university = PdfCompressPresetSpecs.specFor(PdfCompressionPreset.university);
      expect(exam.dpi, lessThanOrEqualTo(university.dpi));
      expect(exam.jpegQuality, lessThanOrEqualTo(university.jpegQuality));
    });
  });

  group('B3 (release readiness, R-49): searchable text preservation', () {
    test('with no textPreserver, output has no reconstructed text (unchanged, pre-B3 behavior)', () async {
      final service = PdfCompressionService();
      final rendering = FakePdfPageRenderingService(pageCount: 1);

      final result = await service.compress(Uint8List(0), renderingService: rendering);

      final streams = _inflateAllStreams(result.bytes);
      expect(_decodedStreamsContain(streams, 'ShouldNotAppear'), isFalse);
    });

    test('with a textPreserver, existing page text is reconstructed as real, searchable content', () async {
      final service = PdfCompressionService();
      final rendering = FakePdfPageRenderingService(pageCount: 2);
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(['CompressPreservedMarkerOne', 'CompressPreservedMarkerTwo']),
      );

      final result = await service.compress(Uint8List(0), renderingService: rendering, textPreserver: preserver);

      final streams = _inflateAllStreams(result.bytes);
      expect(_decodedStreamsContain(streams, 'CompressPreservedMarkerOne'), isTrue);
      expect(_decodedStreamsContain(streams, 'CompressPreservedMarkerTwo'), isTrue);
    });

    test('a source with no extractable text (image-only scan) compresses normally, no overlay added', () async {
      final service = PdfCompressionService();
      final rendering = FakePdfPageRenderingService(pageCount: 1);
      final preserver = PdfSearchableTextPreserver(textSearchService: _FixedTextSearchService(const ['']));

      final result = await service.compress(Uint8List(0), renderingService: rendering, textPreserver: preserver);

      expect(result.bytes, isNotEmpty);
      expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
    });
  });
}

/// Zlib-inflates every `stream ... endstream` block in [pdfBytes] - mirrors
/// `test/manual/generate_ocr_searchable_pdf_demo_test.dart`'s identical
/// helper (matching `package:pdf`'s own default VM deflate). A handful of
/// blocks fail to decode (uncompressed metadata, binary font data) and are
/// silently skipped - this only needs to find the content stream(s) holding
/// the actual page text-show operators.
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
    } catch (_) {
      // Not a zlib-compressed block (or a font binary) - skip.
    }
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
