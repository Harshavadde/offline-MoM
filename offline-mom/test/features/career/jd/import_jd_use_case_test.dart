// Tests ImportJdUseCase (lib/features/career/jd/import_jd_use_case.dart)
// against the real, unmodified DocumentTextExtractionService
// implementations - mirrors import_resume_use_case_test.dart's exact
// extraction-half pattern. No confirmImport/persistence counterpart exists
// for JD import (see the Batch 8 report), so this file only covers
// extractAndParse.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/jd/import_jd_use_case.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/services/documents/document_text_extraction_service.dart';
import 'package:offline_mom/services/documents/parsers/docx_parser.dart';
import 'package:offline_mom/services/documents/parsers/pdf_parser.dart';
import 'package:offline_mom/services/documents/parsers/text_markdown_parser.dart';
import 'package:offline_mom/services/career/jd_parser.dart';

List<int> _buildMinimalDocx(List<String> paragraphs) {
  final paragraphXml = paragraphs.map((text) => '<w:p><w:r><w:t>${_escape(text)}</w:t></w:r></w:p>').join();
  final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$paragraphXml</w:body>'
      '</w:document>';
  final archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', documentXml.length, utf8.encode(documentXml)));
  return ZipEncoder().encode(archive);
}

String _escape(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pdfChannel = MethodChannel('read_pdf_text');
  void mockPdfChannel(Future<Object?> Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pdfChannel, handler);
  }

  late Directory tempDir;
  late ImportJdUseCase useCase;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jd_import_use_case_test_');
    final extractors = <DocumentSourceType, DocumentTextExtractionService>{
      DocumentSourceType.pdf: PdfParser(),
      DocumentSourceType.docx: DocxParser(),
      DocumentSourceType.txt: TextMarkdownParser(DocumentSourceType.txt),
      DocumentSourceType.markdown: TextMarkdownParser(DocumentSourceType.markdown),
    };
    useCase = ImportJdUseCase(extractors: extractors, parser: const JdParser());
  });

  tearDown(() async {
    mockPdfChannel(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> writeTempFile(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return file.path;
  }

  test('reads a TXT JD and structures its content', () async {
    final path = await writeTempFile(
      'jd.txt',
      'Senior Engineer\n\nREQUIREMENTS\n\n- Python\n- SQL\n',
    );

    final jd = await useCase.extractAndParse(path, DocumentSourceType.txt);

    expect(jd.title, 'Senior Engineer');
    expect(jd.requirements, ['Python', 'SQL']);
  });

  test('reads a Markdown JD and structures its content', () async {
    final path = await writeTempFile('jd.md', 'REQUIREMENTS\n\n- Dart\n- Flutter\n');
    final jd = await useCase.extractAndParse(path, DocumentSourceType.markdown);
    expect(jd.requirements, ['Dart', 'Flutter']);
  });

  test('reads a real DOCX JD and structures its paragraphs', () async {
    final file = File('${tempDir.path}/jd.docx');
    await file.writeAsBytes(_buildMinimalDocx(['REQUIREMENTS', '- Kubernetes', '- Docker']));

    final jd = await useCase.extractAndParse(file.path, DocumentSourceType.docx);

    expect(jd.requirements, ['Kubernetes', 'Docker']);
  });

  test('throws DocxReadException (propagated unchanged) for a malformed DOCX', () async {
    final file = File('${tempDir.path}/bad.docx');
    await file.writeAsBytes(utf8.encode('not a zip'));

    await expectLater(
      useCase.extractAndParse(file.path, DocumentSourceType.docx),
      throwsA(isA<DocxReadException>()),
    );
  });

  test('reads PDF JD text via the mocked plugin channel', () async {
    mockPdfChannel((call) async => 'REQUIREMENTS\n\n- Java\n- Spring\n');

    final jd = await useCase.extractAndParse('/fake/jd.pdf', DocumentSourceType.pdf);

    expect(jd.requirements, ['Java', 'Spring']);
  });

  test('throws PdfReadException (propagated unchanged) for an unreadable PDF', () async {
    mockPdfChannel((call) async {
      throw PlatformException(code: 'PDF_ERROR', message: 'corrupted');
    });

    await expectLater(
      useCase.extractAndParse('/fake/corrupt.pdf', DocumentSourceType.pdf),
      throwsA(isA<PdfReadException>()),
    );
  });

  test('throws JdImportExtractionException with a scanned-document message '
      'when the PDF has no extractable text', () async {
    mockPdfChannel((call) async => '   ');

    await expectLater(
      useCase.extractAndParse('/fake/scanned.pdf', DocumentSourceType.pdf),
      throwsA(
        isA<JdImportExtractionException>().having((e) => e.message, 'message', contains('scanned')),
      ),
    );
  });

  test('throws JdImportExtractionException for an empty TXT file', () async {
    final path = await writeTempFile('empty.txt', '   \n  \n');

    await expectLater(
      useCase.extractAndParse(path, DocumentSourceType.txt),
      throwsA(isA<JdImportExtractionException>()),
    );
  });

  test('throws JdImportExtractionException for an unregistered source type', () async {
    final noExtractorsUseCase = ImportJdUseCase(extractors: const {}, parser: const JdParser());

    await expectLater(
      noExtractorsUseCase.extractAndParse('/fake/jd.txt', DocumentSourceType.txt),
      throwsA(isA<JdImportExtractionException>()),
    );
  });
}
