import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/hybrid_retrieval_pipeline.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/keyword_search_service.dart';
import 'package:offline_mom/services/retrieval/retrieval_confidence.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

void main() {
  group('HybridRetrievalPipeline', () {
    late Database db;
    late MeetingRepository meetingRepository;
    late DocumentRepository documentRepository;
    late IndexingService indexingService;
    late HybridRetrievalPipeline pipeline;

    setUp(() async {
      db = await openTestDatabase();
      meetingRepository = SqfliteMeetingRepository(db);
      documentRepository = SqfliteDocumentRepository(db);
      final knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
      final embeddingEngine = FakeEmbeddingEngine();
      final vectorStore = BruteForceVectorStore(knowledgeChunkRepository: knowledgeChunkRepository);
      indexingService = DefaultIndexingService(
        chunkingService: const DefaultChunkingService(),
        embeddingEngine: embeddingEngine,
        vectorStore: vectorStore,
        knowledgeChunkRepository: knowledgeChunkRepository,
      );
      pipeline = HybridRetrievalPipeline(
        embeddingEngine: embeddingEngine,
        vectorStore: vectorStore,
        keywordSearchService: SqfliteKeywordSearchService(db),
      );
    });

    tearDown(() => db.close());

    Future<int> insertMeeting() {
      final now = DateTime(2026, 1, 1);
      return meetingRepository.insert(
        Meeting(
          id: null,
          title: 'Standup',
          source: MeetingSource.recorded,
          status: MeetingStatus.indexing,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    Future<int> insertDocument() {
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
        ),
      );
    }

    test('an empty corpus yields RetrievalConfidence.none and no selected chunks', () async {
      final result = await pipeline.run(question: 'anything at all', scope: ChatScope.workspace);

      expect(result.confidence, RetrievalConfidence.none);
      expect(result.selectedChunks, isEmpty);
      expect(result.stats.vectorCandidateCount, 0);
      expect(result.stats.keywordCandidateCount, 0);
    });

    test('a genuinely relevant match is confidently selected and both retrieval paths agree', () async {
      final meetingId = await insertMeeting();
      await indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: meetingId,
        meetingId: meetingId,
        text: 'The team discussed the quarterly budget and approved next steps.',
      );

      final result = await pipeline.run(question: 'quarterly budget', scope: ChatScope.workspace);

      expect(result.confidence, anyOf(RetrievalConfidence.high, RetrievalConfidence.medium));
      expect(result.selectedChunks, isNotEmpty);
      expect(result.selectedChunks.first.matchedVector, isTrue);
      expect(result.selectedChunks.first.matchedKeyword, isTrue);
      expect(result.chunkConfidence, isNotEmpty);
    });

    test('meeting-scoped retrieval never returns chunks from a different meeting', () async {
      final meetingA = await insertMeeting();
      final meetingB = await insertMeeting();
      await indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: meetingA,
        meetingId: meetingA,
        text: 'The team discussed the quarterly budget and approved next steps.',
      );
      await indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: meetingB,
        meetingId: meetingB,
        text: 'The team discussed the quarterly budget in a different meeting.',
      );

      final result = await pipeline.run(
        question: 'quarterly budget',
        scope: ChatScope.meeting,
        meetingId: meetingA,
      );

      for (final ranked in result.selectedChunks) {
        expect(ranked.chunk.meetingId, meetingA);
      }
    });

    test('document-scoped retrieval never returns chunks from a meeting', () async {
      final meetingId = await insertMeeting();
      final documentId = await insertDocument();
      await indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: meetingId,
        meetingId: meetingId,
        text: 'The team discussed the quarterly budget and approved next steps.',
      );
      await indexingService.indexContent(
        contentType: ContentType.document,
        sourceId: documentId,
        documentId: documentId,
        text: 'This report covers the quarterly budget in detail.',
      );

      final result = await pipeline.run(
        question: 'quarterly budget',
        scope: ChatScope.document,
        documentId: documentId,
      );

      for (final ranked in result.selectedChunks) {
        expect(ranked.chunk.documentId, documentId);
        expect(ranked.chunk.meetingId, isNull);
      }
    });

    test('an empty/blank question yields none confidence without any retrieval calls', () async {
      final meetingId = await insertMeeting();
      await indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: meetingId,
        meetingId: meetingId,
        text: 'The team discussed the quarterly budget.',
      );

      final result = await pipeline.run(question: '   ', scope: ChatScope.workspace);

      expect(result.confidence, RetrievalConfidence.none);
      expect(result.stats.vectorCandidateCount, 0);
    });

    test('classification reflects the query type (e.g. summarize -> summaryRequest)', () async {
      final result = await pipeline.run(question: 'please summarize this', scope: ChatScope.workspace);
      expect(result.classification.type.toString(), contains('summaryRequest'));
    });

    test('retrieval stats report real, non-negative counts and elapsed time', () async {
      final meetingId = await insertMeeting();
      await indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: meetingId,
        meetingId: meetingId,
        text: 'The team discussed the quarterly budget and approved next steps.',
      );

      final result = await pipeline.run(question: 'quarterly budget', scope: ChatScope.workspace);

      expect(result.stats.vectorCandidateCount, greaterThanOrEqualTo(0));
      expect(result.stats.keywordCandidateCount, greaterThanOrEqualTo(0));
      expect(result.stats.fusedCandidateCount, greaterThanOrEqualTo(0));
      expect(result.stats.elapsed, isNotNull);
    });
  });
}
