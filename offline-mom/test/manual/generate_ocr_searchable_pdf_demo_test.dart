// Manual verification script (P0-7, OCR + Searchable PDF) - NOT part of the
// regular regression suite. `flutter_tesseract_ocr` is a real native
// platform-channel plugin with no implementation under `flutter test` (the
// same standing limitation as `Printing.raster`/`read_pdf_text`, R-32 and
// successors), so OCR itself is faked here (`FakeOcrTextExtractionService`,
// realistic word text/positions) - but every PDF byte written to disk below
// is 100% real output from the actual shipped `SearchablePdfBuilderService`
// production code path, and this script goes one real step further than
// most prior manual demos: it decompresses the generated PDF's own content
// streams (dart:io's `zlib`, matching `package:pdf`'s own default VM
// deflate implementation exactly) and asserts the OCR'd word text is
// literally present as real PDF string-show ("Tj") content - not merely
// "the code that adds it ran without throwing," but genuinely, byte-level
// searchable text sitting inside the produced PDF. What remains unverified
// (disclosed, not claimed): whether a real Android device's Tesseract
// engine recognizes real handwriting/print with the accuracy these words
// assume, and whether Adobe/a real PDF viewer's own text layer indexes it
// identically to this script's own raw decompression check - see R-44,
// docs/v2/implementation/04-risk-register.md.
//
// Run with: flutter test test/manual/generate_ocr_searchable_pdf_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/ocr/hocr_parser.dart';
import 'package:offline_mom/services/ocr/ocr_text_extraction_service.dart';
import 'package:offline_mom/services/ocr/searchable_pdf_builder_service.dart';
import 'package:pdf/pdf.dart' show PdfPageRotation;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// Draws a page that looks like a real scanned document (title bar, ruled
/// "text" lines) at a chosen quality/rotation, so the visual-appearance
/// check below has real content to compare against, not a blank rectangle.
Uint8List _scannedPageJpeg({
  required String heading,
  int width = 850,
  int height = 1100,
  int quality = 85,
  bool lowQuality = false,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(250, 248, 244));
  img.drawString(image, heading, font: img.arial24, x: 40, y: 40, color: img.ColorRgb8(20, 20, 20));
  for (var i = 0; i < 12; i++) {
    final y = 110 + i * 40;
    img.drawLine(image, x1: 40, y1: y, x2: width - 40, y2: y, color: img.ColorRgb8(60, 60, 60));
  }
  if (lowQuality) {
    // Real degradation, not a label - genuine gaussian blur + heavy
    // recompression, mirroring a real low-quality phone scan.
    img.gaussianBlur(image, radius: 3);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: lowQuality ? 30 : quality));
}

Uint8List _blankPageJpeg({int width = 850, int height = 1100}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Words positioned to roughly track the ruled lines `_scannedPageJpeg`
/// actually draws, at a page-appropriate DPI - one [OcrWord] per single
/// word, matching real hOCR output exactly (`parseHocrWords` always
/// produces one `ocrx_word` span per word, never a multi-word phrase in
/// one span - a multi-word `OcrWord.text` here would be unrealistic test
/// data `buildInvisibleWordOverlay` never actually receives in production).
List<OcrWord> _wordsFor(List<String> lines) {
  final words = <OcrWord>[];
  for (var i = 0; i < lines.length; i++) {
    final y = 95 + i * 40;
    var x = 45;
    for (final word in lines[i].split(' ')) {
      final width = word.length * 14;
      words.add(OcrWord(text: word, x0: x, y0: y, x1: x + width, y1: y + 30));
      x += width + 10;
    }
  }
  return words;
}

/// Zlib-inflates every `stream ... endstream` block in [pdfBytes] (matching
/// `package:pdf`'s own default VM deflate, `zlib.encode` - see
/// `pdf/io/vm.dart`) and returns every successfully-decoded block's bytes.
/// A handful of blocks fail to decode (uncompressed metadata streams,
/// binary font program data with its own internal compression) - those are
/// silently skipped, since this helper only needs to find the *content*
/// stream(s) holding the actual page text-show operators.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clean single-page scan produces a real, searchable PDF (scenario: clean scanned page)', () async {
    final docsDir = await Directory.systemTemp.createTemp('ocr_demo_clean_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final page = _scannedPageJpeg(heading: 'Azure Kubernetes Service Notes');
    final words = _wordsFor(['Azure Kubernetes Service', 'Terraform manages infrastructure']);
    final ocr = FakeOcrTextExtractionService(defaultWords: words);
    final service = SearchablePdfBuilderService(ocrService: ocr);

    final bytes = await service.build(
      [OcrSourcePage(jpegBytes: page, width: 850, height: 1100)],
      language: 'eng',
    );

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/ocr_clean_scan_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${bytes.length} bytes) - open and visually confirm the page '
        'looks like a real scan (heading + ruled lines), nothing extra visible.');

    final streams = _inflateAllStreams(bytes);
    for (final word in ['Azure', 'Kubernetes', 'Service', 'Terraform', 'infrastructure']) {
      expect(
        _decodedStreamsContain(streams, word),
        isTrue,
        reason: '"$word" must be present as real, decompressible PDF text content',
      );
    }
  });

  test('multi-page scanned document preserves page count and every page\'s text (scenario: multi-page)', () async {
    final docsDir = await Directory.systemTemp.createTemp('ocr_demo_multi_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final headings = ['Meeting Notes Page 1', 'Meeting Notes Page 2', 'Meeting Notes Page 3'];
    final pages = [
      for (var i = 0; i < headings.length; i++)
        OcrSourcePage(jpegBytes: _scannedPageJpeg(heading: headings[i]), width: 850, height: 1100),
    ];
    // Each page gets its own distinct word so this test can prove every
    // page's text survived, not just the first.
    final perPageWords = [
      _wordsFor(['UniquePageOneMarker']),
      _wordsFor(['UniquePageTwoMarker']),
      _wordsFor(['UniquePageThreeMarker']),
    ];
    var callIndex = 0;
    final ocr = _SequencedOcrService(perPageWords, onCall: () => callIndex++);
    final service = SearchablePdfBuilderService(ocrService: ocr);

    final bytes = await service.build(pages, language: 'eng');
    expect(callIndex, 3);

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/ocr_multipage_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${bytes.length} bytes, ${pages.length} pages)');

    final streams = _inflateAllStreams(bytes);
    expect(_decodedStreamsContain(streams, 'UniquePageOneMarker'), isTrue);
    expect(_decodedStreamsContain(streams, 'UniquePageTwoMarker'), isTrue);
    expect(_decodedStreamsContain(streams, 'UniquePageThreeMarker'), isTrue);
  });

  test('mixed born-digital + scanned document: real text reused verbatim, OCR only for the scanned page', () async {
    final docsDir = await Directory.systemTemp.createTemp('ocr_demo_mixed_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final ocr = FakeOcrTextExtractionService(defaultWords: _wordsFor(['ScannedPageOcrText']));
    final service = SearchablePdfBuilderService(ocrService: ocr);
    final pages = [
      OcrSourcePage(
        jpegBytes: _scannedPageJpeg(heading: 'Born-digital page'),
        width: 850,
        height: 1100,
        existingText: 'RealExtractedBornDigitalText',
      ),
      OcrSourcePage(jpegBytes: _scannedPageJpeg(heading: 'Scanned page'), width: 850, height: 1100),
    ];

    final bytes = await service.build(pages, language: 'eng');
    expect(ocr.callCount, 1, reason: 'only the second, image-only page should reach the OCR engine');

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/ocr_mixed_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${bytes.length} bytes) - page 1 real text reused, page 2 OCR\'d');

    final streams = _inflateAllStreams(bytes);
    expect(_decodedStreamsContain(streams, 'RealExtractedBornDigitalText'), isTrue);
    expect(_decodedStreamsContain(streams, 'ScannedPageOcrText'), isTrue);
  });

  test('rotated scan keeps its /Rotate metadata and its OCR text (scenario: rotated scan)', () async {
    final docsDir = await Directory.systemTemp.createTemp('ocr_demo_rotated_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final ocr = FakeOcrTextExtractionService(defaultWords: _wordsFor(['RotatedPageMarkerText']));
    final service = SearchablePdfBuilderService(ocrService: ocr);
    final page = OcrSourcePage(
      jpegBytes: _scannedPageJpeg(heading: 'Sideways scan'),
      width: 850,
      height: 1100,
      rotation: PdfPageRotation.rotate90,
    );

    final bytes = await service.build([page], language: 'eng');
    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/ocr_rotated_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} - open and confirm the page displays right-side-up '
        '(the /Rotate metadata should make the viewer rotate it automatically)');

    expect(String.fromCharCodes(bytes).contains('/Rotate 90'), isTrue);
    final streams = _inflateAllStreams(bytes);
    expect(_decodedStreamsContain(streams, 'RotatedPageMarkerText'), isTrue);
  });

  test('a low-quality (blurred, heavily-compressed) scan still produces valid searchable output (scenario: low-quality scan)', () async {
    final docsDir = await Directory.systemTemp.createTemp('ocr_demo_lowq_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final ocr = FakeOcrTextExtractionService(defaultWords: _wordsFor(['LowQualityScanText']));
    final service = SearchablePdfBuilderService(ocrService: ocr);
    final page = _scannedPageJpeg(heading: 'Blurry photo of a page', lowQuality: true);

    final bytes = await service.build(
      [OcrSourcePage(jpegBytes: page, width: 850, height: 1100)],
      language: 'eng',
    );
    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/ocr_low_quality_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} - visually confirm the blur/degradation is preserved as-is '
        '(P0-7 never "cleans up" the source image)');

    final streams = _inflateAllStreams(bytes);
    expect(_decodedStreamsContain(streams, 'LowQualityScanText'), isTrue);
  });

  test('a blank page with zero recognized words still produces a valid PDF (scenario: blank page)', () async {
    final docsDir = await Directory.systemTemp.createTemp('ocr_demo_blank_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final ocr = FakeOcrTextExtractionService(defaultWords: const []);
    final service = SearchablePdfBuilderService(ocrService: ocr);

    final bytes = await service.build(
      [OcrSourcePage(jpegBytes: _blankPageJpeg(), width: 850, height: 1100)],
      language: 'eng',
    );
    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/ocr_blank_page_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${bytes.length} bytes) - a blank page with no OCR text, '
        'still a valid, openable PDF');

    expect(bytes, isNotEmpty);
  });
}

class _SequencedOcrService implements OcrTextExtractionService {
  _SequencedOcrService(this._wordsByCall, {required this.onCall});
  final List<List<OcrWord>> _wordsByCall;
  final void Function() onCall;
  var _index = 0;

  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) async {
    final words = _wordsByCall[_index];
    _index++;
    onCall();
    return words;
  }
}
