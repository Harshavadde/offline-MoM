// Benchmarks the Phase 1B retrieval pipeline (DefaultIndexingService +
// BruteForceVectorStore) at the corpus sizes M1.2's acceptance check calls
// for (100/500/1000/3000 "documents"). Uses [FakeEmbeddingEngine]
// (test_helpers/fake_ai_engines.dart), not a real on-device embedding
// model - no real GGUF model can run in this development environment (see
// docs/v2/implementation/spikes/m1-0-embedding-spike.md), so this measures
// the Dart/SQLite-side cost of the pipeline (chunking, batch insert, brute
// -force cosine scan) in isolation from actual model inference latency,
// which can only be measured on a real device. Numbers here are a
// regression guard and a rough shape-of-the-curve signal, not a
// production SLA - same caveat `search_benchmark_test.dart` already
// documents for its own sqflite_common_ffi-on-a-dev-machine numbers.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/retrieval_engine.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

const _corpusSizes = [100, 500, 1000, 3000];

// A representative "document" body: a few paragraphs, enough to produce
// 2-3 chunks each at the default ~900-char target (DefaultChunkingService).
String _sampleText(int seed) {
  final topics = ['budget', 'roadmap', 'staffing', 'vendor', 'launch', 'incident'];
  final topic = topics[seed % topics.length];
  return List.generate(
    6,
    (i) => 'Paragraph $i of document $seed discusses the $topic in detail, '
        'covering timelines, owners, and open risks that need follow-up '
        'before the next review cycle.',
  ).join('\n\n');
}

void main() {
  for (final corpusSize in _corpusSizes) {
    group('corpus size $corpusSize', () {
      test('indexing and retrieval timing', () async {
        final db = await openTestDatabase();
        addTearDown(() => db.close());

        final documentRepository = SqfliteDocumentRepository(db);
        final knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
        final embeddingEngine = FakeEmbeddingEngine();
        final vectorStore = BruteForceVectorStore(
          knowledgeChunkRepository: knowledgeChunkRepository,
        );
        final indexingService = DefaultIndexingService(
          chunkingService: const DefaultChunkingService(),
          embeddingEngine: embeddingEngine,
          vectorStore: vectorStore,
          knowledgeChunkRepository: knowledgeChunkRepository,
        );

        final now = DateTime(2026, 1, 1);
        final documentIds = <int>[];
        for (var i = 0; i < corpusSize; i++) {
          final id = await documentRepository.insert(
            Document(
              id: null,
              title: 'Document $i',
              originalFilename: 'doc_$i.pdf',
              sourceType: DocumentSourceType.pdf,
              mimeType: 'application/pdf',
              fileSizeBytes: 1000,
              filePath: '/tmp/doc_$i.pdf',
              status: DocumentStatus.indexing,
              createdAt: now,
              updatedAt: now,
              extractedText: _sampleText(i),
            ),
          );
          documentIds.add(id);
        }

        final indexingStopwatch = Stopwatch()..start();
        for (var i = 0; i < documentIds.length; i++) {
          await indexingService.indexContent(
            contentType: ContentType.document,
            sourceId: documentIds[i],
            documentId: documentIds[i],
            text: _sampleText(i),
          );
        }
        indexingStopwatch.stop();

        final totalChunks = (await knowledgeChunkRepository.getAll()).length;
        final indexingMs = indexingStopwatch.elapsedMilliseconds;
        final avgPerDocMs = indexingMs / corpusSize;

        // ignore: avoid_print
        print(
          '[indexing] corpus=$corpusSize docs, $totalChunks chunks: '
          '${indexingMs}ms total, ${avgPerDocMs.toStringAsFixed(2)}ms/doc',
        );

        final retrievalEngine = DefaultRetrievalEngine(
          embeddingEngine: embeddingEngine,
          vectorStore: vectorStore,
        );

        final retrievalStopwatch = Stopwatch()..start();
        final results = await retrievalEngine.retrieve('budget roadmap staffing', k: 3);
        retrievalStopwatch.stop();

        // ignore: avoid_print
        print(
          '[retrieval] corpus=$corpusSize docs, $totalChunks chunks: '
          '${retrievalStopwatch.elapsedMilliseconds}ms for top-3, '
          '${results.length} results returned',
        );

        expect(results, isNotEmpty);
        // Generous, CI-machine-appropriate bound (see file doc comment) -
        // a regression guard against brute-force search becoming
        // accidentally much worse than linear, not a production SLA.
        expect(
          retrievalStopwatch.elapsedMilliseconds,
          lessThan(5000),
          reason: 'Retrieval took ${retrievalStopwatch.elapsedMilliseconds}ms '
              'across $totalChunks chunks - investigate before this '
              'regresses further.',
        );
      }, timeout: const Timeout(Duration(minutes: 5)));
    });
  }
}
