// Tests ImportResumeUseCase (lib/features/career/resume/import_resume_use_case.dart)
// against real repositories (openTestDatabase()) and the real, unmodified
// DocumentTextExtractionService implementations already shipped for the
// Documents feature - DocxParser/TextMarkdownParser run for real against
// files written to a temp directory; PdfParser's underlying `read_pdf_text`
// plugin channel is mocked, mirroring pdf_parser_test.dart's own precedent
// (there is no pure-Dart PDF fixture path that reaches it otherwise).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/import_resume_use_case.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/documents/document_text_extraction_service.dart';
import 'package:offline_mom/services/documents/parsers/docx_parser.dart';
import 'package:offline_mom/services/documents/parsers/pdf_parser.dart';
import 'package:offline_mom/services/documents/parsers/text_markdown_parser.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

/// Builds a minimal but structurally valid .docx - mirrors
/// docx_parser_test.dart's own `buildMinimalDocx` helper exactly (no shared
/// test fixture for it exists yet, matching that file's own established
/// per-test-file convention).
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

  late Database db;
  late Directory tempDir;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late ImportResumeUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    tempDir = await Directory.systemTemp.createTemp('resume_import_use_case_test_');
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);

    final extractors = <DocumentSourceType, DocumentTextExtractionService>{
      DocumentSourceType.pdf: PdfParser(),
      DocumentSourceType.docx: DocxParser(),
      DocumentSourceType.txt: TextMarkdownParser(DocumentSourceType.txt),
      DocumentSourceType.markdown: TextMarkdownParser(DocumentSourceType.markdown),
    };

    useCase = ImportResumeUseCase(
      extractors: extractors,
      parser: const ResumeImportParser(),
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      experienceBlockRepository: experienceBlockRepository,
      educationBlockRepository: SqfliteEducationBlockRepository(db),
      projectBlockRepository: SqfliteProjectBlockRepository(db),
      certificationBlockRepository: SqfliteCertificationBlockRepository(db),
      skillEntryRepository: SqfliteSkillEntryRepository(db),
      customSectionBlockRepository: SqfliteCustomSectionBlockRepository(db),
    );
  });

  tearDown(() async {
    mockPdfChannel(null);
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> writeTempFile(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return file.path;
  }

  group('extractAndParse - TXT/Markdown', () {
    test('reads a TXT file and structures its content', () async {
      final path = await writeTempFile(
        'resume.txt',
        'Jane Doe\njane@example.com\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n',
      );

      final draft = await useCase.extractAndParse(path, DocumentSourceType.txt);

      expect(draft.fullName, 'Jane Doe');
      expect(draft.experience, hasLength(1));
    });

    test('reads a Markdown file and structures its content', () async {
      final path = await writeTempFile(
        'resume.md',
        '# Jane Doe\n\nSKILLS\n\nDart, Flutter\n',
      );

      final draft = await useCase.extractAndParse(path, DocumentSourceType.markdown);

      expect(draft.skills.map((s) => s.name), containsAll(['Dart', 'Flutter']));
    });

    test('throws ResumeImportExtractionException for an empty TXT file', () async {
      final path = await writeTempFile('empty.txt', '   \n  \n');

      await expectLater(
        useCase.extractAndParse(path, DocumentSourceType.txt),
        throwsA(isA<ResumeImportExtractionException>()),
      );
    });
  });

  group('extractAndParse - DOCX', () {
    test('reads a real DOCX file and structures its paragraphs', () async {
      final file = File('${tempDir.path}/resume.docx');
      await file.writeAsBytes(_buildMinimalDocx([
        'Jane Doe',
        'EXPERIENCE',
        'Engineer - Acme Corp',
        '2020 - 2021',
        '- Did the thing.',
      ]));

      final draft = await useCase.extractAndParse(file.path, DocumentSourceType.docx);

      expect(draft.fullName, 'Jane Doe');
      expect(draft.experience, hasLength(1));
      expect(draft.experience.single.company, 'Acme Corp');
    });

    test('throws DocxReadException (propagated unchanged) for a malformed DOCX', () async {
      final file = File('${tempDir.path}/bad.docx');
      await file.writeAsBytes(utf8.encode('not a zip at all'));

      await expectLater(
        useCase.extractAndParse(file.path, DocumentSourceType.docx),
        throwsA(isA<DocxReadException>()),
      );
    });
  });

  group('extractAndParse - PDF (mocked plugin channel)', () {
    test('reads single-page PDF text via the plugin and structures it', () async {
      mockPdfChannel((call) async => 'Jane Doe\n\nSKILLS\n\nDart, SQL\n');

      final draft = await useCase.extractAndParse('/fake/resume.pdf', DocumentSourceType.pdf);

      expect(draft.fullName, 'Jane Doe');
      expect(draft.skills.map((s) => s.name), containsAll(['Dart', 'SQL']));
    });

    test('reading order is preserved across a multi-page PDF\'s concatenated '
        'text (the plugin exposes no per-page boundary, matching PdfParser\'s '
        'own established behavior)', () async {
      mockPdfChannel((call) async =>
          'Jane Doe\n\n'
          'EXPERIENCE\n\n'
          'First Role - First Co\n2018 - 2019\n- Page one bullet.\n\n'
          'Second Role - Second Co\n2019 - 2020\n- Page two bullet.\n\n'
          'EDUCATION\n\n'
          'B.S. Computer Science - State University\n2016 - 2020\n');

      final draft = await useCase.extractAndParse('/fake/multipage.pdf', DocumentSourceType.pdf);

      expect(draft.experience, hasLength(2));
      expect(draft.experience[0].role, 'First Role');
      expect(draft.experience[1].role, 'Second Role');
      expect(draft.education, hasLength(1));
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

    test('throws ResumeImportExtractionException with a scanned-document '
        'message when the PDF has no extractable text', () async {
      mockPdfChannel((call) async => '   ');

      await expectLater(
        useCase.extractAndParse('/fake/scanned.pdf', DocumentSourceType.pdf),
        throwsA(
          isA<ResumeImportExtractionException>()
              .having((e) => e.message, 'message', contains('scanned')),
        ),
      );
    });
  });

  test('extractAndParse throws for an unregistered source type', () async {
    final noExtractorsUseCase = ImportResumeUseCase(
      extractors: const {},
      parser: const ResumeImportParser(),
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      experienceBlockRepository: experienceBlockRepository,
      educationBlockRepository: SqfliteEducationBlockRepository(db),
      projectBlockRepository: SqfliteProjectBlockRepository(db),
      certificationBlockRepository: SqfliteCertificationBlockRepository(db),
      skillEntryRepository: SqfliteSkillEntryRepository(db),
      customSectionBlockRepository: SqfliteCustomSectionBlockRepository(db),
    );

    await expectLater(
      noExtractorsUseCase.extractAndParse('/fake/resume.txt', DocumentSourceType.txt),
      throwsA(isA<ResumeImportExtractionException>()),
    );
  });

  group('confirmImport', () {
    test('creates a Resume row with the draft\'s profile fields', () async {
      final draft = await useCase.extractAndParse(
        await writeTempFile('r.txt', 'Jane Doe\njane@example.com\n'),
        DocumentSourceType.txt,
      );

      final resumeId = await useCase.confirmImport(draft, title: 'My Imported Resume');

      final resume = await resumeRepository.getById(resumeId);
      expect(resume, isNotNull);
      expect(resume!.title, 'My Imported Resume');
      expect(resume.fullName, 'Jane Doe');
      expect(resume.email, 'jane@example.com');
    });

    test('inserts and attaches every detected block type, reachable through '
        'the existing ResumeBlockRepository/library repositories - identical '
        'to a resume built by hand', () async {
      final draft = await useCase.extractAndParse(
        await writeTempFile(
          'full.txt',
          'Jane Doe\n\n'
          'EXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n\n'
          'EDUCATION\n\nB.S. CS - State University\n2016 - 2020\n\n'
          'PROJECTS\n\nNotes App\n\n'
          'CERTIFICATIONS\n\nAWS Cert - Amazon\n2022\n\n'
          'SKILLS\n\nDart, SQL\n',
        ),
        DocumentSourceType.txt,
      );

      final resumeId = await useCase.confirmImport(draft, title: 'Full Import');

      final refs = await resumeBlockRepository.getForResume(resumeId);
      final typesPresent = refs.map((r) => r.blockType).toSet();
      expect(
        typesPresent,
        containsAll([
          ResumeBlockType.experience,
          ResumeBlockType.education,
          ResumeBlockType.project,
          ResumeBlockType.certification,
          ResumeBlockType.skill,
        ]),
      );

      final storedExperience = await experienceBlockRepository.getById(
        refs.firstWhere((r) => r.blockType == ResumeBlockType.experience).blockId,
      );
      expect(storedExperience!.role, 'Engineer');
    });

    test('a draft with no structured content still creates a resume with '
        'just the detected name and no blocks', () async {
      final draft = await useCase.extractAndParse(
        await writeTempFile('minimal.txt', 'Jane Doe\n'),
        DocumentSourceType.txt,
      );

      final resumeId = await useCase.confirmImport(draft, title: 'Minimal');

      expect(await resumeBlockRepository.getForResume(resumeId), isEmpty);
      final resume = await resumeRepository.getById(resumeId);
      expect(resume!.fullName, 'Jane Doe');
    });

    test('a resume with no detected name persists with an empty fullName, '
        'never a fabricated one', () async {
      final draft = await useCase.extractAndParse(
        await writeTempFile('nodetect.txt', '1234567890 not a name line at all'),
        DocumentSourceType.txt,
      );

      final resumeId = await useCase.confirmImport(draft, title: 'No Name Detected');

      final resume = await resumeRepository.getById(resumeId);
      expect(resume!.fullName, '');
    });
  });
}
