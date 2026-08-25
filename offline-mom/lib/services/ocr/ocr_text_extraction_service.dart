import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

import 'hocr_parser.dart';

class OcrExtractionException implements Exception {
  const OcrExtractionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Runs offline OCR over one already-rasterized page image and returns its
/// recognized words with real pixel-space bounding boxes (via Tesseract's
/// hOCR output, see `hocr_parser.dart`) - the input every searchable-PDF
/// builder in P0-7 is built on. A real platform-channel call
/// (`flutter_tesseract_ocr`, wrapping `TessBaseAPI` natively) with no
/// implementation under `flutter test`, the same standing limitation as
/// `Printing.raster`/`read_pdf_text`/Whisper transcription (R-32 and
/// successors) - [FakeOcrTextExtractionService] below is what every
/// controller/service test in this feature runs against instead.
abstract class OcrTextExtractionService {
  /// [language] is a Tesseract language code (`'eng'`) whose `.traineddata`
  /// file must already exist in `FlutterTesseractOcr.getTessdataPath()` -
  /// callers must verify this themselves before calling (see
  /// `SearchablePdfBuilderService`'s own doc comment for why: the native
  /// plugin does not fail cleanly for a missing model, so this app never
  /// relies on it to).
  Future<List<OcrWord>> extractWords(String imagePath, {required String language});
}

class TesseractOcrTextExtractionService implements OcrTextExtractionService {
  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) async {
    try {
      final hocr = await FlutterTesseractOcr.extractHocr(imagePath, language: language);
      return parseHocrWords(hocr);
    } on PlatformException catch (e) {
      throw OcrExtractionException(e.message ?? 'OCR failed on this page.');
    } catch (e) {
      throw OcrExtractionException('OCR failed on this page: $e');
    }
  }
}

/// Test double - returns canned words per image path (or a fixed default
/// list for any path not explicitly registered), never touches a platform
/// channel. Mirrors `FakePdfTextSearchService`'s exact shape (P0-6).
class FakeOcrTextExtractionService implements OcrTextExtractionService {
  FakeOcrTextExtractionService({List<OcrWord>? defaultWords})
      : defaultWords = defaultWords ?? const [OcrWord(text: 'Sample', x0: 10, y0: 10, x1: 100, y1: 40)];

  final List<OcrWord> defaultWords;
  final Map<String, List<OcrWord>> wordsByPath = {};
  final Map<String, OcrExtractionException> throwForPath = {};

  /// How many times [extractWords] has actually been called - lets tests
  /// assert OCR was skipped for pages that already had real searchable
  /// text (scenario 26).
  int callCount = 0;

  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) async {
    callCount++;
    final failure = throwForPath[imagePath];
    if (failure != null) throw failure;
    return wordsByPath[imagePath] ?? defaultWords;
  }
}
