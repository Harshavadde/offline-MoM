import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/ask/ask_about_meetings_use_case.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/summary.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late SummaryRepository summaryRepository;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
  });

  tearDown(() => db.close());

  AskAboutMeetingsUseCase buildUseCase({FakeLlmEngine? llmEngine}) {
    return AskAboutMeetingsUseCase(
      meetingRepository: meetingRepository,
      summaryRepository: summaryRepository,
      llmEngine: llmEngine ?? FakeLlmEngine(),
      llmRequestQueue: DefaultLlmRequestQueue(),
    );
  }

  Future<int> insertReadyMeeting({
    required String title,
    required String summaryText,
    List<String> keyTopics = const [],
  }) async {
    final now = DateTime(2026, 3, 1);
    final meetingId = await meetingRepository.insert(
      Meeting(
        id: null,
        title: title,
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await summaryRepository.insert(
      Summary(
        id: null,
        meetingId: meetingId,
        summaryText: summaryText,
        minutesOfMeeting: 'Minutes for $title.',
        keyTopics: keyTopics,
        modelUsed: 'fake-model',
        generatedAt: now,
      ),
    );
    return meetingId;
  }

  test('no ready meetings returns a canned answer, never calls the engine',
      () async {
    final answer = await buildUseCase(
      llmEngine: FakeLlmEngine(errorToThrow: StateError('should not be called')),
    )('What did we decide?');

    expect(answer.sourceMeetings, isEmpty);
    expect(answer.answer, contains("don't have any fully-processed meetings"));
  });

  test('a meeting with no matching keywords still falls back to a real answer '
      'when nothing scores above zero', () async {
    await insertReadyMeeting(
      title: 'Budget Review',
      summaryText: 'We discussed the quarterly budget allocation.',
    );

    final answer = await buildUseCase(
      llmEngine: FakeLlmEngine(answer: 'Fallback answer from the model.'),
    )('completely unrelated gibberish query');

    // Falls back to considering all ready meetings when nothing scores > 0,
    // per AskAboutMeetingsUseCase's own documented behavior - so it still
    // reaches the engine rather than returning the "nothing found" message.
    expect(answer.answer, 'Fallback answer from the model.');
    expect(answer.sourceMeetings, isNotEmpty);
  });

  test('scores by keyword overlap and asks the engine using the matching '
      'meeting as context', () async {
    await insertReadyMeeting(
      title: 'Budget Review',
      summaryText: 'We approved the marketing budget for next quarter.',
      keyTopics: ['budget', 'marketing'],
    );
    await insertReadyMeeting(
      title: 'Design Sync',
      summaryText: 'We reviewed the new onboarding wireframes.',
      keyTopics: ['design', 'onboarding'],
    );

    final answer = await buildUseCase(
      llmEngine: FakeLlmEngine(answer: 'The marketing budget was approved.'),
    )('What happened with the marketing budget?');

    expect(answer.answer, 'The marketing budget was approved.');
    expect(answer.sourceMeetings.map((m) => m.title), ['Budget Review']);
  });

  test('propagates an engine failure to the caller', () async {
    await insertReadyMeeting(
      title: 'Budget Review',
      summaryText: 'We approved the marketing budget.',
      keyTopics: ['budget'],
    );

    await expectLater(
      buildUseCase(
        llmEngine: FakeLlmEngine(errorToThrow: Exception('model crashed')),
      )('What about the budget?'),
      throwsException,
    );
  });
}
