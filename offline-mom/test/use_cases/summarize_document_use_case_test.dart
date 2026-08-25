import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/summarize_document_use_case.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/services/ai/chunked_summarization_service.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late DocumentRepository documentRepository;
  late SummaryRepository summaryRepository;
  late int documentId;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);

    final now = DateTime(2026, 1, 1);
    documentId = await documentRepository.insert(
      Document(
        id: null,
        title: 'Report',
        originalFilename: 'report.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/report.pdf',
        status: DocumentStatus.summarizing,
        createdAt: now,
        updatedAt: now,
        extractedText: 'The quarterly numbers improved across every region.',
      ),
    );
  });

  tearDown(() => db.close());

  SummarizeDocumentUseCase buildUseCase({FakeLlmEngine? llmEngine}) {
    return SummarizeDocumentUseCase(
      documentRepository: documentRepository,
      summaryRepository: summaryRepository,
      chunkedSummarizationService: ChunkedSummarizationService(
        llmEngine: llmEngine ?? FakeLlmEngine(),
        llmRequestQueue: DefaultLlmRequestQueue(),
      ),
    );
  }

  test('generates successfully: persists a document-owned summary and marks '
      'the document ready', () async {
    await buildUseCase()(documentId);

    final summary = await summaryRepository.getForDocument(documentId);
    expect(summary, isNotNull);
    expect(summary!.documentId, documentId);
    expect(summary.meetingId, isNull);
    expect(summary.summaryText, 'Default fake summary.');
    expect(summary.keyTopics, ['topic one', 'topic two']);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.ready);
    expect(document.errorMessage, isNull);
  });

  test('engine failure marks the document as error and persists no summary',
      () async {
    await buildUseCase(
      llmEngine: FakeLlmEngine(errorToThrow: Exception('model crashed')),
    )(documentId);

    expect(await summaryRepository.getForDocument(documentId), isNull);
    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(document.errorMessage, contains('model crashed'));
  });

  test('does nothing when the document has no extracted text yet', () async {
    final now = DateTime(2026, 1, 1);
    final noTextId = await documentRepository.insert(
      Document(
        id: null,
        title: 'Not extracted yet',
        originalFilename: 'draft.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/draft.pdf',
        status: DocumentStatus.extracting,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await buildUseCase()(noTextId);

    expect(await summaryRepository.getForDocument(noTextId), isNull);
    final document = await documentRepository.getById(noTextId);
    expect(document!.status, DocumentStatus.extracting);
  });

  test('does nothing for an unknown document id', () async {
    await buildUseCase()(9999); // should not throw
  });
}
