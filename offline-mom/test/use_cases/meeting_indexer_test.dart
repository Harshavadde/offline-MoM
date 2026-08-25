import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/meetings/meeting_indexer.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/summary.dart';
import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late TranscriptRepository transcriptRepository;
  late SummaryRepository summaryRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
  });

  tearDown(() => db.close());

  MeetingIndexer buildIndexer({FakeEmbeddingEngine? embeddingEngine}) {
    return MeetingIndexer(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      summaryRepository: summaryRepository,
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

  Future<int> insertMeeting({MeetingStatus status = MeetingStatus.summarizing}) {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Standup',
        source: MeetingSource.recorded,
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> insertTranscript(int meetingId, {String fullText = 'Discussed the quarterly budget.'}) {
    return transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: meetingId,
        language: 'en',
        fullText: fullText,
        segments: const [],
        createdAt: DateTime(2026, 1, 1),
      ),
    ).then((_) {});
  }

  Future<void> insertSummary(int meetingId) {
    return summaryRepository.insert(
      Summary(
        id: null,
        meetingId: meetingId,
        summaryText: 'Budget approved for next year.',
        minutesOfMeeting: 'Full minutes here.',
        keyTopics: const ['budget', 'roadmap'],
        modelUsed: 'fake-model',
        generatedAt: DateTime(2026, 1, 1),
      ),
    ).then((_) {});
  }

  test('indexes both the transcript and the summary as independent sources, '
      'and marks the meeting ready', () async {
    final meetingId = await insertMeeting();
    await insertTranscript(meetingId);
    await insertSummary(meetingId);

    await buildIndexer()(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.ready);
    expect(meeting.errorMessage, isNull);

    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(chunks, isNotEmpty);
    expect(chunks.any((c) => c.contentType.name == 'transcript'), isTrue);
    expect(chunks.any((c) => c.contentType.name == 'summary'), isTrue);
  });

  test('indexes only the transcript when there is no summary yet', () async {
    final meetingId = await insertMeeting();
    await insertTranscript(meetingId);

    await buildIndexer()(meetingId);

    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(chunks, isNotEmpty);
    expect(chunks.every((c) => c.contentType.name == 'transcript'), isTrue);
  });

  test('re-indexing replaces the transcript\'s chunks and the summary\'s '
      'chunks independently, without duplicating either', () async {
    final meetingId = await insertMeeting();
    await insertTranscript(meetingId);
    await insertSummary(meetingId);
    final indexer = buildIndexer();

    await indexer(meetingId);
    final firstPassCount = (await knowledgeChunkRepository.getForMeeting(meetingId)).length;

    await indexer(meetingId);
    final secondPassCount = (await knowledgeChunkRepository.getForMeeting(meetingId)).length;

    expect(secondPassCount, firstPassCount);
  });

  test('does nothing when neither a transcript nor a summary exists',
      () async {
    final meetingId = await insertMeeting();

    await buildIndexer()(meetingId);

    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.summarizing); // unchanged
  });

  test('embedding failure marks the meeting as error and persists no '
      'chunks', () async {
    final meetingId = await insertMeeting();
    await insertTranscript(meetingId);
    await insertSummary(meetingId);

    await buildIndexer(
      embeddingEngine: FakeEmbeddingEngine(errorToThrow: Exception('embedding crashed')),
    )(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.error);
    expect(meeting.errorMessage, contains('embedding crashed'));
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
  });

  test('does nothing for an unknown meeting id', () async {
    await buildIndexer()(9999); // should not throw
  });
}
