import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/ai_summary/generate_meeting_summary_use_case.dart';
import 'package:offline_mom/features/meetings/meeting_indexer.dart';
import 'package:offline_mom/features/meetings/retry_meeting_processing_use_case.dart';
import 'package:offline_mom/features/transcription/transcribe_meeting_use_case.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/transcript.dart';
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
    tempDir = await Directory.systemTemp.createTemp('retry_use_case_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  RetryMeetingProcessingUseCase buildUseCase({
    FakeSpeechToTextEngine? sttEngine,
    FakeLlmEngine? llmEngine,
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
        embeddingEngine: FakeEmbeddingEngine(),
        vectorStore: BruteForceVectorStore(
          knowledgeChunkRepository: knowledgeChunkRepository,
        ),
        knowledgeChunkRepository: knowledgeChunkRepository,
      ),
    );
    return RetryMeetingProcessingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      summaryRepository: summaryRepository,
      transcribeMeetingUseCase: transcribe,
      generateMeetingSummaryUseCase: summarize,
      meetingIndexer: meetingIndexer,
    );
  }

  Future<int> insertMeeting({
    MeetingStatus status = MeetingStatus.error,
    String? errorMessage = 'AI summary failed: boom',
  }) async {
    // A real file, since TranscribeMeetingUseCase now checks File.exists
    // before attempting to transcribe (R5,
    // docs/v2/implementation/02-backlog.md Task 1.3.1.1).
    final audioFile = File('${tempDir.path}/audio.m4a');
    await audioFile.writeAsBytes([0]);

    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Retry me',
        source: MeetingSource.recorded,
        status: status,
        createdAt: now,
        updatedAt: now,
        audioFilePath: audioFile.path,
        errorMessage: errorMessage,
      ),
    );
  }

  test(
      'when a transcript already exists, retries only summarization and '
      'clears the previous error', () async {
    final meetingId = await insertMeeting();
    await transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: meetingId,
        language: 'en',
        fullText: 'Existing transcript text.',
        segments: const [],
        createdAt: DateTime(2026, 1, 1, 10),
      ),
    );

    await buildUseCase()(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.ready);
    expect(meeting.errorMessage, isNull);
    expect(await summaryRepository.getForMeeting(meetingId), isNotNull);
  });

  test('when no transcript exists, retries transcription then summarization',
      () async {
    final meetingId = await insertMeeting();

    await buildUseCase()(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.ready);
    expect(await transcriptRepository.getForMeeting(meetingId), isNotNull);
    expect(await summaryRepository.getForMeeting(meetingId), isNotNull);
  });

  test('stops after transcription if it fails again, without attempting '
      'summarization', () async {
    final meetingId = await insertMeeting();

    await buildUseCase(
      sttEngine: FakeSpeechToTextEngine(errorToThrow: Exception('still broken')),
    )(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.error);
    expect(meeting.errorMessage, contains('still broken'));
    expect(await summaryRepository.getForMeeting(meetingId), isNull);
  });
}
