import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/document_indexer.dart';
import 'package:offline_mom/features/documents/extract_document_text_use_case.dart';
import 'package:offline_mom/features/documents/retry_document_processing_use_case.dart';
import 'package:offline_mom/features/documents/summarize_document_use_case.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/summary.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/services/ai/chunked_summarization_service.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/documents/document_text_extraction_service.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

class _FakeExtractor implements DocumentTextExtractionService {
  _FakeExtractor({this.result});

  @override
  DocumentSourceType get supportedSourceType => DocumentSourceType.pdf;
  final String? result;

  @override
  Future<String?> extractText(String filePath) async => result;
}

void main() {
  late Database db;
  late DocumentRepository documentRepository;
  late SummaryRepository summaryRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
  });

  tearDown(() => db.close());

  RetryDocumentProcessingUseCase buildUseCase({
    String? extractedText = 'Retried extraction text.',
    FakeLlmEngine? llmEngine,
    FakeEmbeddingEngine? embeddingEngine,
  }) {
    final extract = ExtractDocumentTextUseCase(
      documentRepository: documentRepository,
      extractors: {DocumentSourceType.pdf: _FakeExtractor(result: extractedText)},
    );
    final summarize = SummarizeDocumentUseCase(
      documentRepository: documentRepository,
      summaryRepository: summaryRepository,
      chunkedSummarizationService: ChunkedSummarizationService(
        llmEngine: llmEngine ?? FakeLlmEngine(),
        llmRequestQueue: DefaultLlmRequestQueue(),
      ),
    );
    final indexer = DocumentIndexer(
      documentRepository: documentRepository,
      indexingService: DefaultIndexingService(
        chunkingService: const DefaultChunkingService(),
        embeddingEngine: embeddingEngine ?? FakeEmbeddingEngine(),
        vectorStore: BruteForceVectorStore(
          knowledgeChunkRepository: knowledgeChunkRepository,
        ),
        knowledgeChunkRepository: knowledgeChunkRepository,
      ),
    );
    return RetryDocumentProcessingUseCase(
      documentRepository: documentRepository,
      summaryRepository: summaryRepository,
      extractDocumentTextUseCase: extract,
      summarizeDocumentUseCase: summarize,
      documentIndexer: indexer,
    );
  }

  Future<int> insertDocument({
    DocumentStatus status = DocumentStatus.error,
    String? extractedText,
    String? errorMessage = 'AI summary failed: boom',
  }) {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'Retry me',
        originalFilename: 'doc.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/doc.pdf',
        status: status,
        createdAt: now,
        updatedAt: now,
        extractedText: extractedText,
        errorMessage: errorMessage,
      ),
    );
  }

  test(
      'when text was already extracted, retries summarization then '
      'indexing', () async {
    final documentId = await insertDocument(
      extractedText: 'Already-extracted text.',
    );

    await buildUseCase()(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.ready);
    // Extraction was skipped, so the original text is untouched, not
    // overwritten by the fake extractor's "Retried extraction text.".
    expect(document.extractedText, 'Already-extracted text.');
    expect(await summaryRepository.getForDocument(documentId), isNotNull);
    expect(await knowledgeChunkRepository.getForDocument(documentId), isNotEmpty);
  });

  test(
      'when no text exists yet, retries extraction, summarization, then '
      'indexing', () async {
    final documentId = await insertDocument();

    await buildUseCase()(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.ready);
    expect(document.extractedText, 'Retried extraction text.');
    expect(await summaryRepository.getForDocument(documentId), isNotNull);
    expect(await knowledgeChunkRepository.getForDocument(documentId), isNotEmpty);
  });

  test('stops after extraction if it fails again, without attempting '
      'summarization or indexing', () async {
    final documentId = await insertDocument();

    await buildUseCase(extractedText: null)(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(await summaryRepository.getForDocument(documentId), isNull);
    expect(await knowledgeChunkRepository.getForDocument(documentId), isEmpty);
  });

  test(
      'when text and a summary already exist (only indexing failed '
      'before), retries only indexing - summarization is not repeated',
      () async {
    final documentId = await insertDocument(
      extractedText: 'Already-extracted text.',
    );
    await summaryRepository.insert(
      Summary(
        id: null,
        documentId: documentId,
        summaryText: 'Existing summary from before the indexing failure.',
        minutesOfMeeting: '',
        keyTopics: const [],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 1, 1, 11),
      ),
    );

    await buildUseCase()(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.ready);
    // Exactly one summary exists - retry must not have called
    // SummarizeDocumentUseCase again and inserted a second, duplicate row.
    final summaryRows = await db.query('summaries', where: 'document_id = ?', whereArgs: [documentId]);
    expect(summaryRows, hasLength(1));
    expect(summaryRows.single['summary_text'], 'Existing summary from before the indexing failure.');
    expect(await knowledgeChunkRepository.getForDocument(documentId), isNotEmpty);
  });
}
