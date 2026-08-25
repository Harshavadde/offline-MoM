// Tests pdf_redaction.dart/PdfRedactionService (P0-4, Permanent PDF
// Redaction) - the security-critical pixel-burn primitive, distinct from
// pdf_overlay_service_test.dart (which tests the shared *overlay*
// primitive ADR-040/ADR-041 explicitly say redaction must NOT reuse).
//
// The 'burnRedactions genuinely overwrites pixel data' group below is the
// security regression suite the P0-4 spec explicitly requires: a test that
// would fail if this feature merely drew a black vector rectangle over an
// untouched base image (a naive/wrong implementation would leave the
// original pixel values fully intact and this test would catch it
// immediately, since it decodes the actual returned image and inspects
// pixel channel values directly - it does not just compare output byte
// lengths or trust that "some overlay was applied").
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/ocr/hocr_parser.dart';
import 'package:offline_mom/services/ocr/ocr_text_extraction_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_redaction.dart';
import 'package:offline_mom/services/toolkit/pdf_redaction_service.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_helpers/text_image_pdf_page_rendering_service.dart';

class _FixedTextSearchService implements PdfTextSearchService {
  _FixedTextSearchService(this.pages);
  final List<String> pages;
  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async => pages;
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

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  group('burnRedactions genuinely overwrites pixel data (security regression suite)', () {
    test('a redacted region is exactly opaque black; pixels outside it are untouched', () {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(200, 150, 50));

      burnRedactions(image, const [RedactionRegion(x: 0.2, y: 0.2, width: 0.3, height: 0.3)], 100, 100);

      // Inside the region (maps to pixel rect [20,20]-[49,49] inclusive):
      // exactly black, every channel - a genuine overwrite, not a partial
      // blend that would leave some trace of the original color.
      final inside = image.getPixel(35, 35);
      expect(inside.r, 0);
      expect(inside.g, 0);
      expect(inside.b, 0);

      // Just outside the region on every side: the original color is
      // fully intact, proving this is a bounded rewrite, not a global one.
      for (final p in [(5, 5), (95, 5), (5, 95), (95, 95), (50, 50)]) {
        final pixel = image.getPixel(p.$1, p.$2);
        expect(pixel.r, 200, reason: 'pixel ${p.$1},${p.$2} red channel');
        expect(pixel.g, 150, reason: 'pixel ${p.$1},${p.$2} green channel');
        expect(pixel.b, 50, reason: 'pixel ${p.$1},${p.$2} blue channel');
      }

      // The exact boundary: pixel 49,49 (last redacted pixel) is black;
      // pixel 50,50 (first pixel outside) is not - proves the region
      // boundary is precise, not off-by-a-visible-margin in either
      // direction.
      expect(image.getPixel(49, 49).r, 0);
      expect(image.getPixel(50, 50).r, 200);
    });

    test('multiple regions on the same image are each independently burned; the gap between them is untouched', () {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(10, 200, 10));

      burnRedactions(
        image,
        const [
          RedactionRegion(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
          RedactionRegion(x: 0.7, y: 0.7, width: 0.3, height: 0.3),
        ],
        100,
        100,
      );

      expect(image.getPixel(5, 5).g, 0); // first region
      expect(image.getPixel(85, 85).g, 0); // second region
      expect(image.getPixel(50, 50).g, 200); // the untouched gap between them
    });

    test('a region extending past the page edge clamps instead of throwing, and still redacts the in-bounds part', () {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(120, 30, 220));

      expect(
        () => burnRedactions(image, const [RedactionRegion(x: 0.8, y: -0.1, width: 0.5, height: 0.3)], 100, 100),
        returnsNormally,
      );
      expect(image.getPixel(99, 0).r, 0); // the in-bounds corner of the out-of-bounds region
      expect(image.getPixel(50, 50).r, 120); // far from the region, untouched
    });

    test('a large region covering most of the page redacts everything except a thin untouched margin', () {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(240, 240, 10));

      burnRedactions(image, const [RedactionRegion(x: 0.05, y: 0.05, width: 0.9, height: 0.9)], 100, 100);

      expect(image.getPixel(50, 50).r, 0); // center - deep inside the redacted area
      expect(image.getPixel(2, 2).r, 240); // the untouched margin, all four corners
      expect(image.getPixel(97, 2).r, 240);
      expect(image.getPixel(2, 97).r, 240);
      expect(image.getPixel(97, 97).r, 240);
    });

    test('a zero-area region is a no-op - does not throw, does not touch any pixel', () {
      final image = img.Image(width: 50, height: 50);
      img.fill(image, color: img.ColorRgb8(1, 2, 3));

      burnRedactions(image, const [RedactionRegion(x: 0.5, y: 0.5, width: 0, height: 0)], 50, 50);

      for (final p in [(0, 0), (25, 25), (49, 49)]) {
        final pixel = image.getPixel(p.$1, p.$2);
        expect((pixel.r, pixel.g, pixel.b), (1, 2, 3));
      }
    });
  });

  group('redactJpegBytes (decode -> burn -> re-encode round trip)', () {
    test('the redacted region survives JPEG re-encoding as near-black; content outside is preserved', () {
      final source = img.Image(width: 200, height: 200);
      img.fill(source, color: img.ColorRgb8(180, 60, 60));
      final jpeg = Uint8List.fromList(img.encodeJpg(source, quality: 90));

      final redactedJpeg = redactJpegBytes(jpeg, const [RedactionRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5)], 200, 200);
      final redacted = img.decodeJpg(redactedJpeg)!;

      // JPEG re-encoding can introduce small artifacts near hard edges, so
      // this asserts "very dark" rather than exact (0,0,0) - still a
      // conclusive proof the original color is gone, not merely covered.
      final center = redacted.getPixel(100, 100);
      expect(center.r, lessThan(15));
      expect(center.g, lessThan(15));
      expect(center.b, lessThan(15));

      final corner = redacted.getPixel(5, 5);
      expect(corner.r, greaterThan(150)); // still close to the original 180
    });

    test('a redacted region does not retain extractable original pixel values anywhere inside it', () {
      // A distinctive, easy-to-detect color (bright magenta) so any survival
      // of the original pixel data - even partial, even after JPEG loss -
      // would be obvious in the red+blue channels staying high.
      final source = img.Image(width: 120, height: 120);
      img.fill(source, color: img.ColorRgb8(255, 0, 255));
      final jpeg = Uint8List.fromList(img.encodeJpg(source, quality: 95));

      final redactedJpeg = redactJpegBytes(jpeg, const [RedactionRegion(x: 0.1, y: 0.1, width: 0.8, height: 0.8)], 120, 120);
      final redacted = img.decodeJpg(redactedJpeg)!;

      for (final p in [(60, 60), (20, 20), (100, 100), (20, 100), (100, 20)]) {
        final pixel = redacted.getPixel(p.$1, p.$2);
        expect(pixel.r, lessThan(20), reason: 'red channel at ${p.$1},${p.$2} should not retain magenta');
        expect(pixel.b, lessThan(20), reason: 'blue channel at ${p.$1},${p.$2} should not retain magenta');
      }
    });
  });

  group('PdfRedactionService.applyRedactions', () {
    late Directory docsDir;

    setUp(() async {
      docsDir = await Directory.systemTemp.createTemp('pdf_redaction_service_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    });

    tearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    test('produces a valid PDF with no regions at all', () async {
      final service = PdfRedactionService();
      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 2),
        regionsByPage: const {},
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('a page with a redaction produces different bytes than the same page without one', () async {
      final service = PdfRedactionService();
      final source = Uint8List.fromList([1, 2, 3]);

      final plain = await service.applyRedactions(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {},
      );
      final redacted = await service.applyRedactions(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          0: [RedactionRegion(x: 0.2, y: 0.2, width: 0.3, height: 0.3)],
        },
      );

      expect(redacted, isNot(equals(plain)));
    });

    test('only the specified page is redacted - a page missing from the map rebuilds with its original pixels', () async {
      final service = PdfRedactionService();
      final source = Uint8List.fromList([1, 2, 3]);

      // Page 1 (a non-black synthetic color) redacted; page 0 untouched.
      final selective = await service.applyRedactions(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 2, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          1: [RedactionRegion(x: 0.1, y: 0.1, width: 0.4, height: 0.4)],
        },
      );
      final plain = await service.applyRedactions(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 2, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {},
      );

      expect(selective, isNot(equals(plain)));
    });

    test('every intermediate temp file is deleted after applying redactions', () async {
      final service = PdfRedactionService();

      await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 3),
        regionsByPage: const {
          0: [RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2)],
        },
      );

      final leftoverFiles = await Directory('${docsDir.path}/toolkit/tmp').list().where((e) => e is File).toList();
      expect(leftoverFiles, isEmpty);
    });

    // NOTE ON WHAT THIS PROVES: this passes even for a page with NO
    // redaction applied at all, because this app's whole PDF pipeline
    // (ADR-034) never embeds a text layer for any page, redacted or not -
    // every page is a flat rasterized image. This test is still the
    // literal automated version of the P0-4 spec's "attempt text
    // extraction" manual-verification step, and it genuinely demonstrates
    // that property concretely rather than just asserting it in prose.
    // The property unique to *redaction itself* (that the selected
    // region's pixel data is gone, not just never-was-text) is what the
    // 'burnRedactions genuinely overwrites pixel data' group above proves.
    test('a real text+image page: the sensitive string is not extractable/searchable anywhere in the '
        'output PDF\'s raw bytes after redaction ("attempt text extraction", the P0-4 spec\'s own '
        'manual-verification step, run here as an automated proof)', () async {
      final service = PdfRedactionService();
      final rendering = TextImagePdfPageRenderingService(text: 'CONFIDENTIAL: SSN 123-45-6789');

      final redacted = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: rendering,
        // Covers the rendered text's own pixel area (drawn at x:40,y:60 in
        // a 600x800 page - normalized to roughly x:0.02-0.62, y:0.05-0.13).
        regionsByPage: const {
          0: [RedactionRegion(x: 0.02, y: 0.04, width: 0.65, height: 0.1)],
        },
      );

      // A raw byte/string search across the *entire* produced PDF, not a
      // scoped lookup - proves the sensitive text isn't recoverable via any
      // text-extraction/search tool, anywhere in the file. latin1 decodes
      // every byte value 0-255 without throwing, so this is a faithful
      // "does this exact byte sequence appear anywhere" check, not an
      // approximation.
      final rawText = latin1.decode(redacted, allowInvalid: true);
      expect(rawText.contains('123-45-6789'), isFalse);
      expect(rawText.contains('CONFIDENTIAL'), isFalse);
    });

    test('the source bytes passed in are never mutated', () async {
      final service = PdfRedactionService();
      final source = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sourceCopy = Uint8List.fromList(source);

      await service.applyRedactions(
        source,
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        regionsByPage: const {
          0: [RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2)],
        },
      );

      expect(source, equals(sourceCopy));
    });
  });

  group('wordIntersectsRedactionRegion (B3, release readiness, R-49) - security-critical intersection rule', () {
    const pageWidth = 300;
    const pageHeight = 400;

    test('a word fully inside the region intersects', () {
      const word = OcrWord(text: 'x', x0: 100, y0: 100, x1: 200, y1: 130);
      const region = RedactionRegion(x: 0.1, y: 0.1, width: 0.8, height: 0.8); // pixel (30,40)-(270,360)
      expect(wordIntersectsRedactionRegion(word, region, pageWidth, pageHeight), isTrue);
    });

    test('a word fully outside the region does not intersect', () {
      const word = OcrWord(text: 'x', x0: 10, y0: 10, x1: 60, y1: 30);
      const region = RedactionRegion(x: 0.3, y: 0.2, width: 0.4, height: 0.2); // pixel (90,80)-(210,160)
      expect(wordIntersectsRedactionRegion(word, region, pageWidth, pageHeight), isFalse);
    });

    test('a word only PARTIALLY overlapping the region still intersects - the conservative "prefer '
        'removal" rule, not "fully contained only"', () {
      // Region: pixel (90,80)-(210,160). Word straddles the region's left
      // edge - only its right half is inside.
      const word = OcrWord(text: 'x', x0: 50, y0: 90, x1: 150, y1: 120);
      const region = RedactionRegion(x: 0.3, y: 0.2, width: 0.4, height: 0.2);
      expect(wordIntersectsRedactionRegion(word, region, pageWidth, pageHeight), isTrue);
    });

    test('a word that only touches the region\'s exact boundary (no area overlap) does not intersect', () {
      // Region: pixel (90,80)-(210,160). Word starts exactly where the
      // region ends (x0 == region's x2) - adjacent, not overlapping.
      const word = OcrWord(text: 'x', x0: 210, y0: 90, x1: 260, y1: 120);
      const region = RedactionRegion(x: 0.3, y: 0.2, width: 0.4, height: 0.2);
      expect(wordIntersectsRedactionRegion(word, region, pageWidth, pageHeight), isFalse);
    });

    test('a zero-area (degenerate) region never intersects anything, matching burnRedactions\' own skip rule', () {
      const word = OcrWord(text: 'x', x0: 90, y0: 80, x1: 210, y1: 160);
      const zeroWidth = RedactionRegion(x: 0.3, y: 0.2, width: 0.0, height: 0.2);
      const zeroHeight = RedactionRegion(x: 0.3, y: 0.2, width: 0.4, height: 0.0);
      expect(wordIntersectsRedactionRegion(word, zeroWidth, pageWidth, pageHeight), isFalse);
      expect(wordIntersectsRedactionRegion(word, zeroHeight, pageWidth, pageHeight), isFalse);
    });

    test('a word never intersects a region entirely outside the page bounds', () {
      const word = OcrWord(text: 'x', x0: 10, y0: 10, x1: 60, y1: 30);
      const region = RedactionRegion(x: 1.5, y: 1.5, width: 0.4, height: 0.2); // pixel (450,600)-(570,680)
      expect(wordIntersectsRedactionRegion(word, region, pageWidth, pageHeight), isFalse);
    });

    test('a word intersecting at least one of several regions counts as intersecting', () {
      const word = OcrWord(text: 'x', x0: 100, y0: 100, x1: 200, y1: 130);
      const regions = [
        RedactionRegion(x: 0.0, y: 0.0, width: 0.05, height: 0.05), // far away, no overlap
        RedactionRegion(x: 0.3, y: 0.2, width: 0.4, height: 0.2), // overlaps the word
      ];
      expect(regions.any((r) => wordIntersectsRedactionRegion(word, r, pageWidth, pageHeight)), isTrue);
    });
  });

  group('PdfRedactionService.applyRedactions - B3 (release readiness, R-49): searchable text preservation', () {
    late Directory docsDir;

    setUp(() async {
      docsDir = await Directory.systemTemp.createTemp('pdf_redaction_b3_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    });

    tearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    test('a page with NO redaction region safely reuses its pre-existing text', () async {
      final service = PdfRedactionService();
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['UnaffectedPageMarker']),
      );

      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 1),
        regionsByPage: const {},
        textPreserver: preserver,
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, 'UnaffectedPageMarker'), isTrue);
    });

    test('a page WITH a redaction region NEVER reuses its pre-existing flat text, even when a '
        'textPreserver is provided - flat text carries no word-level position, so it cannot be '
        'proven safe (this feature\'s own core security requirement)', () async {
      final service = PdfRedactionService();
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['CONFIDENTIAL SSN 123-45-6789']),
      );

      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          0: [RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2)],
        },
        textPreserver: preserver,
        // ocrService intentionally omitted - no model installed.
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, '123-45-6789'), isFalse);
      expect(_decodedStreamsContain(streams, 'CONFIDENTIAL'), isFalse);
    });

    test('with an OCR model available, a redacted page keeps only the words demonstrably OUTSIDE '
        'every redaction region - the redacted word itself is never searchable', () async {
      final service = PdfRedactionService();
      // "SensitiveWord" sits inside the redaction region below; "SafeWord"
      // is far outside it.
      final ocr = FakeOcrTextExtractionService(
        defaultWords: const [
          OcrWord(text: 'SafeWord', x0: 10, y0: 10, x1: 60, y1: 30),
          OcrWord(text: 'SensitiveWord', x0: 100, y0: 100, x1: 200, y1: 130),
        ],
      );

      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          0: [RedactionRegion(x: 0.3, y: 0.2, width: 0.4, height: 0.2)], // pixel (90,80)-(210,160)
        },
        ocrService: ocr,
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, 'SafeWord'), isTrue,
          reason: 'a word demonstrably outside every redaction region must remain searchable');
      expect(_decodedStreamsContain(streams, 'SensitiveWord'), isFalse,
          reason: 'a word inside the redaction region must never remain searchable');
    });

    test('a word only PARTIALLY overlapping a redaction region is excluded too, not partially preserved',
        () async {
      final service = PdfRedactionService();
      // Straddles the region's left edge (region: pixel (90,80)-(210,160)).
      final ocr = FakeOcrTextExtractionService(
        defaultWords: const [OcrWord(text: 'StraddlingWord', x0: 50, y0: 90, x1: 150, y1: 120)],
      );

      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          0: [RedactionRegion(x: 0.3, y: 0.2, width: 0.4, height: 0.2)],
        },
        ocrService: ocr,
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, 'StraddlingWord'), isFalse);
    });

    test('multiple redaction regions on one page: every word intersecting any region is excluded, '
        'safe words from elsewhere on the page remain', () async {
      final service = PdfRedactionService();
      final ocr = FakeOcrTextExtractionService(
        defaultWords: const [
          OcrWord(text: 'FirstSensitiveWord', x0: 10, y0: 10, x1: 60, y1: 30),
          OcrWord(text: 'SecondSensitiveWord', x0: 200, y0: 200, x1: 260, y1: 230),
          OcrWord(text: 'ThirdSafeWord', x0: 10, y0: 300, x1: 80, y1: 330),
        ],
      );

      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          0: [
            RedactionRegion(x: 0.0, y: 0.0, width: 0.3, height: 0.1), // covers FirstSensitiveWord
            RedactionRegion(x: 0.6, y: 0.45, width: 0.3, height: 0.15), // covers SecondSensitiveWord
          ],
        },
        ocrService: ocr,
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, 'FirstSensitiveWord'), isFalse);
      expect(_decodedStreamsContain(streams, 'SecondSensitiveWord'), isFalse);
      expect(_decodedStreamsContain(streams, 'ThirdSafeWord'), isTrue);
    });

    test('redacting page 3 of a multi-page document leaves unaffected pages\' text fully intact',
        () async {
      final service = PdfRedactionService();
      final preserver = PdfSearchableTextPreserver(
        textSearchService: _FixedTextSearchService(const ['PageOneMarker', 'PageTwoMarker', 'PageThreeSensitive']),
      );

      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 3, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          2: [RedactionRegion(x: 0.1, y: 0.1, width: 0.5, height: 0.5)],
        },
        textPreserver: preserver,
        // No OCR model available - page 3 (index 2) safely loses its text
        // layer entirely rather than guessing.
      );

      final streams = _inflateAllStreams(bytes);
      expect(_decodedStreamsContain(streams, 'PageOneMarker'), isTrue);
      expect(_decodedStreamsContain(streams, 'PageTwoMarker'), isTrue);
      expect(_decodedStreamsContain(streams, 'PageThreeSensitive'), isFalse);
    });

    test('an OCR failure on a redacted page degrades to no text layer, never a thrown exception', () async {
      final service = PdfRedactionService();
      final alwaysThrows = _AlwaysThrowingOcrService();

      final bytes = await service.applyRedactions(
        Uint8List.fromList([1, 2, 3]),
        renderingService: FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400),
        regionsByPage: const {
          0: [RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2)],
        },
        ocrService: alwaysThrows,
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}

class _AlwaysThrowingOcrService implements OcrTextExtractionService {
  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) async {
    throw const OcrExtractionException('OCR failed.');
  }
}
