import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/extract_document_text_use_case.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/services/documents/document_text_extraction_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

class _FakeExtractor implements DocumentTextExtractionService {
  _FakeExtractor(this.supportedSourceType, {this.result, this.errorToThrow});

  @override
  final DocumentSourceType supportedSourceType;
  final String? result;
  final Object? errorToThrow;

  @override
  Future<String?> extractText(String filePath) async {
    if (errorToThrow != null) throw errorToThrow!;
    return result;
  }
}

void main() {
  late Database db;
  late DocumentRepository documentRepository;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertDocument({
    DocumentSourceType sourceType = DocumentSourceType.pdf,
  }) {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'Report',
        originalFilename: 'report.${sourceType.name}',
        sourceType: sourceType,
        mimeType: sourceType.mimeType,
        fileSizeBytes: 100,
        filePath: '/tmp/report.${sourceType.name}',
        status: DocumentStatus.created,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  ExtractDocumentTextUseCase buildUseCase(
    Map<DocumentSourceType, DocumentTextExtractionService> extractors,
  ) {
    return ExtractDocumentTextUseCase(
      documentRepository: documentRepository,
      extractors: extractors,
    );
  }

  test('extracts text successfully and advances the document to summarizing',
      () async {
    final documentId = await insertDocument();
    final useCase = buildUseCase({
      DocumentSourceType.pdf: _FakeExtractor(
        DocumentSourceType.pdf,
        result: 'The extracted body.',
      ),
    });

    await useCase(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.summarizing);
    expect(document.extractedText, 'The extracted body.');
    expect(document.errorMessage, isNull);
  });

  test('a null extraction result (no readable text) marks the document as '
      'error with a diagnosable message', () async {
    final documentId = await insertDocument();
    final useCase = buildUseCase({
      DocumentSourceType.pdf: _FakeExtractor(DocumentSourceType.pdf, result: null),
    });

    await useCase(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(document.extractedText, isNull);
    expect(document.errorMessage, contains('No readable text'));
  });

  test('a parser exception marks the document as error and persists no text',
      () async {
    final documentId = await insertDocument();
    final useCase = buildUseCase({
      DocumentSourceType.pdf: _FakeExtractor(
        DocumentSourceType.pdf,
        errorToThrow: Exception('corrupted file'),
      ),
    });

    await useCase(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(document.extractedText, isNull);
    expect(document.errorMessage, contains('corrupted file'));
  });

  test('a missing extractor for the document\'s source type fails loudly '
      'instead of throwing an unguarded null-check error', () async {
    final documentId = await insertDocument(sourceType: DocumentSourceType.docx);
    // Only a pdf extractor registered - docx is missing.
    final useCase = buildUseCase({
      DocumentSourceType.pdf: _FakeExtractor(DocumentSourceType.pdf, result: 'x'),
    });

    await useCase(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(document.errorMessage, contains('No text extractor'));
  });

  test('does nothing for an unknown document id', () async {
    final useCase = buildUseCase({
      DocumentSourceType.pdf: _FakeExtractor(DocumentSourceType.pdf, result: 'x'),
    });

    await useCase(9999); // should not throw
  });

  test('handles extraction of a very large text body', () async {
    final documentId = await insertDocument();
    final largeText = 'sentence. ' * 100000;
    final useCase = buildUseCase({
      DocumentSourceType.pdf: _FakeExtractor(DocumentSourceType.pdf, result: largeText),
    });

    await useCase(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.extractedText!.length, largeText.length);
    expect(document.status, DocumentStatus.summarizing);
  });
}
