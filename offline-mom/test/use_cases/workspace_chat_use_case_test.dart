import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/features/chat/workspace_chat_use_case.dart';
import 'package:offline_mom/models/chat_message.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
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

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

/// Polls a real wall-clock deadline instead of draining a **fixed** count of
/// event-loop ticks - R-23 (docs/v2/implementation/04-risk-register.md)
/// documents exactly why a fixed tick count for
/// `WorkspaceChatUseCase.call`'s multi-`await` pre-generation steps
/// (repository inserts, retrieval's embed-then-search) to settle is
/// fundamentally unreliable: how many event-loop hops that takes is
/// process-lifetime-dependent, not just machine-dependent, so a count that
/// looks sufficient running this file alone can still be too small once run
/// deep in the full suite. This mirrors `chat_controller_test.dart`'s own
/// `_pumpUntil` fix for the identical class of flake, applied here to the
/// second call site R-23 flagged as unaudited at the time.
Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// A controllable [LlmEngine] whose [answerQuestionStream] never resolves
/// until [complete] is called - lets tests exercise the queue's "still
/// queued" cancellation path deterministically (see the cancellation test
/// below), which a real or [FakeLlmEngine] instance (both resolve
/// essentially immediately) can't reliably do.
class _ControllableLlmEngine implements LlmEngine {
  final List<Completer<String>> _pending = [];

  Completer<String> _next() {
    final completer = Completer<String>();
    _pending.add(completer);
    return completer;
  }

  void completeOldest(String answer) {
    _pending.removeAt(0).complete(answer);
  }

  @override
  Future<String> answerQuestionStream(
    String context,
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) {
    return _next().future;
  }

  @override
  Future<String> answerQuestion(String context, String question) {
    return _next().future;
  }

  @override
  Future<String> answerGeneralKnowledgeStream(
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) {
    return _next().future;
  }

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
  }) async {}
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

  tearDown(() => db.close());

  WorkspaceChatUseCase buildUseCase({LlmEngine? llmEngine, LlmRequestQueue? llmRequestQueue}) {
    return WorkspaceChatUseCase(
      chatSessionRepository: chatSessionRepository,
      chatMessageRepository: chatMessageRepository,
      hybridRetrievalPipeline: hybridRetrievalPipeline,
      meetingRepository: meetingRepository,
      documentRepository: documentRepository,
      llmEngine: llmEngine ?? FakeLlmEngine(answer: 'The budget was approved.'),
      llmRequestQueue: llmRequestQueue ?? DefaultLlmRequestQueue(),
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

  Future<int> insertDocument({String title = 'Report.pdf'}) {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: title,
        originalFilename: title,
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/$title',
        status: DocumentStatus.ready,
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

  Future<void> indexDocumentText(int documentId, String text) {
    return indexingService.indexContent(
      contentType: ContentType.document,
      sourceId: documentId,
      documentId: documentId,
      text: text,
    );
  }

  Future<ChatSession> createSession({
    ChatScope scope = ChatScope.workspace,
    int? meetingId,
    int? documentId,
  }) async {
    final now = DateTime(2026, 1, 1, 9);
    final id = await chatSessionRepository.insert(
      ChatSession(
        id: null,
        title: 'A conversation',
        scope: scope,
        createdAt: now,
        updatedAt: now,
        meetingId: meetingId,
        documentId: documentId,
      ),
    );
    return (await chatSessionRepository.getById(id))!;
  }

  test('workspace scope: persists the user question, retrieves across '
      'meetings and documents, and cites both', () async {
    final meetingId = await insertMeeting(title: 'Budget Standup');
    await indexMeetingTranscript(
      meetingId,
      'The team discussed the quarterly budget and approved next steps.',
    );
    final documentId = await insertDocument(title: 'Budget Report.pdf');
    await indexDocumentText(
      documentId,
      'This report covers the quarterly budget in detail with figures.',
    );
    final session = await createSession(scope: ChatScope.workspace);

    final answer = (await buildUseCase().call(session: session, question: 'quarterly budget'))!;

    expect(answer.role, ChatMessageRole.assistant);
    expect(answer.content, 'The budget was approved.');
    expect(answer.answerProvenance, AnswerProvenance.local);

    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages, hasLength(2));
    expect(messages[0].role, ChatMessageRole.user);
    expect(messages[0].content, 'quarterly budget');
    expect(messages[1].role, ChatMessageRole.assistant);

    final sources = messages[1].sourcesJson;
    expect(sources, isNotNull);
    expect(sources, contains('Budget Standup'));
    expect(sources, contains('Budget Report.pdf'));

    final updatedSession = await chatSessionRepository.getById(session.id!);
    expect(updatedSession!.updatedAt.isAfter(session.updatedAt), isTrue);
  });

  test('meeting scope: only retrieves and cites that meeting, even when a '
      'document matches the same query', () async {
    final meetingId = await insertMeeting(title: 'Budget Standup');
    await indexMeetingTranscript(meetingId, 'The team discussed the quarterly budget.');
    final documentId = await insertDocument(title: 'Budget Report.pdf');
    await indexDocumentText(documentId, 'This report covers the quarterly budget.');
    final session = await createSession(scope: ChatScope.meeting, meetingId: meetingId);

    final answer = (await buildUseCase().call(session: session, question: 'quarterly budget'))!;

    expect(answer.sourcesJson, contains('Budget Standup'));
    expect(answer.sourcesJson, isNot(contains('Budget Report.pdf')));
  });

  test('document scope: only retrieves and cites that document, even when '
      'a meeting matches the same query', () async {
    final meetingId = await insertMeeting(title: 'Budget Standup');
    await indexMeetingTranscript(meetingId, 'The team discussed the quarterly budget.');
    final documentId = await insertDocument(title: 'Budget Report.pdf');
    await indexDocumentText(documentId, 'This report covers the quarterly budget.');
    final session = await createSession(scope: ChatScope.document, documentId: documentId);

    final answer = (await buildUseCase().call(session: session, question: 'quarterly budget'))!;

    expect(answer.sourcesJson, contains('Budget Report.pdf'));
    expect(answer.sourcesJson, isNot(contains('Budget Standup')));
  });

  test('workspace scope with nothing indexed answers from the LLM\'s general '
      'knowledge instead of a fixed fallback string (Phase 6B, ADR-037), '
      'with no fabricated citations', () async {
    final session = await createSession();
    final useCase = buildUseCase(
      llmEngine: FakeLlmEngine(answer: 'Paris is the capital of France.'),
    );

    final answer = (await useCase.call(session: session, question: 'anything at all'))!;

    expect(answer.content, 'Paris is the capital of France.');
    expect(answer.answerProvenance, AnswerProvenance.generalKnowledge);
    expect(answer.sourcesJson, isNull);
  });

  test('meeting scope with no indexed content for that meeting also answers '
      'from general knowledge, not a meeting-specific fixed string', () async {
    final meetingId = await insertMeeting();
    final session = await createSession(scope: ChatScope.meeting, meetingId: meetingId);
    final useCase = buildUseCase(
      llmEngine: FakeLlmEngine(answer: 'A general-knowledge answer.'),
    );

    final answer = (await useCase.call(session: session, question: 'anything'))!;

    expect(answer.content, 'A general-knowledge answer.');
    expect(answer.answerProvenance, AnswerProvenance.generalKnowledge);
    expect(answer.sourcesJson, isNull);
  });

  test('an LLM error during the general-knowledge fallback still propagates '
      '(no silent swallow) and persists no assistant message', () async {
    final session = await createSession();
    final useCase = buildUseCase(
      llmEngine: FakeLlmEngine(errorToThrow: Exception('model crashed')),
    );

    await expectLater(
      useCase.call(session: session, question: 'anything at all'),
      throwsA(isA<Exception>()),
    );

    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages, hasLength(1));
    expect(messages.single.role, ChatMessageRole.user);
  });

  test('streams the answer token-by-token via onToken before resolving',
      () async {
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'The quarterly budget was discussed at length.');
    final session = await createSession(scope: ChatScope.meeting, meetingId: meetingId);

    final tokens = <String>[];
    final answer = (await buildUseCase().call(
      session: session,
      question: 'budget',
      onToken: tokens.add,
    ))!;

    expect(tokens, isNotEmpty);
    expect(tokens.join(''), answer.content);
  });

  test('a follow-up question is answered with the prior turn as history '
      '(Phase 7A: conversation memory) - the first turn gets no history, '
      'the second sees the first question and answer', () async {
    final session = await createSession();
    final fakeEngine = FakeLlmEngine(answer: 'A poem about the sea.');
    final useCase = buildUseCase(llmEngine: fakeEngine);

    await useCase.call(session: session, question: 'Write a poem.');
    expect(fakeEngine.lastHistory, isEmpty);

    await useCase.call(session: session, question: 'Translate into English.');

    expect(fakeEngine.lastHistory, hasLength(2));
    expect(fakeEngine.lastHistory[0].role, LlmChatRole.user);
    expect(fakeEngine.lastHistory[0].text, 'Write a poem.');
    expect(fakeEngine.lastHistory[1].role, LlmChatRole.assistant);
    expect(fakeEngine.lastHistory[1].text, 'A poem about the sea.');
  });

  test('persistQuestion: false (Phase 8B.1 "Regenerate") does not insert a '
      'second copy of the question, and excludes it from history since it\'s '
      'the current turn, not a prior one', () async {
    final session = await createSession();
    final fakeEngine = FakeLlmEngine(answer: 'An answer.');
    final useCase = buildUseCase(llmEngine: fakeEngine);

    // Simulates a caller (ChatController.regenerateMessage) that already
    // has this exact question persisted (from the original turn) and has
    // already deleted the stale answer - only the new answer should be
    // inserted here, not another copy of the question.
    await useCase.call(session: session, question: 'the question');
    expect((await chatMessageRepository.getForSession(session.id!)), hasLength(2));

    await chatMessageRepository.deleteMessage(
      (await chatMessageRepository.getForSession(session.id!))
          .firstWhere((m) => m.role == ChatMessageRole.assistant)
          .id!,
    );

    await useCase.call(session: session, question: 'the question', persistQuestion: false);

    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages, hasLength(2));
    expect(messages.where((m) => m.role == ChatMessageRole.user), hasLength(1));
    expect(messages.where((m) => m.role == ChatMessageRole.assistant), hasLength(1));
    // The question itself isn't handed back as "history" - it's the
    // current turn, matching the normal (persistQuestion: true) path's
    // "history is fetched before this turn's question exists" contract.
    expect(fakeEngine.lastHistory, isEmpty);
  });

  test('isAbandoned returning true discards the answer: returns null and '
      'persists no assistant message', () async {
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'The quarterly budget was discussed at length.');
    final session = await createSession(scope: ChatScope.meeting, meetingId: meetingId);

    final result = await buildUseCase().call(
      session: session,
      question: 'budget',
      isAbandoned: () => true,
    );

    expect(result, isNull);
    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages, hasLength(1));
    expect(messages.single.role, ChatMessageRole.user);

    final updatedSession = await chatSessionRepository.getById(session.id!);
    expect(updatedSession!.updatedAt, session.updatedAt);
  });

  test('cancelling a still-queued request throws LlmQueueCancelledException '
      'and persists no assistant message', () async {
    final meetingId = await insertMeeting();
    await indexMeetingTranscript(meetingId, 'The quarterly budget was discussed at length.');
    final session = await createSession(scope: ChatScope.meeting, meetingId: meetingId);

    final queue = DefaultLlmRequestQueue();
    final controllable = _ControllableLlmEngine();
    final useCase = buildUseCase(llmEngine: controllable, llmRequestQueue: queue);

    // Occupy the queue with a blocking foreground request first, so the
    // chat turn below lands in _pending (still cancellable) rather than
    // starting immediately.
    final blocker = queue.enqueue(
      LlmQueueRequest(isForeground: true, run: () => controllable.answerQuestion('', '')),
    );

    int? requestId;
    final future = useCase.call(
      session: session,
      question: 'budget',
      onRequestQueued: (id) => requestId = id,
    );

    // Let the retrieval steps and the enqueue call run.
    await _pumpUntil(() => requestId != null);
    expect(requestId, isNotNull);

    final cancelled = queue.cancel(requestId!);
    expect(cancelled, isTrue);

    await expectLater(future, throwsA(isA<LlmQueueCancelledException>()));

    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages, hasLength(1));
    expect(messages.single.role, ChatMessageRole.user);

    // Release the blocker so the queue doesn't leave a dangling request.
    controllable.completeOldest('blocker done');
    await blocker.result;
  });
}
