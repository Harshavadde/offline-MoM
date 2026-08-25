import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ocr/hocr_parser.dart';
import 'package:offline_mom/services/ocr/ocr_page_text_layout.dart';

void main() {
  group('buildInvisibleWordOverlay', () {
    const words = [
      OcrWord(text: 'Hello', x0: 100, y0: 50, x1: 300, y1: 150),
      OcrWord(text: 'World', x0: 320, y0: 50, x1: 500, y1: 150),
    ];

    test('produces one invisible overlay element per word', () {
      final overlay = buildInvisibleWordOverlay(words, 1000, 1300, 150);
      expect(overlay, hasLength(2));
      expect(overlay.every((e) => e.invisible), isTrue);
      expect(overlay.map((e) => e.text), ['Hello', 'World']);
    });

    test('normalizes each word\'s position to a 0..1 fraction of the image dimensions', () {
      final overlay = buildInvisibleWordOverlay(words, 1000, 1300, 150);
      expect(overlay[0].x, 100 / 1000);
      expect(overlay[0].y, 50 / 1300);
    });

    test('font size scales with the word\'s pixel height at the given dpi', () {
      final overlay = buildInvisibleWordOverlay(words, 1000, 1300, 150);
      const expectedPt = (150 - 50) / 150 * 72.0;
      expect(overlay[0].fontSize, closeTo(expectedPt, 0.01));
    });

    test('drops a degenerate zero-area word box', () {
      const degenerate = [OcrWord(text: 'x', x0: 10, y0: 10, x1: 10, y1: 40)];
      expect(buildInvisibleWordOverlay(degenerate, 1000, 1300, 150), isEmpty);
    });

    test('returns empty overlay for an invalid image size', () {
      expect(buildInvisibleWordOverlay(words, 0, 0, 150), isEmpty);
    });

    test('empty word list yields empty overlay', () {
      expect(buildInvisibleWordOverlay(const [], 1000, 1300, 150), isEmpty);
    });
  });

  group('buildEvenlySpacedLineOverlay', () {
    test('produces one invisible overlay line per non-blank line of text', () {
      final overlay = buildEvenlySpacedLineOverlay('First line\nSecond line\n\nThird line', 1000, 1300, 150);
      expect(overlay, hasLength(3));
      expect(overlay.every((e) => e.invisible), isTrue);
      expect(overlay.map((e) => e.text), ['First line', 'Second line', 'Third line']);
    });

    test('spaces lines evenly down the page in order', () {
      final overlay = buildEvenlySpacedLineOverlay('A\nB\nC', 1000, 900, 150);
      expect(overlay[0].y, lessThan(overlay[1].y));
      expect(overlay[1].y, lessThan(overlay[2].y));
    });

    test('blank text yields no overlay', () {
      expect(buildEvenlySpacedLineOverlay('', 1000, 1300, 150), isEmpty);
      expect(buildEvenlySpacedLineOverlay('   \n  ', 1000, 1300, 150), isEmpty);
    });
  });
}
