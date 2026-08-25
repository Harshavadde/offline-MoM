import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../repositories/chat_message_repository.dart';
import '../../repositories/chat_session_repository.dart';
import '../../services/ai/llm_engine.dart';
import '../../services/ai/llm_request_queue.dart';

/// [ChatScope.general] - no retrieval context, per docs/v2/06-user-journeys.md
/// Journey 3 and FR-31 (docs/v2/08-functional-requirements.md). A deliberate
/// near-mirror of `WorkspaceChatUseCase`'s shape (same signature, same
/// persistence/history/streaming/cancellation contract) minus everything
/// retrieval-related: no `HybridRetrievalPipeline`, no
/// `MeetingRepository`/`DocumentRepository`, no citations - every answer is
/// always [AnswerProvenance.generalKnowledge] via
/// [LlmEngine.answerGeneralKnowledgeStream], the same engine method
/// `WorkspaceChatUseCase` already falls back to when retrieval finds nothing
/// confidently relevant (Phase 6B, ADR-037). Reuses the same [LlmEngine] and
/// the same shared [LlmRequestQueue] `WorkspaceChatUseCase` uses - no second
/// engine, no second queue.
const _maxHistoryMessages = 12;

class GeneralChatUseCase {
  GeneralChatUseCase({
    required ChatSessionRepository chatSessionRepository,
    required ChatMessageRepository chatMessageRepository,
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
  })  : _chatSessionRepository = chatSessionRepository,
        _chatMessageRepository = chatMessageRepository,
        _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue;

  final ChatSessionRepository _chatSessionRepository;
  final ChatMessageRepository _chatMessageRepository;
  final LlmEngine _llmEngine;
  final LlmRequestQueue _llmRequestQueue;

  /// Runs one general-chat turn for [session] (must have
  /// `scope == ChatScope.general`, though this class doesn't itself enforce
  /// that - the caller picks which use case to invoke, same as
  /// `WorkspaceChatUseCase`'s callers pick it for every other scope):
  /// persists the user's [question], answers from the model's own general
  /// knowledge (no context, never a citation), and persists the answer.
  ///
  /// See `WorkspaceChatUseCase.call`'s doc comment for the full contract
  /// [onToken]/[onRequestQueued]/[isAbandoned]/[persistQuestion]/
  /// [onQuestionPersisted] share verbatim - duplicated here only because
  /// the two classes have no common supertype (deliberately: `ChatScope
  /// .general` never touches retrieval, so forcing a shared interface
  /// across both would need to make the retrieval-only parameters optional
  /// on both, which is worse than the small duplication).
  Future<ChatMessage?> call({
    required ChatSession session,
    required String question,
    void Function(String token)? onToken,
    void Function(int requestId)? onRequestQueued,
    bool Function()? isAbandoned,
    bool persistQuestion = true,
    void Function(ChatMessage persistedQuestion)? onQuestionPersisted,
  }) async {
    assert(session.id != null, 'session must already be persisted');
    final trimmed = question.trim();
    assert(trimmed.isNotEmpty, 'question must not be blank');

    final priorMessages = await _chatMessageRepository.getForSession(session.id!);
    final historySource = persistQuestion
        ? priorMessages
        : (priorMessages.isNotEmpty ? priorMessages.sublist(0, priorMessages.length - 1) : priorMessages);
    final history = _recentHistory(historySource);

    if (persistQuestion) {
      final questionMessage = ChatMessage(
        id: null,
        sessionId: session.id!,
        role: ChatMessageRole.user,
        content: trimmed,
        createdAt: DateTime.now(),
      );
      final questionId = await _chatMessageRepository.insert(questionMessage);
      onQuestionPersisted?.call(questionMessage.copyWith(id: questionId));
    }

    final handle = _llmRequestQueue.enqueue(
      LlmQueueRequest(
        isForeground: true,
        run: () => _llmEngine.answerGeneralKnowledgeStream(trimmed, onToken: onToken, history: history),
      ),
    );
    onRequestQueued?.call(handle.id);
    final answer = await handle.result;

    if (isAbandoned?.call() ?? false) return null;

    final assistantMessage = await _persist(session.id!, answer);
    await _chatSessionRepository.update(session.copyWith(updatedAt: DateTime.now()));
    return assistantMessage;
  }

  /// Same trimming rule as `WorkspaceChatUseCase._recentHistory` - kept as
  /// a separate copy rather than a shared helper for the same "no common
  /// supertype worth forcing" reasoning as [call]'s doc comment.
  List<LlmChatTurn> _recentHistory(List<ChatMessage> priorMessages) {
    final recent = priorMessages.length > _maxHistoryMessages
        ? priorMessages.sublist(priorMessages.length - _maxHistoryMessages)
        : priorMessages;
    return [
      for (final message in recent)
        LlmChatTurn(
          role: message.role == ChatMessageRole.user ? LlmChatRole.user : LlmChatRole.assistant,
          text: message.content,
        ),
    ];
  }

  Future<ChatMessage> _persist(int sessionId, String content) async {
    final message = ChatMessage(
      id: null,
      sessionId: sessionId,
      role: ChatMessageRole.assistant,
      content: content,
      createdAt: DateTime.now(),
      answerProvenance: AnswerProvenance.generalKnowledge,
    );
    final id = await _chatMessageRepository.insert(message);
    return message.copyWith(id: id);
  }
}
