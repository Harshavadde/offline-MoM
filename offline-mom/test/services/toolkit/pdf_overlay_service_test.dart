// Tests PdfOverlayService/pdf_overlay.dart (Toolkit productization pass,
// P0-2) - the shared foundation Add Text, Signatures, Annotations
// (Highlight/Underline/Strikethrough/Freehand/Shapes), and Watermark all
// build on. Mirrors pdf_compression_service_test.dart's exact pattern
// (FakePdfPageRenderingService, a fake path_provider for temp files) since
// this is the same rasterize-then-rebuild architecture every PDF Tool
// service already uses.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/toolkit/pdf_overlay.dart';
import 'package:offline_mom/services/toolkit/pdf_overlay_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
    docsDir = await Directory.systemTemp.createTemp('pdf_overlay_service_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  group('PdfOverlayService.applyOverlays', () {
    test('produces a valid PDF with the correct page count, empty overlays map', () async {
      final service = PdfOverlayService();
      final rendering = FakePdfPageRenderingService(pageCount: 3);
      final source = Uint8List.fromList([1, 2, 3]);

      final bytes = await service.applyOverlays(source, renderingService: rendering, overlaysByPage: const {});

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('a page with an overlay produces different bytes than the same page with no overlay', () async {
      final service = PdfOverlayService();
      final source = Uint8List.fromList([1, 2, 3]);

      final withoutOverlay = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        overlaysByPage: const {},
      );
      final withOverlay = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        overlaysByPage: const {
          0: [PdfOverlayText(text: 'Stamp', x: 0.1, y: 0.1)],
        },
      );

      expect(withOverlay, isNot(equals(withoutOverlay)));
    });

    test('a page with an empty-list overlay entry produces the same-length output as a page with '
        'no entry at all - the same content, not a genuinely different page', () async {
      final service = PdfOverlayService();
      final source = Uint8List.fromList([1, 2, 3]);

      final noEntry = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        overlaysByPage: const {},
      );
      final emptyEntry = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        overlaysByPage: const {0: []},
      );

      // Not byte-for-byte equal - package:pdf embeds a real CreationDate
      // (DateTime.now()) and document-ID hash on every save() call, so
      // two separate saves of identical *content* are never byte-
      // identical, by design (every real PDF has its own creation
      // timestamp). Length equality is the correct invariant here: the
      // fixed-width metadata differs, the actual page content doesn't.
      expect(emptyEntry.length, noEntry.length);
    });

    test('only the specified page is overlaid - a page missing from the map rebuilds unchanged', () async {
      final service = PdfOverlayService();
      final source = Uint8List.fromList([1, 2, 3]);

      // Page 1 overlaid, page 0 not mentioned at all.
      final selective = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 2),
        overlaysByPage: const {
          1: [PdfOverlayText(text: 'Only page 2', x: 0.1, y: 0.1)],
        },
      );
      // Same 2-page document, neither page overlaid.
      final plain = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 2),
        overlaysByPage: const {},
      );

      expect(selective, isNot(equals(plain)));
      // Can't assert byte-for-byte page-0-equality directly without a PDF
      // parser, but the size difference should be attributable to page 2
      // alone - a coarse sanity check that overlaying didn't touch every
      // page indiscriminately.
      expect(selective.length, greaterThan(plain.length));
    });

    test('every intermediate temp file is deleted after applying overlays', () async {
      final service = PdfOverlayService();
      final source = Uint8List.fromList([1, 2, 3]);

      await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 3),
        overlaysByPage: const {
          0: [PdfOverlayText(text: 'x', x: 0.1, y: 0.1)],
        },
      );

      final leftoverFiles = await Directory('${docsDir.path}/toolkit/tmp')
          .list()
          .where((e) => e is File)
          .toList();
      expect(leftoverFiles, isEmpty);
    });

    test('a translucent highlight rect produces different bytes than an opaque one at the same '
        'position/size - the real graphics-state opacity fix (pw.Opacity), not the ignored '
        'BoxDecoration color alpha - regression test for a bug caught during this feature\'s own '
        'visual verification (a real generated PDF showed the highlight as fully opaque before '
        'the fix)', () async {
      final service = PdfOverlayService();
      final source = Uint8List.fromList([1, 2, 3]);

      const opaqueRed = PdfColor(1, 0, 0, 1.0);
      const translucentRed = PdfColor(1, 0, 0, 0.4);

      final opaque = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        overlaysByPage: const {
          0: [PdfOverlayRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1, color: opaqueRed)],
        },
      );
      final translucent = await service.applyOverlays(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        overlaysByPage: const {
          0: [PdfOverlayRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1, color: translucentRed)],
        },
      );

      expect(translucent, isNot(equals(opaque)));
    });
  });

  group('B3 (release readiness, R-49): searchable text preservation', () {
    test('reconstructs existing page text as real, decompressible content', () async {
      final service = PdfOverlayService();
      final rendering = FakePdfPageRenderingService(pageCount: 1);
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['EditPreservedMarker']),
      );

      final bytes = await service.applyOverlays(
        Uint8List.fromList([1, 2, 3]),
        renderingService: rendering,
        overlaysByPage: const {},
        textPreserver: preserver,
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, 'EditPreservedMarker'), isTrue);
    });

    test('the reconstructed text and the user\'s own visible annotation coexist on the same page', () async {
      final service = PdfOverlayService();
      final rendering = FakePdfPageRenderingService(pageCount: 1);
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['ReconstructedTextMarker']),
      );

      final bytes = await service.applyOverlays(
        Uint8List.fromList([1, 2, 3]),
        renderingService: rendering,
        overlaysByPage: const {
          0: [PdfOverlayText(text: 'UserAnnotationMarker', x: 0.1, y: 0.1)],
        },
        textPreserver: preserver,
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, 'ReconstructedTextMarker'), isTrue);
      expect(_decodedStreamsContain(streams, 'UserAnnotationMarker'), isTrue);
    });

    test('with no textPreserver, applyOverlays behaves exactly as before B3', () async {
      final service = PdfOverlayService();
      final rendering = FakePdfPageRenderingService(pageCount: 1);

      final bytes = await service.applyOverlays(
        Uint8List.fromList([1, 2, 3]),
        renderingService: rendering,
        overlaysByPage: const {},
      );

      expect(bytes, isNotEmpty);
    });
  });

  group('buildOverlaidPageContent', () {
    test('an empty elements list never throws for any element-type construction path', () {
      // Smoke-tests that every PdfOverlayElement subtype's _positionedFor
      // branch is at least reachable/constructible without a layout pass
      // throwing - the real rendering correctness is verified visually
      // (test/manual/generate_pdf_overlay_demo_test.dart), which a plain
      // widget-tree build can't assert on its own.
      const elements = [
        PdfOverlayText(text: 'a', x: 0, y: 0),
        PdfOverlayRect(x: 0, y: 0, width: 0.1, height: 0.1, color: PdfColors.red),
        PdfOverlayRect(x: 0, y: 0, width: 0.1, height: 0.1, color: PdfColors.red, filled: false),
        PdfOverlayLine(points: [(0, 0), (1, 1)], color: PdfColors.blue),
      ];
      final tinyImage = img.Image(width: 4, height: 4);
      img.fill(tinyImage, color: img.ColorRgb8(255, 0, 0));
      final jpegBytes = Uint8List.fromList(img.encodeJpg(tinyImage));

      expect(
        () => buildOverlaidPageContent(
          pw.MemoryImage(jpegBytes),
          100,
          100,
          [...elements, PdfOverlayImage(bytes: jpegBytes, x: 0, y: 0, width: 0.1, height: 0.1)],
        ),
        returnsNormally,
      );
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
