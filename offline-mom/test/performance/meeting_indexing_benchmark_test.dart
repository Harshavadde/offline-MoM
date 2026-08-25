// Benchmarks the Phase 1C meeting-side retrieval pipeline (MeetingIndexer +
// DefaultIndexingService + BruteForceVectorStore) at the corpus sizes the
// Phase 1C PERFORMANCE requirement calls for: 100/500/1000/3000 meetings,
// plus a mixed 1500-meeting + 1500-document workspace. Measures indexing,
// re-indexing, deletion, and retrieval. Same caveats as
// indexing_benchmark_test.dart: FakeEmbeddingEngine (test_helpers/fake_ai_engines.dart)
// stands in for the real on-device embedding model, so these numbers are a
// Dart/SQLite-side regression guard and shape-of-the-curve signal, not a
// production SLA measured on a real device.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/knowledge_chunk_filter.dart';
import 'package:offline_mom/services/retrieval/retrieval_engine.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

const _meetingCorpusSizes = [100, 500, 1000, 3000];

String _sampleTranscript(int seed) {
  final topics = ['budget', 'roadmap', 'staffing', 'vendor', 'launch', 'incident'];
  final topic = topics[seed % topics.length];
  return List.generate(
    6,
    (i) => 'Speaker ${i % 3} discusses the $topic in meeting $seed, '
        'covering timelines, owners, and open risks that need follow-up '
        'before the next review cycle.',
  ).join('\n\n');
}

String _sampleSummary(int seed) {
  final topics = ['budget', 'roadmap', 'staffing', 'vendor', 'launch', 'incident'];
  return 'Summary of meeting $seed: agreed on next steps for '
      '${topics[seed % topics.length]}, with owners assigned and a '
      'follow-up review scheduled.';
}

void main() {
  for (final corpusSize in _meetingCorpusSizes) {
    group('meeting corpus size $corpusSize', () {
      test('indexing, re-indexing, deletion, and retrieval timing', () async {
        final db = await openTestDatabase();
        addTearDown(() => db.close());

        final meetingRepository = SqfliteMeetingRepository(db);
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
        final meetingIds = <int>[];
        for (var i = 0; i < corpusSize; i++) {
          final id = await meetingRepository.insert(
            Meeting(
              id: null,
              title: 'Meeting $i',
              source: MeetingSource.recorded,
              status: MeetingStatus.indexing,
              createdAt: now,
              updatedAt: now,
            ),
          );
          meetingIds.add(id);
        }

        // --- Indexing (transcript + summary per meeting) ---
        final indexingStopwatch = Stopwatch()..start();
        for (var i = 0; i < meetingIds.length; i++) {
          await indexingService.indexContent(
            contentType: ContentType.transcript,
            sourceId: meetingIds[i],
            meetingId: meetingIds[i],
            text: _sampleTranscript(i),
          );
          await indexingService.indexContent(
            contentType: ContentType.summary,
            sourceId: meetingIds[i],
            meetingId: meetingIds[i],
            text: _sampleSummary(i),
          );
        }
        indexingStopwatch.stop();

        final totalChunks = (await knowledgeChunkRepository.getAll()).length;
        final indexingMs = indexingStopwatch.elapsedMilliseconds;
        // ignore: avoid_print
        print(
          '[indexing] corpus=$corpusSize meetings, $totalChunks chunks: '
          '${indexingMs}ms total, ${(indexingMs / corpusSize).toStringAsFixed(2)}ms/meeting',
        );

        // --- Re-indexing (summary regenerated for every meeting) ---
        final reindexStopwatch = Stopwatch()..start();
        for (var i = 0; i < meetingIds.length; i++) {
          await indexingService.indexContent(
            contentType: ContentType.summary,
            sourceId: meetingIds[i],
            meetingId: meetingIds[i],
            text: '${_sampleSummary(i)} (regenerated)',
          );
        }
        reindexStopwatch.stop();
        final chunksAfterReindex = (await knowledgeChunkRepository.getAll()).length;
        // ignore: avoid_print
        print(
          '[re-indexing] corpus=$corpusSize meetings, $chunksAfterReindex '
          'chunks (was $totalChunks - re-indexing a summary must not grow '
          'the transcript\'s chunk count): '
          '${reindexStopwatch.elapsedMilliseconds}ms total, '
          '${(reindexStopwatch.elapsedMilliseconds / corpusSize).toStringAsFixed(2)}ms/meeting',
        );
        expect(
          chunksAfterReindex,
          lessThanOrEqualTo(totalChunks),
          reason: 'Re-indexing summaries should replace, not accumulate, chunks.',
        );

        // --- Retrieval ---
        final retrievalEngine = DefaultRetrievalEngine(
          embeddingEngine: embeddingEngine,
          vectorStore: vectorStore,
        );
        final retrievalStopwatch = Stopwatch()..start();
        final results = await retrievalEngine.retrieve(
          'budget roadmap staffing',
          k: 3,
          filter: KnowledgeChunkFilter.meetingsOnly,
        );
        retrievalStopwatch.stop();
        // ignore: avoid_print
        print(
          '[retrieval] corpus=$corpusSize meetings, $chunksAfterReindex chunks: '
          '${retrievalStopwatch.elapsedMilliseconds}ms for top-3, '
          '${results.length} results returned',
        );
        expect(results, isNotEmpty);
        expect(
          retrievalStopwatch.elapsedMilliseconds,
          lessThan(5000),
          reason: 'Retrieval took ${retrievalStopwatch.elapsedMilliseconds}ms '
              'across $chunksAfterReindex chunks - investigate before this '
              'regresses further.',
        );

        // --- Deletion (removing every meeting's chunks) ---
        final deletionStopwatch = Stopwatch()..start();
        for (final meetingId in meetingIds) {
          await knowledgeChunkRepository.deleteForSource(ContentType.transcript, meetingId);
          await knowledgeChunkRepository.deleteForSource(ContentType.summary, meetingId);
        }
        deletionStopwatch.stop();
        // ignore: avoid_print
        print(
          '[deletion] corpus=$corpusSize meetings: '
          '${deletionStopwatch.elapsedMilliseconds}ms total, '
          '${(deletionStopwatch.elapsedMilliseconds / corpusSize).toStringAsFixed(2)}ms/meeting',
        );
        expect(await knowledgeChunkRepository.getAll(), isEmpty);
      }, timeout: const Timeout(Duration(minutes: 5)));
    });
  }

  group('mixed workspace (1500 meetings + 1500 documents)', () {
    test('indexing and mixed-vs-scoped retrieval timing', () async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      final meetingRepository = SqfliteMeetingRepository(db);
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

      const meetingCount = 1500;
      const documentCount = 1500;
      final now = DateTime(2026, 1, 1);

      final indexingStopwatch = Stopwatch()..start();

      for (var i = 0; i < meetingCount; i++) {
        final meetingId = await meetingRepository.insert(
          Meeting(
            id: null,
            title: 'Meeting $i',
            source: MeetingSource.recorded,
            status: MeetingStatus.indexing,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await indexingService.indexContent(
          contentType: ContentType.transcript,
          sourceId: meetingId,
          meetingId: meetingId,
          text: _sampleTranscript(i),
        );
        await indexingService.indexContent(
          contentType: ContentType.summary,
          sourceId: meetingId,
          meetingId: meetingId,
          text: _sampleSummary(i),
        );
      }

      for (var i = 0; i < documentCount; i++) {
        final documentId = await documentRepository.insert(
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
            extractedText: _sampleTranscript(i),
          ),
        );
        await indexingService.indexContent(
          contentType: ContentType.document,
          sourceId: documentId,
          documentId: documentId,
          text: _sampleTranscript(i),
        );
      }

      indexingStopwatch.stop();
      final totalChunks = (await knowledgeChunkRepository.getAll()).length;
      // ignore: avoid_print
      print(
        '[mixed indexing] $meetingCount meetings + $documentCount documents, '
        '$totalChunks chunks: ${indexingStopwatch.elapsedMilliseconds}ms total',
      );

      final retrievalEngine = DefaultRetrievalEngine(
        embeddingEngine: embeddingEngine,
        vectorStore: vectorStore,
      );

      final mixedStopwatch = Stopwatch()..start();
      final mixedResults = await retrievalEngine.retrieve('budget roadmap staffing', k: 5);
      mixedStopwatch.stop();
      // ignore: avoid_print
      print(
        '[mixed retrieval] workspace-wide: ${mixedStopwatch.elapsedMilliseconds}ms '
        'for top-5, ${mixedResults.length} results',
      );
      expect(mixedResults, isNotEmpty);

      final meetingsOnlyStopwatch = Stopwatch()..start();
      final meetingsOnlyResults = await retrievalEngine.retrieve(
        'budget roadmap staffing',
        k: 5,
        filter: KnowledgeChunkFilter.meetingsOnly,
      );
      meetingsOnlyStopwatch.stop();
      // ignore: avoid_print
      print(
        '[mixed retrieval] meetings-only: ${meetingsOnlyStopwatch.elapsedMilliseconds}ms '
        'for top-5, ${meetingsOnlyResults.length} results',
      );
      expect(meetingsOnlyResults, isNotEmpty);
      expect(meetingsOnlyResults.every((c) => c.meetingId != null), isTrue);

      final documentsOnlyStopwatch = Stopwatch()..start();
      final documentsOnlyResults = await retrievalEngine.retrieve(
        'budget roadmap staffing',
        k: 5,
        filter: KnowledgeChunkFilter.documentsOnly,
      );
      documentsOnlyStopwatch.stop();
      // ignore: avoid_print
      print(
        '[mixed retrieval] documents-only: ${documentsOnlyStopwatch.elapsedMilliseconds}ms '
        'for top-5, ${documentsOnlyResults.length} results',
      );
      expect(documentsOnlyResults, isNotEmpty);
      expect(documentsOnlyResults.every((c) => c.documentId != null), isTrue);

      expect(
        mixedStopwatch.elapsedMilliseconds,
        lessThan(8000),
        reason: 'Mixed workspace retrieval took '
            '${mixedStopwatch.elapsedMilliseconds}ms across $totalChunks '
            'chunks - investigate before this regresses further.',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}
