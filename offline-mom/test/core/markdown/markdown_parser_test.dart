import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/markdown/markdown_parser.dart';

void main() {
  group('parseMarkdownBlocks', () {
    test('a plain sentence becomes one paragraph', () {
      final blocks = parseMarkdownBlocks('Just a plain answer.');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<ParagraphBlock>());
      expect((blocks.single as ParagraphBlock).text, 'Just a plain answer.');
    });

    test('consecutive lines join into one paragraph', () {
      final blocks = parseMarkdownBlocks('Line one\nline two');
      expect(blocks, hasLength(1));
      expect((blocks.single as ParagraphBlock).text, 'Line one line two');
    });

    test('a blank line separates two paragraphs', () {
      final blocks = parseMarkdownBlocks('First paragraph.\n\nSecond paragraph.');
      expect(blocks, hasLength(2));
      expect((blocks[0] as ParagraphBlock).text, 'First paragraph.');
      expect((blocks[1] as ParagraphBlock).text, 'Second paragraph.');
    });

    test('headings at every level', () {
      final blocks = parseMarkdownBlocks('# Title\n## Subtitle\n### Section');
      expect(blocks, hasLength(3));
      expect(blocks[0], isA<HeadingBlock>());
      expect((blocks[0] as HeadingBlock).level, 1);
      expect((blocks[0] as HeadingBlock).text, 'Title');
      expect((blocks[1] as HeadingBlock).level, 2);
      expect((blocks[2] as HeadingBlock).level, 3);
    });

    test('a fenced code block with a language tag', () {
      final blocks = parseMarkdownBlocks('```dart\nvoid main() {}\n```');
      expect(blocks, hasLength(1));
      final code = blocks.single as CodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'void main() {}');
    });

    test('a fenced code block with no language tag', () {
      final blocks = parseMarkdownBlocks('```\nplain code\n```');
      final code = blocks.single as CodeBlock;
      expect(code.language, isNull);
      expect(code.code, 'plain code');
    });

    test('an unterminated code fence still yields a CodeBlock (no crash)', () {
      final blocks = parseMarkdownBlocks('```\nunterminated');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<CodeBlock>());
    });

    test('a bullet list groups consecutive items', () {
      final blocks = parseMarkdownBlocks('- one\n- two\n- three');
      expect(blocks, hasLength(1));
      final list = blocks.single as BulletListBlock;
      expect(list.items, ['one', 'two', 'three']);
    });

    test('a numbered list groups consecutive items', () {
      final blocks = parseMarkdownBlocks('1. first\n2. second');
      final list = blocks.single as NumberedListBlock;
      expect(list.items, ['first', 'second']);
    });

    test('a blockquote joins its lines', () {
      final blocks = parseMarkdownBlocks('> line one\n> line two');
      final quote = blocks.single as BlockQuoteBlock;
      expect(quote.text, 'line one\nline two');
    });

    test('a basic GFM table', () {
      final blocks = parseMarkdownBlocks(
        '| Name | Age |\n| --- | --- |\n| Alice | 30 |\n| Bob | 25 |',
      );
      expect(blocks, hasLength(1));
      final table = blocks.single as TableBlock;
      expect(table.headers, ['Name', 'Age']);
      expect(table.rows, [
        ['Alice', '30'],
        ['Bob', '25'],
      ]);
    });

    test('a heading, paragraph, list and code block all in one message', () {
      final blocks = parseMarkdownBlocks(
        '# Steps\n\nDo this first:\n\n- one\n- two\n\n```\ncode here\n```',
      );
      expect(blocks, hasLength(4));
      expect(blocks[0], isA<HeadingBlock>());
      expect(blocks[1], isA<ParagraphBlock>());
      expect(blocks[2], isA<BulletListBlock>());
      expect(blocks[3], isA<CodeBlock>());
    });

    test('empty input yields no blocks', () {
      expect(parseMarkdownBlocks(''), isEmpty);
      expect(parseMarkdownBlocks('   \n  \n'), isEmpty);
    });
  });

  group('parseInline', () {
    test('plain text with no formatting is a single plain span', () {
      final spans = parseInline('just text');
      expect(spans, hasLength(1));
      expect(spans.single.text, 'just text');
      expect(spans.single.style, InlineStyle.plain);
    });

    test('bold text', () {
      final spans = parseInline('this is **bold** text');
      expect(spans.map((s) => (s.text, s.style)), [
        ('this is ', InlineStyle.plain),
        ('bold', InlineStyle.bold),
        (' text', InlineStyle.plain),
      ]);
    });

    test('italic with asterisks and underscores', () {
      expect(parseInline('*a*').single.style, InlineStyle.italic);
      expect(parseInline('_b_').single.style, InlineStyle.italic);
    });

    test('inline code', () {
      final spans = parseInline('use `flutter test` to run tests');
      expect(spans[1].text, 'flutter test');
      expect(spans[1].style, InlineStyle.code);
    });

    test('a link captures its text and url', () {
      final spans = parseInline('see [the docs](https://example.com) for more');
      final link = spans.firstWhere((s) => s.style == InlineStyle.link);
      expect(link.text, 'the docs');
      expect(link.url, 'https://example.com');
    });

    test('multiple formatted spans in one line', () {
      final spans = parseInline('**bold** and `code` and *italic*');
      expect(spans.map((s) => s.style), [
        InlineStyle.bold,
        InlineStyle.plain,
        InlineStyle.code,
        InlineStyle.plain,
        InlineStyle.italic,
      ]);
    });
  });
}
