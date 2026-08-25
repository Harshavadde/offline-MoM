import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/retrieval/knowledge_chunk_filter.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

void main() {
  group('BruteForceVectorStore.cosineSimilarity', () {
    test('is 1.0 for identical vectors', () {
      expect(
        BruteForceVectorStore.cosineSimilarity([1, 2, 3], [1, 2, 3]),
        closeTo(1.0, 1e-9),
      );
    });

    test('is -1.0 for exactly opposite vectors', () {
      expect(
        BruteForceVectorStore.cosineSimilarity([1, 0], [-1, 0]),
        closeTo(-1.0, 1e-9),
      );
    });

    test('is 0.0 for orthogonal vectors', () {
      expect(
        BruteForceVectorStore.cosineSimilarity([1, 0], [0, 1]),
        closeTo(0.0, 1e-9),
      );
    });

    test('is scale-invariant (unnormalized vectors still compare correctly)', () {
      final a = BruteForceVectorStore.cosineSimilarity([1, 2, 3], [2, 4, 6]);
      expect(a, closeTo(1.0, 1e-9));
    });

    test('returns 0.0 rather than NaN for a zero vector', () {
      expect(BruteForceVectorStore.cosineSimilarity([0, 0, 0], [1, 2, 3]), 0.0);
    });

    test('throws for mismatched vector lengths', () {
      expect(
        () => BruteForceVectorStore.cosineSimilarity([1, 2], [1, 2, 3]),
        throwsArgumentError,
      );
    });
  });

  group('BruteForceVectorStore.similaritySearch', () {
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

    KnowledgeChunk buildChunk(int documentId, String text, List<double> embedding) {
      return KnowledgeChunk(
        id: null,
        contentType: ContentType.document,
        sourceId: documentId,
        documentId: documentId,
        meetingId: null,
        chunkIndex: 0,
        chunkText: text,
        embedding: embedding,
        createdAt: DateTime(2026, 1, 1),
      );
    }

    test('returns the most similar chunks first', () async {
      final documentId = await insertDocument();
      await vectorStore.addAll([
        buildChunk(documentId, 'exact match', [1, 0, 0]),
        buildChunk(documentId, 'somewhat similar', [0.7, 0.7, 0]),
        buildChunk(documentId, 'unrelated', [0, 1, 0]),
      ]);

      final results = await vectorStore.similaritySearch([1, 0, 0], k: 3);

      expect(results.map((c) => c.chunkText), [
        'exact match',
        'somewhat similar',
        'unrelated',
      ]);
    });

    test('returns at most k results even when more chunks exist', () async {
      final documentId = await insertDocument();
      await vectorStore.addAll([
        buildChunk(documentId, 'a', [1, 0]),
        buildChunk(documentId, 'b', [0.9, 0.1]),
        buildChunk(documentId, 'c', [0.5, 0.5]),
        buildChunk(documentId, 'd', [0, 1]),
      ]);

      final results = await vectorStore.similaritySearch([1, 0], k: 2);

      expect(results, hasLength(2));
      expect(results.map((c) => c.chunkText), ['a', 'b']);
    });

    test('returns an empty list when the store is empty', () async {
      expect(await vectorStore.similaritySearch([1, 0], k: 3), isEmpty);
    });

    test('returns an empty list for k=0', () async {
      final documentId = await insertDocument();
      await vectorStore.add(buildChunk(documentId, 'a', [1, 0]));

      expect(await vectorStore.similaritySearch([1, 0], k: 0), isEmpty);
    });
  });

  group('BruteForceVectorStore.similaritySearch with a KnowledgeChunkFilter', () {
    late Database db;
    late KnowledgeChunkRepository knowledgeChunkRepository;
    late DocumentRepository documentRepository;
    late MeetingRepository meetingRepository;
    late BruteForceVectorStore vectorStore;

    setUp(() async {
      db = await openTestDatabase();
      knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
      documentRepository = SqfliteDocumentRepository(db);
      meetingRepository = SqfliteMeetingRepository(db);
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

    KnowledgeChunk documentChunk(int documentId, String text, List<double> embedding) {
      return KnowledgeChunk(
        id: null,
        contentType: ContentType.document,
        sourceId: documentId,
        documentId: documentId,
        meetingId: null,
        chunkIndex: 0,
        chunkText: text,
        embedding: embedding,
        createdAt: DateTime(2026, 1, 1),
      );
    }

    KnowledgeChunk meetingChunk(
      int meetingId,
      ContentType contentType,
      int sourceId,
      String text,
      List<double> embedding,
    ) {
      return KnowledgeChunk(
        id: null,
        contentType: contentType,
        sourceId: sourceId,
        documentId: null,
        meetingId: meetingId,
        chunkIndex: 0,
        chunkText: text,
        embedding: embedding,
        createdAt: DateTime(2026, 1, 1),
      );
    }

    test('with no filter argument, searches the whole workspace (documents '
        'and meetings mixed)', () async {
      final documentId = await insertDocument();
      final meetingId = await insertMeeting();
      await vectorStore.addAll([
        documentChunk(documentId, 'doc chunk', [1, 0]),
        meetingChunk(meetingId, ContentType.transcript, 1, 'meeting chunk', [1, 0]),
      ]);

      final results = await vectorStore.similaritySearch([1, 0], k: 5);

      expect(results.map((c) => c.chunkText).toSet(), {'doc chunk', 'meeting chunk'});
    });

    test('documentsOnly excludes meeting-owned chunks even when they score '
        'higher', () async {
      final documentId = await insertDocument();
      final meetingId = await insertMeeting();
      await vectorStore.addAll([
        documentChunk(documentId, 'doc chunk', [0.5, 0.5]),
        meetingChunk(meetingId, ContentType.transcript, 1, 'meeting chunk', [1, 0]),
      ]);

      final results = await vectorStore.similaritySearch(
        [1, 0],
        k: 5,
        filter: KnowledgeChunkFilter.documentsOnly,
      );

      expect(results.map((c) => c.chunkText), ['doc chunk']);
    });

    test('meetingsOnly excludes document-owned chunks', () async {
      final documentId = await insertDocument();
      final meetingId = await insertMeeting();
      await vectorStore.addAll([
        documentChunk(documentId, 'doc chunk', [1, 0]),
        meetingChunk(meetingId, ContentType.summary, 1, 'meeting chunk', [1, 0]),
      ]);

      final results = await vectorStore.similaritySearch(
        [1, 0],
        k: 5,
        filter: KnowledgeChunkFilter.meetingsOnly,
      );

      expect(results.map((c) => c.chunkText), ['meeting chunk']);
    });

    test('forMeeting restricts to a single meeting\'s chunks', () async {
      final meetingA = await insertMeeting();
      final meetingB = await insertMeeting();
      await vectorStore.addAll([
        meetingChunk(meetingA, ContentType.transcript, 1, 'meeting A', [1, 0]),
        meetingChunk(meetingB, ContentType.transcript, 2, 'meeting B', [1, 0]),
      ]);

      final results = await vectorStore.similaritySearch(
        [1, 0],
        k: 5,
        filter: KnowledgeChunkFilter.forMeeting(meetingA),
      );

      expect(results.map((c) => c.chunkText), ['meeting A']);
    });

    test('a contentTypes filter restricts by content type across owners', () async {
      final meetingId = await insertMeeting();
      await vectorStore.addAll([
        meetingChunk(meetingId, ContentType.transcript, 1, 'transcript chunk', [1, 0]),
        meetingChunk(meetingId, ContentType.summary, 2, 'summary chunk', [1, 0]),
        meetingChunk(meetingId, ContentType.note, 3, 'note chunk', [1, 0]),
      ]);

      final results = await vectorStore.similaritySearch(
        [1, 0],
        k: 5,
        filter: const KnowledgeChunkFilter(contentTypes: {ContentType.summary}),
      );

      expect(results.map((c) => c.chunkText), ['summary chunk']);
    });
  });

  group('BruteForceVectorStore in-memory cache (Phase 3A)', () {
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

    KnowledgeChunk buildChunk(int documentId, String text, List<double> embedding) {
      return KnowledgeChunk(
        id: null,
        contentType: ContentType.document,
        sourceId: documentId,
        documentId: documentId,
        meetingId: null,
        chunkIndex: 0,
        chunkText: text,
        embedding: embedding,
        createdAt: DateTime(2026, 1, 1),
      );
    }

    test('a second similaritySearch reflects a row inserted via a second '
        'BruteForceVectorStore instance sharing the same repository, once '
        'invalidateCache is called', () async {
      final documentId = await insertDocument();
      await vectorStore.add(buildChunk(documentId, 'first', [1, 0]));

      // Populate this store's cache.
      final before = await vectorStore.similaritySearch([1, 0], k: 5);
      expect(before.map((c) => c.chunkText), ['first']);

      // A write that bypasses this exact instance's add/addAll (mirrors
      // IndexingService's direct-repository delete path) - simulated here
      // via a second store sharing the same repository/table.
      final other = BruteForceVectorStore(knowledgeChunkRepository: knowledgeChunkRepository);
      await other.add(buildChunk(documentId, 'second', [1, 0]));

      // Without invalidation, the first store would still be serving its
      // stale cached view (only 'first').
      vectorStore.invalidateCache();
      final after = await vectorStore.similaritySearch([1, 0], k: 5);

      expect(after.map((c) => c.chunkText).toSet(), {'first', 'second'});
    });

    test('add() invalidates the cache so the newly added chunk is '
        'immediately searchable', () async {
      final documentId = await insertDocument();
      await vectorStore.similaritySearch([1, 0], k: 5); // populate cache while empty

      await vectorStore.add(buildChunk(documentId, 'added after first search', [1, 0]));

      final results = await vectorStore.similaritySearch([1, 0], k: 5);
      expect(results.map((c) => c.chunkText), ['added after first search']);
    });

    test('addAll() invalidates the cache the same way add() does', () async {
      final documentId = await insertDocument();
      await vectorStore.similaritySearch([1, 0], k: 5); // populate cache while empty

      await vectorStore.addAll([buildChunk(documentId, 'batch-added', [1, 0])]);

      final results = await vectorStore.similaritySearch([1, 0], k: 5);
      expect(results.map((c) => c.chunkText), ['batch-added']);
    });
  });

  group('BruteForceVectorStore top-k selection matches a naive full-sort '
      'reference (Phase 3A allocation optimization)', () {
    /// The pre-Phase-3A implementation: score every candidate, sort
    /// descending, take k - kept here only as the correctness oracle the
    /// optimized bounded-buffer implementation must always agree with.
    List<KnowledgeChunk> naiveTopK(
      List<KnowledgeChunk> candidates,
      List<double> query,
      int k,
    ) {
      final scored = <MapEntry<KnowledgeChunk, double>>[
        for (final chunk in candidates)
          MapEntry(chunk, BruteForceVectorStore.cosineSimilarity(query, chunk.embedding)),
      ]..sort((a, b) => b.value.compareTo(a.value));
      return scored.take(k).map((e) => e.key).toList();
    }

    KnowledgeChunk chunkWith(int id, List<double> embedding) {
      return KnowledgeChunk(
        id: id,
        contentType: ContentType.document,
        sourceId: id,
        documentId: id,
        meetingId: null,
        chunkIndex: 0,
        chunkText: 'chunk-$id',
        embedding: embedding,
        createdAt: DateTime(2026, 1, 1),
      );
    }

    test('produces the same top-k chunk set (by id) as the naive reference '
        'across randomized corpora of varying size and k', () async {
      final random = Random(42); // fixed seed - deterministic, reproducible failures
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
      final documentRepository = SqfliteDocumentRepository(db);
      final now = DateTime(2026, 1, 1);
      final documentId = await documentRepository.insert(
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

      for (final corpusSize in [1, 2, 5, 20, 50]) {
        for (final k in [1, 3, 7]) {
          final chunks = [
            for (var i = 0; i < corpusSize; i++)
              chunkWith(i, [random.nextDouble(), random.nextDouble(), random.nextDouble()]),
          ];
          final query = [random.nextDouble(), random.nextDouble(), random.nextDouble()];

          final vectorStore =
              BruteForceVectorStore(knowledgeChunkRepository: knowledgeChunkRepository);
          await knowledgeChunkRepository.deleteForSource(ContentType.document, documentId);
          await vectorStore.addAll([
            for (final c in chunks)
              KnowledgeChunk(
                id: null,
                contentType: ContentType.document,
                sourceId: documentId,
                documentId: documentId,
                meetingId: null,
                chunkIndex: c.id!,
                chunkText: c.chunkText,
                embedding: c.embedding,
                createdAt: now,
              ),
          ]);

          final actual = await vectorStore.similaritySearch(query, k: k);
          final expected = naiveTopK(chunks, query, k);

          expect(
            actual.map((c) => c.chunkText).toSet(),
            expected.map((c) => c.chunkText).toSet(),
            reason: 'corpusSize=$corpusSize k=$k',
          );
          expect(actual.length, expected.length, reason: 'corpusSize=$corpusSize k=$k');
        }
      }
    });
  });
}
