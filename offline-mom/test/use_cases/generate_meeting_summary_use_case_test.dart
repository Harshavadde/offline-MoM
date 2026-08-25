import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/ai_summary/generate_meeting_summary_use_case.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/repositories/action_item_repository.dart';
import 'package:offline_mom/repositories/decision_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:offline_mom/services/ai/chunked_summarization_service.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/llm_engine.dart';
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
  late int meetingId;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
    actionItemRepository = SqfliteActionItemRepository(db);
    decisionRepository = SqfliteDecisionRepository(db);

    final now = DateTime(2026, 1, 1);
    meetingId = await meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Test meeting',
        source: MeetingSource.recorded,
        status: MeetingStatus.summarizing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() => db.close());

  GenerateMeetingSummaryUseCase buildUseCase({FakeLlmEngine? llmEngine}) {
    return GenerateMeetingSummaryUseCase(
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
  }

  Future<void> insertTranscript(String text) {
    return transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: meetingId,
        language: 'en',
        fullText: text,
        segments: [TranscriptSegment(startMs: 0, endMs: 1000, text: text)],
        createdAt: DateTime(2026, 1, 1, 10),
      ),
    );
  }

  test(
      'generates successfully: persists summary/action items/decisions, '
      'marks meeting ready', () async {
    await insertTranscript('We reviewed the budget and approved the plan.');

    await buildUseCase()(meetingId);

    final summary = await summaryRepository.getForMeeting(meetingId);
    expect(summary, isNotNull);
    expect(summary!.summaryText, 'Default fake summary.');
    expect(summary.keyTopics, ['topic one', 'topic two']);

    final actionItems = await actionItemRepository.getForMeeting(meetingId);
    expect(actionItems.map((a) => a.description), ['Do the thing']);
    expect(actionItems.single.owner, 'Alex');

    final decisions = await decisionRepository.getForMeeting(meetingId);
    expect(decisions.map((d) => d.description), ['Decided the thing']);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.ready);
  });

  test('engine failure marks the meeting as error and persists nothing',
      () async {
    await insertTranscript('Some transcript text.');

    await buildUseCase(
      llmEngine: FakeLlmEngine(errorToThrow: Exception('model crashed')),
    )(meetingId);

    expect(await summaryRepository.getForMeeting(meetingId), isNull);
    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.error);
  });

  test('does nothing when no transcript exists yet', () async {
    await buildUseCase()(meetingId);

    expect(await summaryRepository.getForMeeting(meetingId), isNull);
    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.summarizing);
  });

  test('a meeting with genuinely no action items/decisions stays ready with '
      'empty lists', () async {
    await insertTranscript('Just a casual chat, nothing actionable.');

    await buildUseCase(
      llmEngine: FakeLlmEngine(
        result: const LlmSummaryResult(
          summaryText: 'Just a casual chat.',
          minutesOfMeeting: 'No formal items discussed.',
          keyTopics: [],
          actionItems: [],
          decisions: [],
          modelUsed: 'fake-model',
        ),
      ),
    )(meetingId);

    expect(await actionItemRepository.getForMeeting(meetingId), isEmpty);
    expect(await decisionRepository.getForMeeting(meetingId), isEmpty);
    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.ready);
  });
}
