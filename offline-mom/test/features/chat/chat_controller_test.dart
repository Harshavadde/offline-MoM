// Tests ChatController (features/chat/presentation/providers/chat_providers.dart)
// through a ProviderContainer with only the leaf providers it actually reads
// (chatSessionRepositoryProvider, chatMessageRepositoryProvider,
// llmRequestQueueProvider, workspaceChatUseCaseProvider) overridden to point
// at a throwaway in-memory database and fake/controllable engines - mirrors
// the pattern established for NotesController in
// test/features/meetings/notes_controller_test.dart.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/features/chat/general_chat_use_case.dart';
import 'package:offline_mom/features/chat/presentation/providers/chat_providers.dart';
import 'package:offline_mom/features/chat/workspace_chat_use_case.dart';
import 'package:offline_mom/models/chat_message.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/chat_message_repository.dart';
import 'package:offline_mom/repositories/chat_session_repository.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/llm_engine.dart';
import 'package:offline_mom/services/ai/llm_request_queue.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/hybrid_retrieval_pipeline.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/keyword_search_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

/// Polls a real wall-clock deadline instead of draining a fixed tick count
/// of `Future.delayed(Duration.zero)` - lets a test wait for a chain like
/// `sendMessage`'s retrieval-then-enqueue steps to reach a given point
/// (e.g. `isSending` flipping true, or
/// [_ControllableLlmEngine.answerQuestionStream] having actually been
/// called) by polling [condition] against a real wall-clock [timeout]. A
/// fixed tick count is a guess at how many real event-loop turns
/// retrieval's sqlite-ffi round-trips need, and that number isn't just
/// machine-dependent but *process-lifetime*-dependent - measured
/// empirically, a fixed-tick wait here passed reliably when its test file
/// ran alone, but started needing far more real event-loop turns once run
/// as part of the full suite (hundreds of prior tests deep in the same
/// long-lived Dart VM process, likely from accumulated Timer/isolate
/// overhead elsewhere in the suite - see R-23,
/// docs/v2/implementation/04-risk-register.md). A real-time deadline is
/// the one bound that stays correct regardless of how many hops the wait
/// actually needs.
Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// A controllable [LlmEngine] whose [answerQuestionStream] holds a pending
/// [Completer] until [complete] is called, and delivers tokens on demand via
/// [emitToken] - lets tests observe streaming/cancellation mid-flight, which
/// [FakeLlmEngine] (resolves essentially immediately) can't do.
class _ControllableLlmEngine implements LlmEngine {
  _ControllableLlmEngine({this.holdModelReady = false});

  /// When false (the default, preserving every existing test's behavior
  /// unchanged), [ensureModelReady] resolves immediately - `ChatController
  /// ._prepareModel()`'s new "preparing model" phase is effectively
  /// instantaneous, exactly like every other fake engine. Set true only by
  /// the dedicated `isPreparingModel` test below, which needs to hold that
  /// phase open long enough to observe it.
  final bool holdModelReady;
  Completer<void>? _modelReadyCompleter;

  void Function(String)? _onToken;
  Completer<String>? _completer;

  @override
  Future<String> answerQuestionStream(
    String context,
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) {
    _onToken = onToken;
    final completer = Completer<String>();
    _completer = completer;
    return completer.future;
  }

  void emitToken(String token) => _onToken?.call(token);
  void complete(String answer) => _completer?.complete(answer);

  /// True once [answerQuestionStream] has actually been called and
  /// registered its `onToken` callback - lets a test wait for the request
  /// to have genuinely started before calling [emitToken], instead of
  /// guessing how many event-loop ticks that takes.
  bool get hasPendingCall => _onToken != null;

  /// Same controllable-completer behavior as [answerQuestionStream] - tests
  /// in this file don't need to distinguish which of the two prompt modes
  /// hybrid retrieval actually chose (that depends on `FakeEmbeddingEngine`'s
  /// deterministic-but-not-semantic similarity output for whatever content
  /// each test indexed), only that *some* request reaches this controllable
  /// engine and blocks until released.
  @override
  Future<String> answerGeneralKnowledgeStream(
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) {
    _onToken = onToken;
    final completer = Completer<String>();
    _completer = completer;
    return completer.future;
  }

  @override
  Future<String> answerQuestion(String context, String question) => throw UnimplementedError();

  @override
  Future<LlmSummaryResult> generateSummary(
    String transcriptText, {
    void Function()? onPreparingModel,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> generateFromPrompt(String systemPrompt, String userPrompt) =>
      throw UnimplementedError();

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) {
    if (!holdModelReady) return Future.value();
    final completer = Completer<void>();
    _modelReadyCompleter = completer;
    return completer.future;
  }

  /// True once [ensureModelReady] has actually been called (only reachable
  /// when [holdModelReady] is true) - lets a test wait for the "preparing
  /// model" phase to have genuinely started before asserting on it or
  /// releasing it.
  bool get hasPendingModelReady => _modelReadyCompleter != null;

  void completeModelReady() => _modelReadyCompleter?.complete();
}

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late DocumentRepository documentRepository;
  late ChatSessionRepository chatSessionRepository;
  late ChatMessageRepository chatMessageRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;
  late IndexingService indexingService;
  late HybridRetrievalPipeline hybridRetrievalPipeline;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
    chatSessionRepository = SqfliteChatSessionRepository(db);
    chatMessageRepository = SqfliteChatMessageRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
    final embeddingEngine = FakeEmbeddingEngine();
    final vectorStore = BruteForceVectorStore(knowledgeChunkRepository: knowledgeChunkRepository);
    indexingService = DefaultIndexingService(
      chunkingService: const DefaultChunkingService(),
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
      knowledgeChunkRepository: knowledgeChunkRepository,
    );
    hybridRetrievalPipeline = HybridRetrievalPipeline(
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
      keywordSearchService: SqfliteKeywordSearchService(db),
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  ProviderContainer buildContainer({LlmEngine? llmEngine, LlmRequestQueue? llmRequestQueue}) {
    final queue = llmRequestQueue ?? DefaultLlmRequestQueue();
    final engine = llmEngine ?? FakeLlmEngine(answer: 'A generated answer.');
    return ProviderContainer(
      overrides: [
        chatSessionRepositoryProvider.overrideWithValue(chatSessionRepository),
        chatMessageRepositoryProvider.overrideWithValue(chatMessageRepository),
        llmRequestQueueProvider.overrideWithValue(queue),
        // `ChatController._prepareModel()` reads this directly (not just
        // through the use cases below) to surface a distinct "preparing
        // model" state before generation - must be overridden here too, or
        // every test would otherwise construct a real `LlamaDartLlmEngine`
        // and attempt genuine native model loading inside `flutter test`.
        llmEngineProvider.overrideWithValue(engine),
        workspaceChatUseCaseProvider.overrideWithValue(
          WorkspaceChatUseCase(
            chatSessionRepository: chatSessionRepository,
            chatMessageRepository: chatMessageRepository,
            hybridRetrievalPipeline: hybridRetrievalPipeline,
            meetingRepository: meetingRepository,
            documentRepository: documentRepository,
            llmEngine: engine,
            llmRequestQueue: queue,
          ),
        ),
        generalChatUseCaseProvider.overrideWithValue(
          GeneralChatUseCase(
            chatSessionRepository: chatSessionRepository,
            chatMessageRepository: chatMessageRepository,
            llmEngine: engine,
            llmRequestQueue: queue,
          ),
        ),
      ],
    );
  }

  Future<int> insertMeeting({String title = 'Standup'}) {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: title,
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> indexMeetingTranscript(int meetingId, String text) {
    return indexingService.indexContent(
      contentType: ContentType.transcript,
      sourceId: meetingId,
      meetingId: meetingId,
      text: text,
    );
  }

  test('startNewConversation resets to a fresh, unscoped-session state',
      () async {
    container = buildContainer();
    final notifier = container.read(chatControllerProvider.notifier);

    notifier.startNewConversation(scope: ChatScope.meeting, meetingId: 7);

    final state = container.read(chatControllerProvider);
    expect(state.scope, ChatScope.meeting);
    expect(state.meetingId, 7);
    expect(state.hasActiveSession, isFalse);
    expect(state.messages, isEmpty);
  });

  test('chatSessionListProvider sorts pinned conversations first '
      '(Phase 2B "pin conversation", ADR-028)', () async {
    container = buildContainer();
    final now = DateTime(2026, 1, 1);
    final older = ChatSession(
      id: null,
      title: 'Older, pinned',
      scope: ChatScope.workspace,
      createdAt: now,
      updatedAt: now,
      isPinned: true,
    );
    final newer = ChatSession(
      id: null,
      title: 'Newer, unpinned',
      scope: ChatScope.workspace,
      createdAt: now.add(const Duration(minutes: 5)),
      updatedAt: now.add(const Duration(minutes: 5)),
    );
    final olderId = await chatSessionRepository.insert(older);
    final newerId = await chatSessionRepository.insert(newer);

    final sessions = await container.read(chatSessionListProvider.future);

    expect(sessions.map((s) => s.id), [olderId, newerId]);
  });

  test('setScope is a no-op once a conversation has an active session',
      () async {
    container = buildContainer();
    final notifier = container.read(chatControllerProvider.notifier);
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'Budget discussion notes here.');
    notifier.startNewConversation(scope: ChatScope.meeting, meetingId: meetingId);

    await notifier.sendMessage('budget');
    expect(container.read(chatControllerProvider).hasActiveSession, isTrue);

    notifier.setScope(ChatScope.workspace);

    final state = container.read(chatControllerProvider);
    expect(state.scope, ChatScope.meeting);
    expect(state.meetingId, meetingId);
  });

  test('sendMessage lazily creates a session scoped correctly and persists '
      'both turns', () async {
    container = buildContainer();
    final notifier = container.read(chatControllerProvider.notifier);
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'Budget discussion notes here.');
    notifier.startNewConversation(scope: ChatScope.meeting, meetingId: meetingId);

    await notifier.sendMessage('what was discussed?');

    final state = container.read(chatControllerProvider);
    expect(state.hasActiveSession, isTrue);
    expect(state.session!.scope, ChatScope.meeting);
    expect(state.session!.meetingId, meetingId);
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, ChatMessageRole.user);
    expect(state.messages[1].role, ChatMessageRole.assistant);
    expect(state.isSending, isFalse);
    expect(state.streamingText, isNull);

    final persisted = await chatMessageRepository.getForSession(state.session!.id!);
    expect(persisted, hasLength(2));
  });

  test('sendMessage with nothing indexed answers from general knowledge '
      'instead of a fixed fallback string (Phase 6B, ADR-037)', () async {
    container = buildContainer(llmEngine: FakeLlmEngine(answer: 'A general-knowledge answer.'));
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation();

    await notifier.sendMessage('anything');

    final state = container.read(chatControllerProvider);
    expect(state.error, isNull);
    expect(state.messages, hasLength(2));
    expect(state.messages[1].content, 'A general-knowledge answer.');
    expect(state.messages[1].answerProvenance, AnswerProvenance.generalKnowledge);
    expect(state.messages[1].sourcesJson, isNull);
  });

  test('a generation failure sets error and retry() re-sends the same '
      'question', () async {
    container = buildContainer(
      llmEngine: FakeLlmEngine(errorToThrow: Exception('model crashed')),
    );
    final notifier = container.read(chatControllerProvider.notifier);
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'Budget discussion notes here.');
    notifier.startNewConversation(scope: ChatScope.meeting, meetingId: meetingId);

    await notifier.sendMessage('what was discussed?');

    var state = container.read(chatControllerProvider);
    expect(state.error, isNotNull);
    expect(state.isSending, isFalse);
    // Only the user's message made it in - the failed turn produced no
    // assistant message.
    expect(state.messages, hasLength(1));

    notifier.retry();
    // retry() re-invokes the same failing engine, so it fails again -
    // asserting only that a second attempt was actually made (a second
    // user-message row would appear if it re-sent).
    await Future<void>.delayed(Duration.zero);
    state = container.read(chatControllerProvider);
    expect(state.messages.where((m) => m.role == ChatMessageRole.user), hasLength(2));
  });

  test(
      'a fast double-tap of sendMessage() on a brand-new conversation only ever '
      'creates one session and sends one message - real-device QA finding: '
      'isSending was previously only set true *after* awaiting session creation, '
      'leaving a real window where a second call in the same microtask could pass '
      'the state.isSending guard too and race to create a second session',
      () async {
    container = buildContainer();
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation();

    // Deliberately not awaited between calls - both fire before either
    // await inside sendMessage() resolves, reproducing the exact race
    // window a fast double-tap of the Send button hits.
    final first = notifier.sendMessage('what was discussed?');
    final second = notifier.sendMessage('what was discussed?');
    await first;
    await second;

    final allSessions = await chatSessionRepository.getAll();
    expect(allSessions, hasLength(1));

    final state = container.read(chatControllerProvider);
    expect(
      state.messages.where((m) => m.role == ChatMessageRole.user),
      hasLength(1),
    );
  });

  test('cancel() while the request is still queued behind another one '
      'returns to idle and persists no assistant message', () async {
    final queue = DefaultLlmRequestQueue();
    final controllable = _ControllableLlmEngine();
    container = buildContainer(llmEngine: controllable, llmRequestQueue: queue);
    final notifier = container.read(chatControllerProvider.notifier);
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'Budget discussion notes here.');
    notifier.startNewConversation(scope: ChatScope.meeting, meetingId: meetingId);

    // Occupy the queue first so the upcoming chat request lands in _pending.
    final blockerCompleter = Completer<String>();
    final blocker = queue.enqueue(
      LlmQueueRequest(isForeground: true, run: () => blockerCompleter.future),
    );

    // Track the queue's own composition rather than `isSending` (which
    // flips true as soon as `sendMessage` starts, well before retrieval
    // finishes and the request actually reaches the queue) - waiting on
    // the wrong signal here previously let `cancel()` run before
    // `ChatController._activeRequestId` was ever set, so `queue.cancel()`
    // was silently never called and the still-pending request sat behind
    // the blocker forever, deadlocking `await sendFuture` below.
    LlmQueueSnapshot? latestSnapshot;
    final statusSub = queue.statusStream.listen((s) => latestSnapshot = s);
    addTearDown(statusSub.cancel);

    final sendFuture = notifier.sendMessage('what was discussed?');
    await _pumpUntil(() => (latestSnapshot?.pendingForeground ?? 0) >= 1);
    expect(container.read(chatControllerProvider).isSending, isTrue);

    notifier.cancel();
    await sendFuture;

    final state = container.read(chatControllerProvider);
    expect(state.isSending, isFalse);
    expect(state.streamingText, isNull);
    expect(state.messages.any((m) => m.role == ChatMessageRole.assistant), isFalse);

    final persisted = await chatMessageRepository.getForSession(state.session!.id!);
    expect(persisted.any((m) => m.role == ChatMessageRole.assistant), isFalse);

    // Release the blocker so the queue doesn't leave a dangling request.
    blockerCompleter.complete('blocker done');
    await blocker.result;
  });

  test('deleteMessage removes exactly that message from state and the '
      'database (Phase 8B.1, Priority 3)', () async {
    container = buildContainer();
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation();
    await notifier.sendMessage('first question');

    final assistantMessage =
        container.read(chatControllerProvider).messages.firstWhere((m) => m.role == ChatMessageRole.assistant);
    await notifier.deleteMessage(assistantMessage);

    final state = container.read(chatControllerProvider);
    expect(state.messages, hasLength(1));
    expect(state.messages.single.role, ChatMessageRole.user);

    final persisted = await chatMessageRepository.getForSession(state.session!.id!);
    expect(persisted, hasLength(1));
  });

  test('editAndResend replaces the edited message and everything after it - '
      'the old turn never coexists with the new one (Phase 8B.1, Priority 2)',
      () async {
    container = buildContainer(llmEngine: FakeLlmEngine(answer: 'Second answer.'));
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation();
    await notifier.sendMessage('original question');

    final originalQuestion =
        container.read(chatControllerProvider).messages.firstWhere((m) => m.role == ChatMessageRole.user);

    await notifier.editAndResend(originalQuestion, 'edited question');

    final state = container.read(chatControllerProvider);
    expect(state.messages, hasLength(2));
    expect(state.messages[0].content, 'edited question');
    expect(state.messages[1].content, 'Second answer.');
    // The stale (pre-edit) turn is gone entirely, not just hidden - both in
    // memory and in the database.
    expect(state.messages.any((m) => m.content == 'original question'), isFalse);

    final persisted = await chatMessageRepository.getForSession(state.session!.id!);
    expect(persisted, hasLength(2));
    expect(persisted.any((m) => m.content == 'original question'), isFalse);
  });

  test('regenerateMessage replaces the last answer in place - the question '
      'is never duplicated (Phase 8B.1, Priority 3)', () async {
    container = buildContainer(llmEngine: FakeLlmEngine(answer: 'First answer.'));
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation();
    await notifier.sendMessage('the question');

    final firstAnswer =
        container.read(chatControllerProvider).messages.firstWhere((m) => m.role == ChatMessageRole.assistant);

    // This container's FakeLlmEngine always returns the same fixed answer,
    // so this asserts the *shape* of the result after regenerating (still
    // exactly one question, one answer, with a new row id) rather than a
    // changed answer string.
    await notifier.regenerateMessage(firstAnswer);

    final state = container.read(chatControllerProvider);
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, ChatMessageRole.user);
    expect(state.messages[0].content, 'the question');
    expect(state.messages[1].role, ChatMessageRole.assistant);
    expect(state.messages[1].content, 'First answer.');
    // A brand-new assistant row (different id) replaced the old one - not
    // the same row still sitting there.
    expect(state.messages[1].id, isNot(firstAnswer.id));

    final persisted = await chatMessageRepository.getForSession(state.session!.id!);
    expect(persisted, hasLength(2));
    expect(persisted.where((m) => m.role == ChatMessageRole.user), hasLength(1));
  });

  test('cancel() while the request is already running abandons it: idle '
      'immediately, and the eventually-arriving answer is never shown or '
      'persisted', () async {
    final queue = DefaultLlmRequestQueue();
    final controllable = _ControllableLlmEngine();
    container = buildContainer(llmEngine: controllable, llmRequestQueue: queue);
    final notifier = container.read(chatControllerProvider.notifier);
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'Budget discussion notes here.');
    notifier.startNewConversation(scope: ChatScope.meeting, meetingId: meetingId);

    final sendFuture = notifier.sendMessage('what was discussed?');
    // Let retrieval + enqueue run, so the request actually starts (queue is
    // otherwise empty, so it runs immediately - no blocker needed here).
    // Polled rather than a fixed tick count: how many real event-loop turns
    // retrieval's sqlite ffi round-trips take is machine-dependent, and a
    // fixed budget that's comfortable on one machine can be too tight on
    // another.
    await _pumpUntil(() => controllable.hasPendingCall);
    controllable.emitToken('Partial ');
    await _pumpUntil(
      () => container.read(chatControllerProvider).streamingText == 'Partial ',
    );

    var state = container.read(chatControllerProvider);
    expect(state.isSending, isTrue);
    expect(state.streamingText, 'Partial ');

    notifier.cancel();
    state = container.read(chatControllerProvider);
    expect(state.isSending, isFalse);
    expect(state.streamingText, isNull);

    // The generation finally "arrives" after the user already cancelled.
    controllable.complete('Partial answer that arrived too late.');
    await sendFuture;

    state = container.read(chatControllerProvider);
    expect(state.messages.any((m) => m.role == ChatMessageRole.assistant), isFalse);
    final persisted = await chatMessageRepository.getForSession(state.session!.id!);
    expect(persisted.any((m) => m.role == ChatMessageRole.assistant), isFalse);
  });

  // M2.1/FR-31: General Chat.

  test('sendMessage in general scope routes through GeneralChatUseCase - no retrieval, no citations',
      () async {
    container = buildContainer(llmEngine: FakeLlmEngine(answer: 'General answer.'));
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation(scope: ChatScope.general);

    await notifier.sendMessage('What is the capital of France?');

    final state = container.read(chatControllerProvider);
    expect(state.session!.scope, ChatScope.general);
    final assistant = state.messages.last;
    expect(assistant.role, ChatMessageRole.assistant);
    expect(assistant.content, 'General answer.');
    expect(assistant.answerProvenance, AnswerProvenance.generalKnowledge);
    expect(assistant.sourcesJson, isNull);
  });

  test('a general-scope conversation persists and can be reopened via openSession', () async {
    container = buildContainer(llmEngine: FakeLlmEngine(answer: 'General answer.'));
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation(scope: ChatScope.general);
    await notifier.sendMessage('Q1');
    final sessionId = container.read(chatControllerProvider).session!.id!;

    notifier.startNewConversation();
    await notifier.openSession(sessionId);

    final state = container.read(chatControllerProvider);
    expect(state.scope, ChatScope.general);
    expect(state.messages, hasLength(2));
  });

  test('a general-scope conversation can be deleted like any other', () async {
    container = buildContainer(llmEngine: FakeLlmEngine(answer: 'General answer.'));
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation(scope: ChatScope.general);
    await notifier.sendMessage('Q1');
    final sessionId = container.read(chatControllerProvider).session!.id!;

    await container.read(deleteChatSessionUseCaseProvider)(sessionId);

    expect(await chatSessionRepository.getById(sessionId), isNull);
  });

  test('isPreparingModel is true while the model is loading and false once generation starts',
      () async {
    final controllable = _ControllableLlmEngine(holdModelReady: true);
    container = buildContainer(llmEngine: controllable);
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation(scope: ChatScope.general);

    final sendFuture = notifier.sendMessage('Q');
    await _pumpUntil(() => controllable.hasPendingModelReady);

    var state = container.read(chatControllerProvider);
    expect(state.isSending, isTrue);
    expect(state.isPreparingModel, isTrue);

    controllable.completeModelReady();
    await _pumpUntil(() => controllable.hasPendingCall);

    state = container.read(chatControllerProvider);
    expect(state.isPreparingModel, isFalse, reason: 'generation has started - no longer "preparing"');

    controllable.complete('Answer.');
    await sendFuture;

    state = container.read(chatControllerProvider);
    expect(state.isSending, isFalse);
    expect(state.isPreparingModel, isFalse);
  });

  test('cancelling while the model is still loading discards the turn once it finishes loading',
      () async {
    final controllable = _ControllableLlmEngine(holdModelReady: true);
    container = buildContainer(llmEngine: controllable);
    final notifier = container.read(chatControllerProvider.notifier);
    notifier.startNewConversation(scope: ChatScope.general);

    final sendFuture = notifier.sendMessage('Q');
    await _pumpUntil(() => controllable.hasPendingModelReady);

    notifier.cancel();
    var state = container.read(chatControllerProvider);
    expect(state.isSending, isFalse);

    // The model finishes loading only after the user already cancelled -
    // generation must never actually start.
    controllable.completeModelReady();
    await sendFuture;

    expect(controllable.hasPendingCall, isFalse,
        reason: 'a cancelled-during-load turn must never reach the engine\'s generate call');
    state = container.read(chatControllerProvider);
    expect(state.messages.any((m) => m.role == ChatMessageRole.assistant), isFalse);
  });
}
