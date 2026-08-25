import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/chat/general_chat_use_case.dart';
import 'package:offline_mom/models/chat_message.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/repositories/chat_message_repository.dart';
import 'package:offline_mom/repositories/chat_session_repository.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/llm_request_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ChatSessionRepository chatSessionRepository;
  late ChatMessageRepository chatMessageRepository;
  late LlmRequestQueue llmRequestQueue;

  setUp(() async {
    db = await openTestDatabase();
    chatSessionRepository = SqfliteChatSessionRepository(db);
    chatMessageRepository = SqfliteChatMessageRepository(db);
    llmRequestQueue = DefaultLlmRequestQueue();
  });

  tearDown(() => db.close());

  Future<ChatSession> insertGeneralSession() async {
    final now = DateTime(2026, 1, 1);
    final draft = ChatSession(
      id: null,
      title: 'General chat',
      scope: ChatScope.general,
      createdAt: now,
      updatedAt: now,
    );
    final id = await chatSessionRepository.insert(draft);
    return draft.copyWith(id: id);
  }

  GeneralChatUseCase buildUseCase({FakeLlmEngine? llmEngine}) {
    return GeneralChatUseCase(
      chatSessionRepository: chatSessionRepository,
      chatMessageRepository: chatMessageRepository,
      llmEngine: llmEngine ?? FakeLlmEngine(),
      llmRequestQueue: llmRequestQueue,
    );
  }

  test('answers from the model\'s own general knowledge, never retrieval - persists both turns', () async {
    final session = await insertGeneralSession();
    final engine = FakeLlmEngine(answer: 'A general-knowledge answer.');

    final assistantMessage = await buildUseCase(llmEngine: engine).call(
      session: session,
      question: 'What is the capital of France?',
    );

    expect(assistantMessage, isNotNull);
    expect(assistantMessage!.content, 'A general-knowledge answer.');
    expect(assistantMessage.answerProvenance, AnswerProvenance.generalKnowledge);
    expect(assistantMessage.sourcesJson, isNull);

    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages, hasLength(2));
    expect(messages[0].role, ChatMessageRole.user);
    expect(messages[0].content, 'What is the capital of France?');
    expect(messages[1].role, ChatMessageRole.assistant);
  });

  test('never attaches citations - sourcesJson is always null, regardless of question content', () async {
    final session = await insertGeneralSession();
    final assistantMessage = await buildUseCase(llmEngine: FakeLlmEngine(answer: 'Answer.')).call(
      session: session,
      question: 'Tell me about my meetings.',
    );

    expect(assistantMessage!.sourcesJson, isNull);
  });

  test('streams the answer token-by-token via onToken before resolving', () async {
    final session = await insertGeneralSession();
    final tokens = <String>[];

    await buildUseCase(llmEngine: FakeLlmEngine(answer: 'one two three')).call(
      session: session,
      question: 'Q',
      onToken: tokens.add,
    );

    expect(tokens.join(), 'one two three');
  });

  test('a follow-up question is answered with the prior turn as history', () async {
    final session = await insertGeneralSession();
    final engine = FakeLlmEngine(answer: 'Second answer.');
    final useCase = buildUseCase(llmEngine: engine);

    await useCase.call(session: session, question: 'First question');
    await useCase.call(session: session, question: 'Second question');

    expect(engine.lastHistory, isNotEmpty);
    expect(engine.lastHistory.first.text, 'First question');
  });

  test('persistQuestion: false does not insert a second copy of the question', () async {
    final session = await insertGeneralSession();
    await chatMessageRepository.insert(
      ChatMessage(
        id: null,
        sessionId: session.id!,
        role: ChatMessageRole.user,
        content: 'Already persisted question',
        createdAt: DateTime.now(),
      ),
    );

    await buildUseCase().call(
      session: session,
      question: 'Already persisted question',
      persistQuestion: false,
    );

    final userMessages = (await chatMessageRepository.getForSession(session.id!))
        .where((m) => m.role == ChatMessageRole.user)
        .toList();
    expect(userMessages, hasLength(1));
  });

  test('isAbandoned returning true discards the answer: returns null and persists no assistant message', () async {
    final session = await insertGeneralSession();

    final result = await buildUseCase().call(
      session: session,
      question: 'Q',
      isAbandoned: () => true,
    );

    expect(result, isNull);
    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages.where((m) => m.role == ChatMessageRole.assistant), isEmpty);
  });

  test('an engine error propagates and persists no assistant message', () async {
    final session = await insertGeneralSession();

    await expectLater(
      buildUseCase(llmEngine: FakeLlmEngine(errorToThrow: Exception('engine failed'))).call(
        session: session,
        question: 'Q',
      ),
      throwsA(isA<Exception>()),
    );

    final messages = await chatMessageRepository.getForSession(session.id!);
    expect(messages.where((m) => m.role == ChatMessageRole.assistant), isEmpty);
  });
}
