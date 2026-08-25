import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/ai_summary/generate_meeting_summary_use_case.dart';
import 'package:offline_mom/features/meetings/meeting_indexer.dart';
import 'package:offline_mom/features/meetings/process_new_meeting_use_case.dart';
import 'package:offline_mom/features/transcription/transcribe_meeting_use_case.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/action_item_repository.dart';
import 'package:offline_mom/repositories/decision_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:offline_mom/services/ai/chunked_summarization_service.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
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
  late ActionItemRepository actionItemRepository;
  late DecisionRepository decisionRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;
  late Directory tempDir;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
    actionItemRepository = SqfliteActionItemRepository(db);
    decisionRepository = SqfliteDecisionRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
    tempDir = await Directory.systemTemp.createTemp('process_new_meeting_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ProcessNewMeetingUseCase buildUseCase({
    FakeSpeechToTextEngine? sttEngine,
    FakeLlmEngine? llmEngine,
    FakeEmbeddingEngine? embeddingEngine,
  }) {
    final transcribe = TranscribeMeetingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      speechToTextEngine: sttEngine ?? FakeSpeechToTextEngine(),
    );
    final summarize = GenerateMeetingSummaryUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      summaryRepository: summaryRepository,
      actionItemRepository: actionItemRepository,
      decisionRepository: decisionRepository,
      chunkedSummarizationService: ChunkedSummarizationService(
        llmEngine: llmEngine ?? FakeLlmEngine(),
        llmRequestQueue: DefaultLlmRequestQueue(),
      ),
    );
    final meetingIndexer = MeetingIndexer(
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
    return ProcessNewMeetingUseCase(
      meetingRepository: meetingRepository,
      transcribeMeetingUseCase: transcribe,
      generateMeetingSummaryUseCase: summarize,
      meetingIndexer: meetingIndexer,
    );
  }

  Future<int> insertMeeting() async {
    final audioFile = File('${tempDir.path}/audio.m4a');
    await audioFile.writeAsBytes([0]);

    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'New meeting',
        source: MeetingSource.recorded,
        status: MeetingStatus.created,
        createdAt: now,
        updatedAt: now,
        audioFilePath: audioFile.path,
      ),
    );
  }

  test('runs transcription, summarization, then indexing end to end for a '
      'fresh meeting', () async {
    final meetingId = await insertMeeting();

    await buildUseCase()(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.ready);
    expect(await transcriptRepository.getForMeeting(meetingId), isNotNull);
    expect(await summaryRepository.getForMeeting(meetingId), isNotNull);
    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(chunks, isNotEmpty);
    expect(chunks.any((c) => c.contentType.name == 'transcript'), isTrue);
    expect(chunks.any((c) => c.contentType.name == 'summary'), isTrue);
  });

  test('stops after transcription if it fails, without attempting '
      'summarization or indexing', () async {
    final meetingId = await insertMeeting();

    await buildUseCase(
      sttEngine: FakeSpeechToTextEngine(errorToThrow: Exception('stt crashed')),
    )(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.error);
    expect(await summaryRepository.getForMeeting(meetingId), isNull);
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
  });

  test('stops after summarization if it fails, without attempting '
      'indexing', () async {
    final meetingId = await insertMeeting();

    await buildUseCase(
      llmEngine: FakeLlmEngine(errorToThrow: Exception('llm crashed')),
    )(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.error);
    expect(await transcriptRepository.getForMeeting(meetingId), isNotNull);
    expect(await summaryRepository.getForMeeting(meetingId), isNull);
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
  });

  test('stops after indexing fails, leaving the transcript and summary '
      'intact', () async {
    final meetingId = await insertMeeting();

    await buildUseCase(
      embeddingEngine: FakeEmbeddingEngine(errorToThrow: Exception('embedding crashed')),
    )(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.error);
    expect(meeting.errorMessage, contains('embedding crashed'));
    expect(await transcriptRepository.getForMeeting(meetingId), isNotNull);
    expect(await summaryRepository.getForMeeting(meetingId), isNotNull);
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
  });
}
