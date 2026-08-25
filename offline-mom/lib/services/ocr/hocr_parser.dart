/// Parses Tesseract's hOCR output (the HTML-based OCR format returned by
/// `TessBaseAPI.getHOCRText()`, confirmed by reading
/// `flutter_tesseract_ocr`'s own Android plugin source -
/// `FlutterTesseractOcrPlugin.java` calls `getHOCRText(0)` for
/// `extractHocr`, a real native capability the plugin's own public
/// documentation doesn't mention) into word-level bounding boxes, in the
/// OCR'd image's own pixel coordinate space (top-left origin, matching
/// hOCR's own convention).
///
/// This is the one piece of P0-7's OCR pipeline that genuinely needs no
/// native platform channel at all - pure string parsing, fully
/// unit-testable against real hOCR fixtures without a device, the same
/// "pull the pure logic out of the untestable I/O shell" discipline this
/// codebase already applies to `ModelDownloadService`'s Range-header/
/// validator logic and `PdfPageRenderingService`'s JPEG-encode step.
library;

/// One recognized word, with its pixel-space bounding box on the source
/// image (`x0,y0` top-left, `x1,y1` bottom-right) - the real per-word
/// alignment data `extractText`'s flat-string API discards.
class OcrWord {
  const OcrWord({
    required this.text,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });

  final String text;
  final int x0;
  final int y0;
  final int x1;
  final int y1;

  int get width => x1 - x0;
  int get height => y1 - y0;
}

final RegExp _wordPattern = RegExp(
  r"""<span class=['"]ocrx_word['"][^>]*title=['"]bbox (\d+) (\d+) (\d+) (\d+)[^'"]*['"][^>]*>(.*?)</span>""",
  dotAll: true,
);
final RegExp _innerTagPattern = RegExp('<[^>]+>');

/// Extracts every `ocrx_word` span from [hocr] - Tesseract's per-word
/// output. Words with empty/whitespace-only text (a common Tesseract
/// hOCR artifact - a bounding box detected with no confidently recognized
/// glyph inside it) are dropped; they carry no searchable content and
/// would only add invisible-text noise with nothing to search for.
List<OcrWord> parseHocrWords(String hocr) {
  final words = <OcrWord>[];
  for (final match in _wordPattern.allMatches(hocr)) {
    final rawText = match.group(5) ?? '';
    final text = _unescapeHtml(rawText.replaceAll(_innerTagPattern, '')).trim();
    if (text.isEmpty) continue;
    words.add(
      OcrWord(
        text: text,
        x0: int.parse(match.group(1)!),
        y0: int.parse(match.group(2)!),
        x1: int.parse(match.group(3)!),
        y1: int.parse(match.group(4)!),
      ),
    );
  }
  return words;
}

/// Joins [words] into a flat, human-readable string (line-aware: a word
/// whose top is well below the previous word's bottom starts a new line) -
/// used wherever a plain-text view of the page is needed (search-index
/// text, "no searchable text found" detection) without a second native
/// OCR call.
String hocrWordsToPlainText(List<OcrWord> words) {
  if (words.isEmpty) return '';
  final buffer = StringBuffer(words.first.text);
  for (var i = 1; i < words.length; i++) {
    final prev = words[i - 1];
    final word = words[i];
    final newLine = word.y0 > prev.y1;
    buffer.write(newLine ? '\n' : ' ');
    buffer.write(word.text);
  }
  return buffer.toString();
}

String _unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'");
