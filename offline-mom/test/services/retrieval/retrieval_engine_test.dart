import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/retrieval/knowledge_chunk_filter.dart';
import 'package:offline_mom/services/retrieval/retrieval_engine.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late KnowledgeChunkRepository knowledgeChunkRepository;
  late DocumentRepository documentRepository;
  late BruteForceVectorStore vectorStore;

  setUp(() async {
    db = await openTestDatabase();
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
    vectorStore = BruteForceVectorStore(knowledgeChunkRepository: knowledgeChunkRepository);
  });

  tearDown(() => db.close());

  Future<int> insertDocument() {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'Doc',
        originalFilename: 'doc.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 10,
        filePath: '/tmp/doc.pdf',
        status: DocumentStatus.indexing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('embeds the query then returns the most relevant stored chunks',
      () async {
    final documentId = await insertDocument();
    final embeddingEngine = FakeEmbeddingEngine();

    // The fake engine is deterministic and text-sensitive, so a chunk
    // whose text closely resembles the query embeds closer to it than an
    // unrelated chunk - this is what makes the assertion below meaningful
    // rather than a coincidence.
    await vectorStore.addAll([
      KnowledgeChunk(
        id: null,
        contentType: ContentType.document,
        sourceId: documentId,
        documentId: documentId,
        meetingId: null,
        chunkIndex: 0,
        chunkText: 'the quarterly budget review meeting notes',
        embedding: await embeddingEngine.embed('the quarterly budget review meeting notes'),
        createdAt: DateTime(2026, 1, 1),
      ),
      KnowledgeChunk(
        id: null,
        contentType: ContentType.document,
        sourceId: documentId,
        documentId: documentId,
        meetingId: null,
        chunkIndex: 1,
        chunkText: 'zzz completely unrelated xyz filler qqq',
        embedding: await embeddingEngine.embed('zzz completely unrelated xyz filler qqq'),
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);

    final engine = DefaultRetrievalEngine(
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
    );

    final results = await engine.retrieve('quarterly budget review', k: 1);

    expect(results, hasLength(1));
    expect(results.single.chunkText, contains('budget review'));
  });

  test('returns an empty list for an empty query without embedding it',
      () async {
    final embeddingEngine = FakeEmbeddingEngine(errorToThrow: StateError('should not be called'));
    final engine = DefaultRetrievalEngine(
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
    );

    expect(await engine.retrieve('   '), isEmpty);
  });

  test('defaults k to 3 per ADR-011', () async {
    final documentId = await insertDocument();
    final embeddingEngine = FakeEmbeddingEngine();
    await vectorStore.addAll([
      for (var i = 0; i < 5; i++)
        KnowledgeChunk(
          id: null,
          contentType: ContentType.document,
          sourceId: documentId,
          documentId: documentId,
          meetingId: null,
          chunkIndex: i,
          chunkText: 'chunk number $i',
          embedding: await embeddingEngine.embed('chunk number $i'),
          createdAt: DateTime(2026, 1, 1),
        ),
    ]);

    final engine = DefaultRetrievalEngine(
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
    );

    expect(await engine.retrieve('chunk'), hasLength(3));
  });

  test('propagates an embedding-engine failure to the caller', () async {
    final engine = DefaultRetrievalEngine(
      embeddingEngine: FakeEmbeddingEngine(errorToThrow: Exception('model crashed')),
      vectorStore: vectorStore,
    );

    await expectLater(engine.retrieve('a real question'), throwsException);
  });

  group('retrieve with a KnowledgeChunkFilter', () {
    late MeetingRepository meetingRepository;

    setUp(() {
      meetingRepository = SqfliteMeetingRepository(db);
    });

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

    test('workspace retrieval (no filter) returns both meeting and document '
        'chunks', () async {
      final documentId = await insertDocument();
      final meetingId = await insertMeeting();
      final embeddingEngine = FakeEmbeddingEngine();
      await vectorStore.addAll([
        KnowledgeChunk(
          id: null,
          contentType: ContentType.document,
          sourceId: documentId,
          documentId: documentId,
          meetingId: null,
          chunkIndex: 0,
          chunkText: 'budget review document',
          embedding: await embeddingEngine.embed('budget review document'),
          createdAt: DateTime(2026, 1, 1),
        ),
        KnowledgeChunk(
          id: null,
          contentType: ContentType.transcript,
          sourceId: 1,
          documentId: null,
          meetingId: meetingId,
          chunkIndex: 0,
          chunkText: 'budget review transcript',
          embedding: await embeddingEngine.embed('budget review transcript'),
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);

      final engine = DefaultRetrievalEngine(
        embeddingEngine: embeddingEngine,
        vectorStore: vectorStore,
      );

      final results = await engine.retrieve('budget review', k: 5);

      expect(results.map((c) => c.chunkText).toSet(), {
        'budget review document',
        'budget review transcript',
      });
    });

    test('documentsOnly excludes meeting chunks', () async {
      final documentId = await insertDocument();
      final meetingId = await insertMeeting();
      final embeddingEngine = FakeEmbeddingEngine();
      await vectorStore.addAll([
        KnowledgeChunk(
          id: null,
          contentType: ContentType.document,
          sourceId: documentId,
          documentId: documentId,
          meetingId: null,
          chunkIndex: 0,
          chunkText: 'budget review document',
          embedding: await embeddingEngine.embed('budget review document'),
          createdAt: DateTime(2026, 1, 1),
        ),
        KnowledgeChunk(
          id: null,
          contentType: ContentType.transcript,
          sourceId: 1,
          documentId: null,
          meetingId: meetingId,
          chunkIndex: 0,
          chunkText: 'budget review transcript',
          embedding: await embeddingEngine.embed('budget review transcript'),
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);

      final engine = DefaultRetrievalEngine(
        embeddingEngine: embeddingEngine,
        vectorStore: vectorStore,
      );

      final results = await engine.retrieve(
        'budget review',
        k: 5,
        filter: KnowledgeChunkFilter.documentsOnly,
      );

      expect(results.map((c) => c.chunkText), ['budget review document']);
    });

    test('forMeeting restricts retrieval to one specific meeting', () async {
      final meetingA = await insertMeeting();
      final meetingB = await insertMeeting();
      final embeddingEngine = FakeEmbeddingEngine();
      await vectorStore.addAll([
        KnowledgeChunk(
          id: null,
          contentType: ContentType.transcript,
          sourceId: 1,
          documentId: null,
          meetingId: meetingA,
          chunkIndex: 0,
          chunkText: 'meeting A budget review',
          embedding: await embeddingEngine.embed('meeting A budget review'),
          createdAt: DateTime(2026, 1, 1),
        ),
        KnowledgeChunk(
          id: null,
          contentType: ContentType.transcript,
          sourceId: 2,
          documentId: null,
          meetingId: meetingB,
          chunkIndex: 0,
          chunkText: 'meeting B budget review',
          embedding: await embeddingEngine.embed('meeting B budget review'),
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);

      final engine = DefaultRetrievalEngine(
        embeddingEngine: embeddingEngine,
        vectorStore: vectorStore,
      );

      final results = await engine.retrieve(
        'budget review',
        k: 5,
        filter: KnowledgeChunkFilter.forMeeting(meetingA),
      );

      expect(results.map((c) => c.chunkText), ['meeting A budget review']);
    });

    test('a contentTypes filter restricts retrieval within a meeting\'s '
        'own chunks (e.g. summaries only)', () async {
      final meetingId = await insertMeeting();
      final embeddingEngine = FakeEmbeddingEngine();
      await vectorStore.addAll([
        KnowledgeChunk(
          id: null,
          contentType: ContentType.transcript,
          sourceId: 1,
          documentId: null,
          meetingId: meetingId,
          chunkIndex: 0,
          chunkText: 'transcript about budget',
          embedding: await embeddingEngine.embed('transcript about budget'),
          createdAt: DateTime(2026, 1, 1),
        ),
        KnowledgeChunk(
          id: null,
          contentType: ContentType.summary,
          sourceId: 2,
          documentId: null,
          meetingId: meetingId,
          chunkIndex: 0,
          chunkText: 'summary about budget',
          embedding: await embeddingEngine.embed('summary about budget'),
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);

      final engine = DefaultRetrievalEngine(
        embeddingEngine: embeddingEngine,
        vectorStore: vectorStore,
      );

      final results = await engine.retrieve(
        'budget',
        k: 5,
        filter: const KnowledgeChunkFilter(contentTypes: {ContentType.summary}),
      );

      expect(results.map((c) => c.chunkText), ['summary about budget']);
    });
  });
}
