import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/documents/parsers/docx_parser.dart';

/// Builds a minimal but structurally valid .docx: a zip containing only
/// `word/document.xml` with the given paragraph texts. Real .docx files
/// also contain `[Content_Types].xml`/`_rels/` etc., but [DocxParser] only
/// ever reads `word/document.xml`, so this is sufficient to exercise it
/// without a fixture binary checked into the repo.
List<int> buildMinimalDocx(List<String> paragraphs) {
  final paragraphXml = paragraphs
      .map((text) => '<w:p><w:r><w:t>${_escape(text)}</w:t></w:r></w:p>')
      .join();
  final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$paragraphXml</w:body>'
      '</w:document>';

  final archive = Archive()
    ..addFile(
      ArchiveFile('word/document.xml', documentXml.length, utf8.encode(documentXml)),
    );
  return ZipEncoder().encode(archive);
}

String _escape(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

void main() {
  late Directory tempDir;
  late DocxParser parser;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docx_parser_test_');
    parser = DocxParser();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('extracts paragraph text from a valid DOCX', () async {
    final file = File('${tempDir.path}/doc.docx');
    await file.writeAsBytes(buildMinimalDocx(['Hello world', 'Second paragraph']));

    final text = await parser.extractText(file.path);

    expect(text, contains('Hello world'));
    expect(text, contains('Second paragraph'));
  });

  test('skips empty paragraphs', () async {
    final file = File('${tempDir.path}/doc.docx');
    await file.writeAsBytes(buildMinimalDocx(['Only content', '', '   ']));

    final text = await parser.extractText(file.path);

    expect(text, 'Only content');
  });

  test('preserves an interior blank paragraph as a blank line (beta '
      'data-fidelity fix - real .docx resumes separate entries like '
      'consecutive Projects with a blank spacing paragraph, and '
      'ResumeImportParser needs that blank line to tell entries apart)',
      () async {
    final file = File('${tempDir.path}/doc.docx');
    await file.writeAsBytes(buildMinimalDocx(['First entry', '', 'Second entry']));

    final text = await parser.extractText(file.path);

    final lines = text!.split('\n');
    final firstIndex = lines.indexOf('First entry');
    final secondIndex = lines.indexOf('Second entry');
    expect(firstIndex, greaterThanOrEqualTo(0));
    expect(secondIndex, greaterThan(firstIndex));
    // At least one genuinely blank line separates them - not merged onto
    // adjacent lines with no boundary at all.
    expect(lines.sublist(firstIndex + 1, secondIndex).any((l) => l.trim().isEmpty), isTrue);
  });

  test('returns null when every paragraph is empty', () async {
    final file = File('${tempDir.path}/doc.docx');
    await file.writeAsBytes(buildMinimalDocx(['', '  ']));

    expect(await parser.extractText(file.path), isNull);
  });

  test('throws DocxReadException for a file that is not a zip at all',
      () async {
    final file = File('${tempDir.path}/not_a_docx.docx');
    await file.writeAsBytes(utf8.encode('this is plainly not a zip archive'));

    await expectLater(
      parser.extractText(file.path),
      throwsA(isA<DocxReadException>()),
    );
  });

  test(
      'throws DocxReadException for a zip that is missing word/document.xml',
      () async {
    final archive = Archive()
      ..addFile(ArchiveFile('README.txt', 5, utf8.encode('hello')));
    final file = File('${tempDir.path}/wrong_zip.docx');
    await file.writeAsBytes(ZipEncoder().encode(archive));

    await expectLater(
      parser.extractText(file.path),
      throwsA(isA<DocxReadException>()),
    );
  });

  test('handles a document with many paragraphs without truncation',
      () async {
    final paragraphs = List.generate(2000, (i) => 'Paragraph number $i.');
    final file = File('${tempDir.path}/large.docx');
    await file.writeAsBytes(buildMinimalDocx(paragraphs));

    final text = await parser.extractText(file.path);

    expect(text, contains('Paragraph number 0.'));
    expect(text, contains('Paragraph number 1999.'));
  });
}
