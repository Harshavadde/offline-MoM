// RecordingController (features/recording/presentation/providers/recording_providers.dart)
// had no dedicated test coverage anywhere in this codebase before this file -
// a genuine, pre-existing gap, not something the V2 completion pass's
// RecordingForegroundService wiring introduced. Written now specifically to
// prove that wiring (start/stop/reset now also calling
// RecordingForegroundService, best-effort) didn't change any of the
// controller's existing, real behavior - mic-permission handling, meeting
// row lifecycle, state transitions.
//
// RecordingForegroundService itself is a static utility with no platform
// channel available under `flutter test` (see
// recording_foreground_service_test.dart) - its calls from this controller
// are unawaited and internally best-effort/silent, so they cannot be
// directly observed here; what this file verifies is that their presence
// doesn't alter or block any of the controller's own real behavior.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:offline_mom/features/ai_summary/generate_meeting_summary_use_case.dart';
import 'package:offline_mom/features/meetings/meeting_indexer.dart';
import 'package:offline_mom/features/meetings/process_new_meeting_use_case.dart';
import 'package:offline_mom/features/recording/presentation/providers/recording_providers.dart';
import 'package:offline_mom/features/transcription/transcribe_meeting_use_case.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/action_item_repository.dart';
import 'package:offline_mom/repositories/decision_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/recording_mark_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:offline_mom/services/ai/chunked_summarization_service.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/audio/recorder_service.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

/// Deterministic stand-in for [RecordPackageRecorderService] - no real
/// microphone/hardware access, so `RecordingController` can be tested
/// without a device, mirroring every other AI-engine fake in this suite.
class FakeRecorderService implements RecorderService {
  FakeRecorderService({this.grantPermission = true, this.startError, this.stopFilePath = '/fake/meeting.m4a'});

  final bool grantPermission;
  final Object? startError;
  final String? stopFilePath;

  bool startCalled = false;
  bool pauseCalled = false;
  bool resumeCalled = false;
  bool stopCalled = false;
  bool disposeCalled = false;

  final _stateController = StreamController<RecordingSessionState>.broadcast();
  final _amplitudeController = StreamController<RecordingAmplitude>.broadcast();

  @override
  Future<bool> hasMicrophonePermission() async => grantPermission;

  @override
  Future<void> start(String filePath) async {
    if (startError != null) throw startError!;
    startCalled = true;
    _stateController.add(RecordingSessionState.recording);
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
    _stateController.add(RecordingSessionState.paused);
  }

  @override
  Future<void> resume() async {
    resumeCalled = true;
    _stateController.add(RecordingSessionState.recording);
  }

  @override
  Future<String?> stop() async {
    stopCalled = true;
    _stateController.add(RecordingSessionState.stopped);
    return stopFilePath;
  }

  @override
  Stream<RecordingSessionState> get stateStream => _stateController.stream;

  @override
  Stream<RecordingAmplitude> get amplitudeStream => _amplitudeController.stream;

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    await _stateController.close();
    await _amplitudeController.close();
  }
}

/// `RecordingController.startRecording` computes a real on-device file path
/// via `path_provider` (`newAudioFilePath()`) before ever touching
/// [RecorderService] - real behavior, unchanged by this pass, that needs a
/// fake platform implementation to run under `flutter test` at all.
/// Mirrors `test/core/utils/toolkit_paths_test.dart`'s exact, already-
/// established pattern for the same plugin.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late Directory docsDir;
  late Database db;
  late MeetingRepository meetingRepository;
  late TranscriptRepository transcriptRepository;
  late SummaryRepository summaryRepository;
  late ActionItemRepository actionItemRepository;
  late DecisionRepository decisionRepository;
  late RecordingMarkRepository recordingMarkRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;
  late ProviderContainer container;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('recording_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);

    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
    actionItemRepository = SqfliteActionItemRepository(db);
    decisionRepository = SqfliteDecisionRepository(db);
    recordingMarkRepository = SqfliteRecordingMarkRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  ProviderContainer buildContainer({FakeRecorderService? recorder}) {
    final embeddingEngine = FakeEmbeddingEngine();
    final vectorStore = BruteForceVectorStore(knowledgeChunkRepository: knowledgeChunkRepository);
    final indexingService = DefaultIndexingService(
      chunkingService: const DefaultChunkingService(),
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
      knowledgeChunkRepository: knowledgeChunkRepository,
    );
    final transcribe = TranscribeMeetingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      speechToTextEngine: FakeSpeechToTextEngine(),
    );
    final summarize = GenerateMeetingSummaryUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      summaryRepository: summaryRepository,
      actionItemRepository: actionItemRepository,
      decisionRepository: decisionRepository,
      chunkedSummarizationService: ChunkedSummarizationService(
        llmEngine: FakeLlmEngine(),
        llmRequestQueue: DefaultLlmRequestQueue(),
      ),
    );
    final meetingIndexer = MeetingIndexer(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      summaryRepository: summaryRepository,
      indexingService: indexingService,
    );

    return ProviderContainer(
      overrides: [
        meetingRepositoryProvider.overrideWithValue(meetingRepository),
        recordingMarkRepositoryProvider.overrideWithValue(recordingMarkRepository),
        recorderServiceProvider.overrideWithValue(recorder ?? FakeRecorderService()),
        processNewMeetingUseCaseProvider.overrideWithValue(
          ProcessNewMeetingUseCase(
            meetingRepository: meetingRepository,
            transcribeMeetingUseCase: transcribe,
            generateMeetingSummaryUseCase: summarize,
            meetingIndexer: meetingIndexer,
          ),
        ),
      ],
    );
  }

  test('denied microphone permission surfaces RecordingFailed and creates no meeting row', () async {
    container = buildContainer(recorder: FakeRecorderService(grantPermission: false));
    final notifier = container.read(recordingControllerProvider.notifier);

    await notifier.startRecording('Standup');

    final state = container.read(recordingControllerProvider);
    expect(state, isA<RecordingFailed>());
    expect((state as RecordingFailed).message, contains('microphone'));
    expect(await meetingRepository.getAll(), isEmpty);
  });

  test('a recorder start() failure deletes the just-created meeting row rather than orphaning it', () async {
    container = buildContainer(recorder: FakeRecorderService(startError: Exception('mic busy')));
    final notifier = container.read(recordingControllerProvider.notifier);

    await notifier.startRecording('Standup');

    final state = container.read(recordingControllerProvider);
    expect(state, isA<RecordingFailed>());
    expect(await meetingRepository.getAll(), isEmpty);
  });

  test('startRecording creates a meeting row and transitions to RecordingInProgress', () async {
    final recorder = FakeRecorderService();
    container = buildContainer(recorder: recorder);
    final notifier = container.read(recordingControllerProvider.notifier);

    await notifier.startRecording('Standup');

    expect(recorder.startCalled, isTrue);
    final state = container.read(recordingControllerProvider);
    expect(state, isA<RecordingInProgress>());
    final meetings = await meetingRepository.getAll();
    expect(meetings, hasLength(1));
    expect(meetings.first.title, 'Standup');
    expect(meetings.first.source, MeetingSource.recorded);
  });

  test('pauseRecording/resumeRecording toggle isPaused and call through to the recorder', () async {
    final recorder = FakeRecorderService();
    container = buildContainer(recorder: recorder);
    final notifier = container.read(recordingControllerProvider.notifier);
    await notifier.startRecording('Standup');

    await notifier.pauseRecording();
    expect(recorder.pauseCalled, isTrue);
    expect((container.read(recordingControllerProvider) as RecordingInProgress).isPaused, isTrue);

    await notifier.resumeRecording();
    expect(recorder.resumeCalled, isTrue);
    expect((container.read(recordingControllerProvider) as RecordingInProgress).isPaused, isFalse);
  });

  test('addMark persists a RecordingMark for the active meeting', () async {
    container = buildContainer();
    final notifier = container.read(recordingControllerProvider.notifier);
    await notifier.startRecording('Standup');
    final meetingId = (container.read(recordingControllerProvider) as RecordingInProgress).meetingId;

    final offset = await notifier.addMark();

    expect(offset, isNotNull);
    final marks = await recordingMarkRepository.getForMeeting(meetingId);
    expect(marks, hasLength(1));
  });

  test('stopRecording calls the recorder, persists the audio path/duration, and transitions to RecordingFinished',
      () async {
    final recorder = FakeRecorderService(stopFilePath: '/fake/final.m4a');
    container = buildContainer(recorder: recorder);
    final notifier = container.read(recordingControllerProvider.notifier);
    await notifier.startRecording('Standup');
    final meetingId = (container.read(recordingControllerProvider) as RecordingInProgress).meetingId;

    await notifier.stopRecording();

    expect(recorder.stopCalled, isTrue);
    final state = container.read(recordingControllerProvider);
    expect(state, isA<RecordingFinished>());
    expect((state as RecordingFinished).meetingId, meetingId);
    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.audioFilePath, '/fake/final.m4a');

    // stopRecording() deliberately fires the transcribe/summarize/index
    // pipeline unawaited (so the UI isn't blocked on it - see its own doc
    // comment) - waited out here, not skipped, so this test's own tearDown
    // doesn't close the database out from under that still-in-flight
    // background work (which would otherwise throw a real, if harmless,
    // "database_closed" error attributed to whichever test happens to be
    // running next). Polls a real wall-clock deadline rather than a fixed
    // tick count, matching this suite's own established R-23 discipline
    // (docs/v2/implementation/04-risk-register.md).
    const terminalStatuses = {MeetingStatus.ready, MeetingStatus.error, MeetingStatus.audioMissing};
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final current = await meetingRepository.getById(meetingId);
      if (current != null && terminalStatuses.contains(current.status)) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });

  test('reset() returns to RecordingIdle', () async {
    container = buildContainer();
    final notifier = container.read(recordingControllerProvider.notifier);
    await notifier.startRecording('Standup');

    notifier.reset();

    expect(container.read(recordingControllerProvider), isA<RecordingIdle>());
  });
}
