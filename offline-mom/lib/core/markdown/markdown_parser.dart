/// A small, dependency-free Markdown subset parser for chat messages
/// (Phase 8B.1, Priority 4) - deliberately not a full CommonMark
/// implementation (no nested emphasis, no reference-style links, no
/// ordered-list start-number tracking beyond simple `1.`/`1)` prefixes).
/// It covers what this app's on-device LLM actually produces in practice
/// (paragraphs, headings, fenced code blocks, bullet/numbered lists,
/// blockquotes, basic GFM tables, bold/italic/inline-code/links) without
/// adding a markdown package dependency.
library;

sealed class MarkdownBlock {
  const MarkdownBlock();
}

class HeadingBlock extends MarkdownBlock {
  const HeadingBlock(this.level, this.text);
  final int level;
  final String text;
}

class ParagraphBlock extends MarkdownBlock {
  const ParagraphBlock(this.text);
  final String text;
}

class CodeBlock extends MarkdownBlock {
  const CodeBlock(this.code, {this.language});
  final String code;
  final String? language;
}

class BulletListBlock extends MarkdownBlock {
  const BulletListBlock(this.items);
  final List<String> items;
}

class NumberedListBlock extends MarkdownBlock {
  const NumberedListBlock(this.items);
  final List<String> items;
}

class BlockQuoteBlock extends MarkdownBlock {
  const BlockQuoteBlock(this.text);
  final String text;
}

class TableBlock extends MarkdownBlock {
  const TableBlock(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

final _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
final _bulletPattern = RegExp(r'^[-*+]\s+(.*)$');
final _numberedPattern = RegExp(r'^\d+[.)]\s+(.*)$');
final _blockQuotePattern = RegExp(r'^>\s?(.*)$');
final _tableSeparatorPattern = RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$');

/// Parses [source] into a flat list of top-level blocks, in document
/// order. Never throws - any line that doesn't match a recognized
/// block-level pattern becomes part of a plain [ParagraphBlock].
List<MarkdownBlock> parseMarkdownBlocks(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MarkdownBlock>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    if (line.trimLeft().startsWith('```')) {
      final language = line.trimLeft().substring(3).trim();
      final codeLines = <String>[];
      var j = i + 1;
      while (j < lines.length && !lines[j].trimLeft().startsWith('```')) {
        codeLines.add(lines[j]);
        j++;
      }
      blocks.add(CodeBlock(codeLines.join('\n'), language: language.isEmpty ? null : language));
      i = j + 1;
      continue;
    }

    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      blocks.add(HeadingBlock(heading.group(1)!.length, heading.group(2)!.trim()));
      i++;
      continue;
    }

    if (_looksLikeTableHeader(lines, i)) {
      final headerCells = _splitTableRow(line);
      var j = i + 2;
      final rows = <List<String>>[];
      while (j < lines.length && lines[j].contains('|') && lines[j].trim().isNotEmpty) {
        rows.add(_splitTableRow(lines[j]));
        j++;
      }
      blocks.add(TableBlock(headerCells, rows));
      i = j;
      continue;
    }

    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      final items = <String>[bullet.group(1)!.trim()];
      var j = i + 1;
      while (j < lines.length) {
        final next = _bulletPattern.firstMatch(lines[j]);
        if (next == null) break;
        items.add(next.group(1)!.trim());
        j++;
      }
      blocks.add(BulletListBlock(items));
      i = j;
      continue;
    }

    final numbered = _numberedPattern.firstMatch(line);
    if (numbered != null) {
      final items = <String>[numbered.group(1)!.trim()];
      var j = i + 1;
      while (j < lines.length) {
        final next = _numberedPattern.firstMatch(lines[j]);
        if (next == null) break;
        items.add(next.group(1)!.trim());
        j++;
      }
      blocks.add(NumberedListBlock(items));
      i = j;
      continue;
    }

    final quote = _blockQuotePattern.firstMatch(line);
    if (quote != null) {
      final quoteLines = <String>[quote.group(1)!.trim()];
      var j = i + 1;
      while (j < lines.length) {
        final next = _blockQuotePattern.firstMatch(lines[j]);
        if (next == null) break;
        quoteLines.add(next.group(1)!.trim());
        j++;
      }
      blocks.add(BlockQuoteBlock(quoteLines.join('\n')));
      i = j;
      continue;
    }

    // A plain paragraph: consecutive non-blank lines that don't start a
    // more specific block, joined with a single space (soft-wrap, matching
    // how a chat answer's own line breaks are usually just word-wrap
    // artifacts rather than meaningful paragraph breaks).
    final paragraphLines = <String>[line.trim()];
    var j = i + 1;
    while (j < lines.length &&
        lines[j].trim().isNotEmpty &&
        !lines[j].trimLeft().startsWith('```') &&
        _headingPattern.firstMatch(lines[j]) == null &&
        _bulletPattern.firstMatch(lines[j]) == null &&
        _numberedPattern.firstMatch(lines[j]) == null &&
        _blockQuotePattern.firstMatch(lines[j]) == null) {
      paragraphLines.add(lines[j].trim());
      j++;
    }
    blocks.add(ParagraphBlock(paragraphLines.join(' ')));
    i = j;
  }

  return blocks;
}

bool _looksLikeTableHeader(List<String> lines, int index) {
  if (!lines[index].contains('|')) return false;
  if (index + 1 >= lines.length) return false;
  return _tableSeparatorPattern.hasMatch(lines[index + 1].trim());
}

List<String> _splitTableRow(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
  return trimmed.split('|').map((cell) => cell.trim()).toList();
}

enum InlineStyle { plain, bold, italic, code, link }

class InlineSpanData {
  const InlineSpanData(this.text, this.style, {this.url});
  final String text;
  final InlineStyle style;
  final String? url;
}

final _inlinePattern = RegExp(
  r'\*\*(?<bold>[^*]+?)\*\*'
  r'|`(?<code>[^`]+?)`'
  r'|\*(?<italic1>[^*]+?)\*'
  r'|_(?<italic2>[^_]+?)_'
  r'|\[(?<linktext>[^\]]+?)\]\((?<linkurl>[^)]+?)\)',
);

/// Parses inline emphasis/code/links within a single block's text.
/// Deliberately simple: matches are found left-to-right and never nested
/// (e.g. `**bold with *italic* inside**` renders the outer bold span's
/// literal text rather than nesting styles) - good enough for what an
/// on-device LLM's answers actually contain.
List<InlineSpanData> parseInline(String text) {
  final spans = <InlineSpanData>[];
  var cursor = 0;
  for (final match in _inlinePattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(InlineSpanData(text.substring(cursor, match.start), InlineStyle.plain));
    }
    if (match.namedGroup('bold') case final bold?) {
      spans.add(InlineSpanData(bold, InlineStyle.bold));
    } else if (match.namedGroup('code') case final code?) {
      spans.add(InlineSpanData(code, InlineStyle.code));
    } else if (match.namedGroup('italic1') case final italic1?) {
      spans.add(InlineSpanData(italic1, InlineStyle.italic));
    } else if (match.namedGroup('italic2') case final italic2?) {
      spans.add(InlineSpanData(italic2, InlineStyle.italic));
    } else if (match.namedGroup('linktext') case final linkText?) {
      spans.add(InlineSpanData(linkText, InlineStyle.link, url: match.namedGroup('linkurl')));
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(InlineSpanData(text.substring(cursor), InlineStyle.plain));
  }
  if (spans.isEmpty) spans.add(InlineSpanData(text, InlineStyle.plain));
  return spans;
}
