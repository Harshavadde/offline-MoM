import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/document_indexer.dart';
import 'package:offline_mom/features/documents/extract_document_text_use_case.dart';
import 'package:offline_mom/features/documents/process_new_document_use_case.dart';
import 'package:offline_mom/features/documents/summarize_document_use_case.dart';
import 'package:offline_mom/models/document.dart';
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

  ProcessNewDocumentUseCase buildUseCase({
    String? extractedText = 'Some extracted body text.',
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
    return ProcessNewDocumentUseCase(
      documentRepository: documentRepository,
      extractDocumentTextUseCase: extract,
      summarizeDocumentUseCase: summarize,
      documentIndexer: indexer,
    );
  }

  Future<int> insertDocument() {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'New import',
        originalFilename: 'doc.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/doc.pdf',
        status: DocumentStatus.created,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test(
      'runs extraction, summarization, then indexing end to end for a '
      'fresh import', () async {
    final documentId = await insertDocument();

    await buildUseCase()(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.ready);
    expect(document.extractedText, 'Some extracted body text.');
    expect(await summaryRepository.getForDocument(documentId), isNotNull);
    expect(await knowledgeChunkRepository.getForDocument(documentId), isNotEmpty);
  });

  test('stops after extraction if no text was found, without attempting '
      'summarization or indexing', () async {
    final documentId = await insertDocument();

    await buildUseCase(extractedText: null)(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(await summaryRepository.getForDocument(documentId), isNull);
    expect(await knowledgeChunkRepository.getForDocument(documentId), isEmpty);
  });

  test('stops after summarization if indexing then fails, leaving the '
      'summary intact', () async {
    final documentId = await insertDocument();

    await buildUseCase(
      embeddingEngine: FakeEmbeddingEngine(errorToThrow: Exception('embedding crashed')),
    )(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(document.errorMessage, contains('embedding crashed'));
    // The summary produced before indexing failed is not rolled back.
    expect(await summaryRepository.getForDocument(documentId), isNotNull);
    expect(await knowledgeChunkRepository.getForDocument(documentId), isEmpty);
  });
}
