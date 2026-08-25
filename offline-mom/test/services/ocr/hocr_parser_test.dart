import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ocr/hocr_parser.dart';

const _sampleHocr = '''
<div class='ocr_page' id='page_1' title='bbox 0 0 1000 1300'>
 <div class='ocr_carea' id='block_1_1' title="bbox 34 44 960 200">
  <p class='ocr_par' id='par_1_1' lang='eng' title="bbox 34 44 960 90">
   <span class='ocr_line' id='line_1_1' title="bbox 34 44 460 79">
    <span class='ocrx_word' id='word_1_1' title='bbox 34 44 130 79; x_wconf 96'>Hello</span>
    <span class='ocrx_word' id='word_1_2' title='bbox 140 44 230 79; x_wconf 94'>World</span>
   </span>
   <span class='ocr_line' id='line_1_2' title="bbox 34 100 460 140">
    <span class='ocrx_word' id='word_1_3' title='bbox 34 100 200 140; x_wconf 90'>Second</span>
    <span class='ocrx_word' id='word_1_4' title='bbox 210 100 260 140; x_wconf 10'></span>
   </span>
  </p>
 </div>
</div>
''';

void main() {
  test('extracts every ocrx_word span with its real pixel bounding box', () {
    final words = parseHocrWords(_sampleHocr);
    expect(words.map((w) => w.text), ['Hello', 'World', 'Second']);
    expect(words[0].x0, 34);
    expect(words[0].y0, 44);
    expect(words[0].x1, 130);
    expect(words[0].y1, 79);
    expect(words[1].x0, 140);
  });

  test('drops a word span with empty/whitespace-only recognized text', () {
    final words = parseHocrWords(_sampleHocr);
    expect(words.any((w) => w.text.isEmpty), isFalse);
  });

  test('unescapes common HTML entities in recognized text', () {
    const hocr = '''<span class='ocrx_word' title='bbox 1 2 3 4'>Tom &amp; Jerry&#39;s</span>''';
    final words = parseHocrWords(hocr);
    expect(words.single.text, "Tom & Jerry's");
  });

  test('strips a nested inline tag from a word span rather than including markup as text', () {
    const hocr = '''<span class='ocrx_word' title='bbox 1 2 3 4'><strong>Bold</strong></span>''';
    final words = parseHocrWords(hocr);
    expect(words.single.text, 'Bold');
  });

  test('empty hOCR document yields no words', () {
    expect(parseHocrWords(''), isEmpty);
    expect(parseHocrWords('<div class="ocr_page"></div>'), isEmpty);
  });

  test('OcrWord.width/height are derived correctly from the bounding box', () {
    final words = parseHocrWords(_sampleHocr);
    expect(words[0].width, 130 - 34);
    expect(words[0].height, 79 - 44);
  });

  test('hocrWordsToPlainText joins same-line words with a space and starts a new line on a clear vertical gap', () {
    final words = parseHocrWords(_sampleHocr);
    final text = hocrWordsToPlainText(words);
    expect(text, 'Hello World\nSecond');
  });

  test('hocrWordsToPlainText returns empty string for no words', () {
    expect(hocrWordsToPlainText(const []), '');
  });
}
