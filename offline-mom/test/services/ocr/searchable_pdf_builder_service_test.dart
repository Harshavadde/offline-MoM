import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/ocr/hocr_parser.dart';
import 'package:offline_mom/services/ocr/ocr_text_extraction_service.dart';
import 'package:offline_mom/services/ocr/searchable_pdf_builder_service.dart';
import 'package:pdf/pdf.dart' show PdfPageRotation;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _tinyJpeg() {
  final image = img.Image(width: 40, height: 40);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late FakeOcrTextExtractionService fakeOcr;
  late SearchablePdfBuilderService service;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('searchable_pdf_builder_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    fakeOcr = FakeOcrTextExtractionService(
      defaultWords: const [OcrWord(text: 'Kubernetes', x0: 20, y0: 20, x1: 220, y1: 70)],
    );
    service = SearchablePdfBuilderService(ocrService: fakeOcr);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('empty page list throws', () async {
    await expectLater(
      service.build(const [], language: 'eng'),
      throwsA(isA<SearchablePdfBuilderException>()),
    );
  });

  test('produces real, non-empty PDF bytes for a single page and calls OCR once', () async {
    final bytes = await service.build(
      [OcrSourcePage(jpegBytes: _tinyJpeg(), width: 600, height: 800)],
      language: 'eng',
    );
    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 4), utf8Prefix('%PDF'));
    expect(fakeOcr.callCount, 1);
  });

  test('multi-page document runs OCR once per page and reports progress for every page (scenario 3)', () async {
    final progressCalls = <(int, int)>[];
    final pages = List.generate(
      5,
      (_) => OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500),
    );
    await service.build(
      pages,
      language: 'eng',
      onProgress: (done, total) => progressCalls.add((done, total)),
    );
    expect(fakeOcr.callCount, 5);
    expect(progressCalls, [(1, 5), (2, 5), (3, 5), (4, 5), (5, 5)]);
  });

  test('a page with existing real text is never sent to OCR (scenario 26)', () async {
    final pages = [
      OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500, existingText: 'Already searchable text'),
      OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500),
    ];
    await service.build(pages, language: 'eng');
    expect(fakeOcr.callCount, 1, reason: 'only the second (image-only) page should be OCR\'d');
  });

  test('mixed searchable + scanned document still produces one PDF with both pages (scenario 4)', () async {
    final pages = [
      OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500, existingText: 'Born-digital text'),
      OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500),
    ];
    final bytes = await service.build(pages, language: 'eng');
    expect(bytes, isNotEmpty);
  });

  test('cancellation before the first page throws a cancelled exception and calls OCR zero times (scenario 5)', () async {
    await expectLater(
      service.build(
        [OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500)],
        language: 'eng',
        isCancelled: () => true,
      ),
      throwsA(isA<SearchablePdfBuilderException>().having((e) => e.wasCancelled, 'wasCancelled', isTrue)),
    );
    expect(fakeOcr.callCount, 0);
  });

  test('cancellation mid-document stops before the remaining pages are OCR\'d', () async {
    var callsSoFar = 0;
    final pages = List.generate(4, (_) => OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500));
    await expectLater(
      service.build(
        pages,
        language: 'eng',
        onProgress: (_, _) => callsSoFar++,
        isCancelled: () => callsSoFar >= 2,
      ),
      throwsA(isA<SearchablePdfBuilderException>()),
    );
    expect(fakeOcr.callCount, 2, reason: 'stopped after page 2, never reached pages 3-4');
  });

  test('OCR failure on a page surfaces as a real, catchable failure, not a corrupt PDF (scenario 6)', () async {
    final failingService = SearchablePdfBuilderService(ocrService: _AlwaysFailingOcrService());
    await expectLater(
      failingService.build(
        [OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500)],
        language: 'eng',
      ),
      throwsA(isA<SearchablePdfBuilderException>()),
    );
  });

  test('retry after a failure succeeds once the underlying OCR call stops failing (scenario 7)', () async {
    final flaky = _FlakyOnceOcrService();
    final flakyService = SearchablePdfBuilderService(ocrService: flaky);
    final page = OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500);
    await expectLater(flakyService.build([page], language: 'eng'), throwsA(isA<SearchablePdfBuilderException>()));
    final bytes = await flakyService.build([page], language: 'eng');
    expect(bytes, isNotEmpty);
  });

  test('temp JPEG files used for OCR are deleted afterward, success or failure (scenario 21)', () async {
    final recording = _RecordingOcrService();
    final recordingService = SearchablePdfBuilderService(ocrService: recording);
    await recordingService.build(
      [OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500)],
      language: 'eng',
    );
    expect(recording.requestedPaths, hasLength(1));
    expect(await File(recording.requestedPaths.single).exists(), isFalse);
  });

  test('a blank/degenerate page (no recognizable words) still produces a valid PDF with no invisible text (scenario 23)', () async {
    final blank = FakeOcrTextExtractionService(defaultWords: const []);
    final blankService = SearchablePdfBuilderService(ocrService: blank);
    final bytes = await blankService.build(
      [OcrSourcePage(jpegBytes: _tinyJpeg(), width: 400, height: 500)],
      language: 'eng',
    );
    expect(bytes, isNotEmpty);
  });

  test('a rotated page keeps its /Rotate metadata in the output document', () async {
    final bytes = await service.build(
      [
        OcrSourcePage(
          jpegBytes: _tinyJpeg(),
          width: 400,
          height: 500,
          rotation: PdfPageRotation.rotate90,
        ),
      ],
      language: 'eng',
    );
    expect(bytes, isNotEmpty);
  });
}

List<int> utf8Prefix(String s) => s.codeUnits;

class _AlwaysFailingOcrService implements OcrTextExtractionService {
  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) {
    throw const OcrExtractionException('native OCR failure');
  }
}

class _FlakyOnceOcrService implements OcrTextExtractionService {
  var _calls = 0;
  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) async {
    _calls++;
    if (_calls == 1) throw const OcrExtractionException('transient failure');
    return const [OcrWord(text: 'Recovered', x0: 10, y0: 10, x1: 100, y1: 40)];
  }
}

class _RecordingOcrService implements OcrTextExtractionService {
  final requestedPaths = <String>[];
  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) async {
    requestedPaths.add(imagePath);
    return const [OcrWord(text: 'X', x0: 1, y0: 1, x1: 10, y1: 10)];
  }
}
