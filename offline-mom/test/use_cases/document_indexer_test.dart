import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/document_indexer.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late DocumentRepository documentRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
  });

  tearDown(() => db.close());

  DocumentIndexer buildIndexer({FakeEmbeddingEngine? embeddingEngine}) {
    return DocumentIndexer(
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
  }

  Future<int> insertDocument({String? extractedText}) {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'Report',
        originalFilename: 'report.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/report.pdf',
        status: DocumentStatus.ready,
        createdAt: now,
        updatedAt: now,
        extractedText: extractedText,
      ),
    );
  }

  test('indexes a document\'s extracted text and marks it ready', () async {
    final documentId = await insertDocument(
      extractedText: 'The quarterly numbers improved across every region. '
          'Leadership approved the new budget for next year.',
    );

    await buildIndexer()(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.ready);
    expect(document.errorMessage, isNull);

    final chunks = await knowledgeChunkRepository.getForDocument(documentId);
    expect(chunks, isNotEmpty);
    for (final chunk in chunks) {
      expect(chunk.embedding, isNotEmpty);
    }
  });

  test('re-indexing replaces previous chunks rather than duplicating them',
      () async {
    final documentId = await insertDocument(extractedText: 'Original text content here.');
    final indexer = buildIndexer();

    await indexer(documentId);
    final firstPassCount = (await knowledgeChunkRepository.getForDocument(documentId)).length;

    await indexer(documentId);
    final secondPassCount = (await knowledgeChunkRepository.getForDocument(documentId)).length;

    expect(secondPassCount, firstPassCount);
  });

  test('does nothing when the document has no extracted text', () async {
    final documentId = await insertDocument();

    await buildIndexer()(documentId);

    expect(await knowledgeChunkRepository.getForDocument(documentId), isEmpty);
    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.ready); // unchanged
  });

  test('embedding failure marks the document as error and persists no '
      'chunks', () async {
    final documentId = await insertDocument(extractedText: 'Some real text to index.');

    await buildIndexer(
      embeddingEngine: FakeEmbeddingEngine(errorToThrow: Exception('embedding crashed')),
    )(documentId);

    final document = await documentRepository.getById(documentId);
    expect(document!.status, DocumentStatus.error);
    expect(document.errorMessage, contains('embedding crashed'));
    expect(await knowledgeChunkRepository.getForDocument(documentId), isEmpty);
  });

  test('does nothing for an unknown document id', () async {
    await buildIndexer()(9999); // should not throw
  });
}
