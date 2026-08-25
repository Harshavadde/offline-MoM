import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/retrieval/keyword_search_service.dart';
import 'package:offline_mom/services/retrieval/knowledge_chunk_filter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

void main() {
  group('SqfliteKeywordSearchService', () {
    late Database db;
    late KnowledgeChunkRepository repository;
    late MeetingRepository meetingRepository;
    late DocumentRepository documentRepository;
    late SqfliteKeywordSearchService service;
    late int meetingId;

    setUp(() async {
      db = await openTestDatabase();
      repository = SqfliteKnowledgeChunkRepository(db);
      meetingRepository = SqfliteMeetingRepository(db);
      documentRepository = SqfliteDocumentRepository(db);
      service = SqfliteKeywordSearchService(db);
      meetingId = await _insertMeeting(meetingRepository);
    });

    tearDown(() => db.close());

    KnowledgeChunk buildChunk({
      required String text,
      int? meetingId,
      int? documentId,
      ContentType contentType = ContentType.transcript,
    }) {
      return KnowledgeChunk(
        id: null,
        contentType: contentType,
        sourceId: 1,
        meetingId: meetingId,
        documentId: documentId,
        chunkIndex: 0,
        chunkText: text,
        embedding: const [1.0, 0.0],
        createdAt: DateTime(2026, 1, 1),
      );
    }

    test('finds a chunk by an exact keyword match', () async {
      await repository.insert(buildChunk(text: 'the quarterly budget was approved', meetingId: meetingId));
      await repository.insert(buildChunk(text: 'lunch order for the team offsite', meetingId: meetingId));

      final results = await service.search('budget', k: 5);

      expect(results, hasLength(1));
      expect(results.single.chunk.chunkText, contains('budget'));
    });

    test('a query matching nothing returns an empty list', () async {
      await repository.insert(buildChunk(text: 'the quarterly budget was approved', meetingId: meetingId));

      final results = await service.search('nonexistentword', k: 5);

      expect(results, isEmpty);
    });

    test('an empty/punctuation-only query returns an empty list', () async {
      await repository.insert(buildChunk(text: 'the quarterly budget was approved', meetingId: meetingId));

      expect(await service.search('', k: 5), isEmpty);
      expect(await service.search('...', k: 5), isEmpty);
    });

    test('k=0 returns an empty list without querying', () async {
      await repository.insert(buildChunk(text: 'the quarterly budget was approved', meetingId: meetingId));
      expect(await service.search('budget', k: 0), isEmpty);
    });

    test('results are ordered best match first (highest sign-corrected score)', () async {
      await repository.insert(
        buildChunk(text: 'budget budget budget - entirely about the budget', meetingId: meetingId),
      );
      await repository.insert(buildChunk(text: 'a passing mention of budget once', meetingId: meetingId));

      final results = await service.search('budget', k: 5);

      expect(results, hasLength(2));
      expect(results.first.score, greaterThan(results.last.score));
      expect(results.first.chunk.chunkText, contains('entirely about'));
    });

    test('respects k as a limit', () async {
      for (var i = 0; i < 5; i++) {
        await repository.insert(buildChunk(text: 'budget item number $i', meetingId: meetingId));
      }
      final results = await service.search('budget', k: 2);
      expect(results, hasLength(2));
    });

    test('filter.forMeeting restricts results to that meeting only', () async {
      final otherMeetingId = await _insertMeeting(meetingRepository);
      await repository.insert(buildChunk(text: 'meeting one budget notes', meetingId: meetingId));
      await repository.insert(buildChunk(text: 'meeting two budget notes', meetingId: otherMeetingId));

      final results =
          await service.search('budget', k: 10, filter: KnowledgeChunkFilter.forMeeting(meetingId));

      expect(results, hasLength(1));
      expect(results.single.chunk.meetingId, meetingId);
    });

    test('filter.forDocument restricts results to that document only', () async {
      final documentIdOne = await _insertDocument(documentRepository);
      final documentIdTwo = await _insertDocument(documentRepository);
      await repository.insert(
        buildChunk(text: 'document one budget notes', meetingId: null, documentId: documentIdOne),
      );
      await repository.insert(
        buildChunk(text: 'document two budget notes', meetingId: null, documentId: documentIdTwo),
      );

      final results =
          await service.search('budget', k: 10, filter: KnowledgeChunkFilter.forDocument(documentIdOne));

      expect(results, hasLength(1));
      expect(results.single.chunk.documentId, documentIdOne);
    });

    test('filter.contentTypes restricts results by content type', () async {
      await repository.insert(
        buildChunk(text: 'transcript about budget', meetingId: meetingId, contentType: ContentType.transcript),
      );
      await repository.insert(
        buildChunk(text: 'summary about budget', meetingId: meetingId, contentType: ContentType.summary),
      );

      final results = await service.search(
        'budget',
        k: 10,
        filter: const KnowledgeChunkFilter(contentTypes: {ContentType.summary}),
      );

      expect(results, hasLength(1));
      expect(results.single.chunk.contentType, ContentType.summary);
    });

    test('a deleted chunk no longer appears in keyword results (trigger sync)', () async {
      final id = await repository.insert(buildChunk(text: 'a unique searchable phrase', meetingId: meetingId));
      expect(await service.search('unique', k: 5), hasLength(1));

      await repository.deleteForSource(ContentType.transcript, 1);
      expect(await service.search('unique', k: 5), isEmpty);
      // Sanity: confirm the row is really gone, not just filtered.
      expect(await repository.getAll(), isEmpty, reason: 'id $id should have been deleted');
    });
  });
}

Future<int> _insertMeeting(MeetingRepository repository) {
  final now = DateTime(2026, 1, 1);
  return repository.insert(
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

Future<int> _insertDocument(DocumentRepository repository) {
  final now = DateTime(2026, 1, 1);
  return repository.insert(
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
