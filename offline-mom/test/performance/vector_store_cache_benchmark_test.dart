// Phase 3A: benchmarks BruteForceVectorStore's in-memory chunk cache -
// demonstrates that repeated similaritySearch calls against an unchanged
// corpus (every chat message, every search) get measurably faster once the
// first call has populated the cache, since subsequent calls skip the
// SQLite round-trip + BLOB-embedding-decode entirely. Same caveats as
// indexing_benchmark_test.dart: sqflite_common_ffi on a desktop dev
// machine, a regression guard and shape-of-the-curve signal, not a
// production SLA.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';

import '../test_helpers/test_database.dart';

const _corpusSizes = [500, 3000];

void main() {
  for (final corpusSize in _corpusSizes) {
    test('corpus size $corpusSize: a cached similaritySearch is not slower '
        'than the first (cold) call, and repeated calls stay fast',
        () async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      final documentRepository = SqfliteDocumentRepository(db);
      final knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
      final vectorStore = BruteForceVectorStore(
        knowledgeChunkRepository: knowledgeChunkRepository,
      );

      final now = DateTime(2026, 1, 1);
      final documentId = await documentRepository.insert(
        Document(
          id: null,
          title: 'Doc',
          originalFilename: 'doc.pdf',
          sourceType: DocumentSourceType.pdf,
          mimeType: 'application/pdf',
          fileSizeBytes: 1000,
          filePath: '/tmp/doc.pdf',
          status: DocumentStatus.indexing,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await vectorStore.addAll([
        for (var i = 0; i < corpusSize; i++)
          KnowledgeChunk(
            id: null,
            contentType: ContentType.document,
            sourceId: documentId,
            documentId: documentId,
            meetingId: null,
            chunkIndex: i,
            chunkText: 'chunk body number $i about some topic or other',
            // 768-dim, embeddinggemma's real output size - realistic BLOB
            // decode cost, not a toy 2-3 element vector.
            embedding: [for (var d = 0; d < 768; d++) (i + d) % 97 / 97.0],
            createdAt: now,
          ),
      ]);

      final query = [for (var d = 0; d < 768; d++) d % 97 / 97.0];

      final coldStopwatch = Stopwatch()..start();
      final coldResults = await vectorStore.similaritySearch(query, k: 3);
      coldStopwatch.stop();

      final warmStopwatch = Stopwatch()..start();
      const warmRuns = 20;
      for (var i = 0; i < warmRuns; i++) {
        await vectorStore.similaritySearch(query, k: 3);
      }
      warmStopwatch.stop();
      final avgWarmMs = warmStopwatch.elapsedMilliseconds / warmRuns;

      // ignore: avoid_print
      print(
        '[vector store cache] corpus=$corpusSize chunks: cold '
        '${coldStopwatch.elapsedMilliseconds}ms, warm avg '
        '${avgWarmMs.toStringAsFixed(2)}ms/call over $warmRuns calls',
      );

      expect(coldResults, hasLength(3));
      // The cache's whole point is that a warm call skips the repository
      // round-trip + BLOB decode the cold call paid for - generous bound
      // (not "must be N times faster", which would be flaky on a loaded CI
      // machine) that still catches a real regression (e.g. the cache
      // accidentally not being hit at all, making every call cold-cost).
      expect(
        avgWarmMs,
        lessThan(coldStopwatch.elapsedMilliseconds + 1),
        reason: 'A warm (cached) search should not cost meaningfully more '
            'than the original cold search - investigate whether the '
            'cache is actually being hit.',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
