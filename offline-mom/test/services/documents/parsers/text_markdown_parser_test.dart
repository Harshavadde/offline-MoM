import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/services/documents/parsers/text_markdown_parser.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('text_markdown_parser_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('extracts plain UTF-8 text from a .txt file, trimmed', () async {
    final file = File('${tempDir.path}/notes.txt');
    await file.writeAsString('  Hello, world.\nSecond line.  \n');
    final parser = TextMarkdownParser(DocumentSourceType.txt);

    final text = await parser.extractText(file.path);

    expect(text, 'Hello, world.\nSecond line.');
  });

  test('extracts Markdown content as-is, without stripping formatting syntax',
      () async {
    final file = File('${tempDir.path}/readme.md');
    await file.writeAsString('# Title\n\n- item one\n- item two\n');
    final parser = TextMarkdownParser(DocumentSourceType.markdown);

    final text = await parser.extractText(file.path);

    expect(text, contains('# Title'));
    expect(text, contains('- item one'));
  });

  test('returns null for an empty (whitespace-only) file', () async {
    final file = File('${tempDir.path}/empty.txt');
    await file.writeAsString('   \n\n  ');
    final parser = TextMarkdownParser(DocumentSourceType.txt);

    expect(await parser.extractText(file.path), isNull);
  });

  test('falls back to Latin-1 for a file that is not valid UTF-8', () async {
    final file = File('${tempDir.path}/latin1.txt');
    // 0xE9 alone is invalid UTF-8 but a valid Latin-1 byte (é).
    await file.writeAsBytes(latin1.encode('Café menu'));
    final parser = TextMarkdownParser(DocumentSourceType.txt);

    final text = await parser.extractText(file.path);

    expect(text, 'Café menu');
  });

  test('handles a large text file without truncation', () async {
    final file = File('${tempDir.path}/large.txt');
    final content = 'word ' * 200000;
    await file.writeAsString(content);
    final parser = TextMarkdownParser(DocumentSourceType.txt);

    final text = await parser.extractText(file.path);

    expect(text!.length, content.trim().length);
  });

  test('a missing file surfaces as a thrown exception, not a null result',
      () async {
    final parser = TextMarkdownParser(DocumentSourceType.txt);
    await expectLater(
      parser.extractText('${tempDir.path}/does_not_exist.txt'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
