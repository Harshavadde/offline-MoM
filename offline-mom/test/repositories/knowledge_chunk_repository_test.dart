import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late KnowledgeChunkRepository repository;
  late DocumentRepository documentRepository;
  late MeetingRepository meetingRepository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteKnowledgeChunkRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
    meetingRepository = SqfliteMeetingRepository(db);
  });

  tearDown(() => db.close());

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
        status: DocumentStatus.indexing,
        createdAt: now,
        updatedAt: now,
        extractedText: 'text',
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
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  KnowledgeChunk buildChunk({
    int? documentId,
    int? meetingId,
    ContentType? contentType,
    int? sourceId,
    int chunkIndex = 0,
    String chunkText = 'chunk text',
    List<double>? embedding,
  }) {
    return KnowledgeChunk(
      id: null,
      contentType: contentType ?? (documentId != null ? ContentType.document : ContentType.transcript),
      sourceId: sourceId ?? documentId ?? meetingId!,
      documentId: documentId,
      meetingId: meetingId,
      chunkIndex: chunkIndex,
      chunkText: chunkText,
      embedding: embedding ?? [0.1, 0.2, 0.3],
      createdAt: DateTime(2026, 1, 1, 12),
    );
  }

  test('insert then getForDocument round-trips the embedding and metadata '
      'exactly', () async {
    final documentId = await insertDocument();
    final embedding = [0.5, -0.25, 1.0, -1.0, 0.0];

    await repository.insert(buildChunk(documentId: documentId, embedding: embedding));

    final chunks = await repository.getForDocument(documentId);
    expect(chunks, hasLength(1));
    expect(chunks.single.embedding, embedding);
    expect(chunks.single.contentType, ContentType.document);
    expect(chunks.single.sourceId, documentId);
  });

  test('insertAll persists every chunk and getForDocument orders by '
      'chunkIndex', () async {
    final documentId = await insertDocument();

    await repository.insertAll([
      buildChunk(documentId: documentId, chunkIndex: 2, chunkText: 'third'),
      buildChunk(documentId: documentId, chunkIndex: 0, chunkText: 'first'),
      buildChunk(documentId: documentId, chunkIndex: 1, chunkText: 'second'),
    ]);

    final chunks = await repository.getForDocument(documentId);
    expect(chunks.map((c) => c.chunkText), ['first', 'second', 'third']);
  });

  test('insertAll with an empty list does nothing and does not throw',
      () async {
    await repository.insertAll(const []);
    expect(await repository.getAll(), isEmpty);
  });

  test('getForMeeting returns only that meeting\'s chunks', () async {
    final meetingId = await insertMeeting();
    final documentId = await insertDocument();
    await repository.insertAll([
      buildChunk(meetingId: meetingId, contentType: ContentType.transcript, chunkText: 'meeting chunk'),
      buildChunk(documentId: documentId, chunkText: 'document chunk'),
    ]);

    final meetingChunks = await repository.getForMeeting(meetingId);
    expect(meetingChunks.map((c) => c.chunkText), ['meeting chunk']);
  });

  test('getForMeeting returns chunks from every content type sharing that '
      'meeting (transcript, summary, and multiple notes)', () async {
    final meetingId = await insertMeeting();
    await repository.insertAll([
      buildChunk(
        meetingId: meetingId,
        contentType: ContentType.transcript,
        sourceId: 100,
        chunkText: 'transcript chunk',
      ),
      buildChunk(
        meetingId: meetingId,
        contentType: ContentType.summary,
        sourceId: 200,
        chunkText: 'summary chunk',
      ),
      buildChunk(
        meetingId: meetingId,
        contentType: ContentType.note,
        sourceId: 301,
        chunkText: 'note one chunk',
      ),
      buildChunk(
        meetingId: meetingId,
        contentType: ContentType.note,
        sourceId: 302,
        chunkText: 'note two chunk',
      ),
    ]);

    final chunks = await repository.getForMeeting(meetingId);
    expect(
      chunks.map((c) => c.chunkText).toSet(),
      {'transcript chunk', 'summary chunk', 'note one chunk', 'note two chunk'},
    );
  });

  test('deleteForSource removes only the targeted source\'s chunks, even '
      'when other sources share the same meeting', () async {
    final meetingId = await insertMeeting();
    await repository.insertAll([
      buildChunk(meetingId: meetingId, contentType: ContentType.transcript, sourceId: 1, chunkText: 'transcript'),
      buildChunk(meetingId: meetingId, contentType: ContentType.summary, sourceId: 2, chunkText: 'summary'),
      buildChunk(meetingId: meetingId, contentType: ContentType.note, sourceId: 3, chunkText: 'note'),
    ]);

    await repository.deleteForSource(ContentType.note, 3);

    final remaining = await repository.getForMeeting(meetingId);
    expect(remaining.map((c) => c.chunkText).toSet(), {'transcript', 'summary'});
  });

  test('deleteForSource does not remove another source of the same content '
      'type (distinguished by sourceId, e.g. two different notes)', () async {
    final meetingId = await insertMeeting();
    await repository.insertAll([
      buildChunk(meetingId: meetingId, contentType: ContentType.note, sourceId: 10, chunkText: 'note ten'),
      buildChunk(meetingId: meetingId, contentType: ContentType.note, sourceId: 11, chunkText: 'note eleven'),
    ]);

    await repository.deleteForSource(ContentType.note, 10);

    final remaining = await repository.getForMeeting(meetingId);
    expect(remaining.map((c) => c.chunkText), ['note eleven']);
  });

  test('deleting the owning document cascades to its chunks', () async {
    final documentId = await insertDocument();
    await repository.insert(buildChunk(documentId: documentId));

    await documentRepository.delete(documentId);

    expect(await repository.getForDocument(documentId), isEmpty);
  });

  test('deleting the owning meeting cascades to every content type\'s '
      'chunks (transcript, summary, and notes alike)', () async {
    final meetingId = await insertMeeting();
    await repository.insertAll([
      buildChunk(meetingId: meetingId, contentType: ContentType.transcript, sourceId: 1),
      buildChunk(meetingId: meetingId, contentType: ContentType.summary, sourceId: 2),
      buildChunk(meetingId: meetingId, contentType: ContentType.note, sourceId: 3),
    ]);

    await meetingRepository.delete(meetingId);

    expect(await repository.getForMeeting(meetingId), isEmpty);
  });

  test('getAll returns chunks across every owner', () async {
    final documentId = await insertDocument();
    final meetingId = await insertMeeting();
    await repository.insertAll([
      buildChunk(documentId: documentId),
      buildChunk(meetingId: meetingId),
    ]);

    expect(await repository.getAll(), hasLength(2));
  });

  test(
      'the database rejects a chunk row with both meeting_id and '
      'document_id set (CHECK constraint, ADR-005)', () async {
    final documentId = await insertDocument();
    final meetingId = await insertMeeting();

    await expectLater(
      db.insert('knowledge_chunks', {
        'meeting_id': meetingId,
        'document_id': documentId,
        'content_type': 'transcript',
        'source_id': meetingId,
        'chunk_index': 0,
        'chunk_text': 'invalid',
        'embedding': KnowledgeChunk.encodeEmbedding([0.1]),
        'embedding_dim': 1,
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      }),
      throwsA(anything),
    );
  });

  test('handles a high-dimensional embedding vector without truncation',
      () async {
    final documentId = await insertDocument();
    final embedding = List<double>.generate(768, (i) => i / 768);

    await repository.insert(buildChunk(documentId: documentId, embedding: embedding));

    final chunks = await repository.getForDocument(documentId);
    expect(chunks.single.embedding, embedding);
  });
}
