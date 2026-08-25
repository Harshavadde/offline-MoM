import '../../core/knowledge/content_type.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/chat_source_ref.dart';
import '../../repositories/chat_message_repository.dart';
import '../../repositories/chat_session_repository.dart';
import '../../repositories/document_repository.dart';
import '../../repositories/meeting_repository.dart';
import '../../services/ai/llm_engine.dart';
import '../../services/ai/llm_request_queue.dart';
import '../../services/retrieval/context_builder.dart';
import '../../services/retrieval/hybrid_ranker.dart';
import '../../services/retrieval/hybrid_retrieval_pipeline.dart';
import '../../services/retrieval/retrieval_confidence.dart';

/// The single retrieval-backed chat implementation behind every selectable
/// [ChatScope] except [ChatScope.general] (M2.1, not this milestone) - one
/// use case, not three, per ADR-013 (docs/v2/implementation/03-decisions.md).
///
/// As of Phase 6B (Hybrid Retrieval Engine, ADR-037,
/// docs/v2/implementation/03-decisions.md), retrieval runs through
/// [HybridRetrievalPipeline] - vector *and* keyword search fused and
/// ranked, not vector search alone - and the previous "couldn't find
/// anything, here's a fixed string, never call the LLM" fallback is gone:
/// when hybrid retrieval isn't confident anything in the user's own
/// content answers the question, this use case now answers from the
/// model's own general knowledge instead
/// ([LlmEngine.answerGeneralKnowledgeStream]), persisting which prompt
/// mode was used ([AnswerProvenance]) so the UI can label the answer's
/// provenance honestly rather than imply it was grounded in content it
/// wasn't.
///
/// [ChatScope.workspace] retrieves across the whole workspace,
/// [ChatScope.meeting]/[ChatScope.document] narrow to one owner - scope
/// switching is a retrieval-filter change, never a different screen or a
/// different use case (this class's own doc comment/ADR-013).
///
/// Streaming and citations follow ADR-026: [onToken] is forwarded straight
/// to the active [LlmEngine] method for progressive UI delivery without
/// changing [LlmRequestQueue]'s single-flight contract; citations are
/// built only from chunks [HybridRetrievalPipeline] actually selected for
/// the prompt context, never parsed from the model's own text, and are
/// never attached to a general-knowledge answer (no fabricated
/// citations).
/// How many of the most recent persisted messages to offer the LLM as
/// short-term conversation memory (Phase 7A, items 4/6) - a generous upper
/// bound on turn *count*; [LlamaDartLlmEngine] applies its own character
/// budget on top of this, so this just avoids handing an unbounded,
/// session-long list across the use-case/engine boundary for a very long
/// chat.
const _maxHistoryMessages = 12;

class WorkspaceChatUseCase {
  WorkspaceChatUseCase({
    required ChatSessionRepository chatSessionRepository,
    required ChatMessageRepository chatMessageRepository,
    required HybridRetrievalPipeline hybridRetrievalPipeline,
    required MeetingRepository meetingRepository,
    required DocumentRepository documentRepository,
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
    ContextBuilder contextBuilder = const ContextBuilder(),
  })  : _chatSessionRepository = chatSessionRepository,
        _chatMessageRepository = chatMessageRepository,
        _hybridRetrievalPipeline = hybridRetrievalPipeline,
        _meetingRepository = meetingRepository,
        _documentRepository = documentRepository,
        _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue,
        _contextBuilder = contextBuilder;

  final ChatSessionRepository _chatSessionRepository;
  final ChatMessageRepository _chatMessageRepository;
  final HybridRetrievalPipeline _hybridRetrievalPipeline;
  final MeetingRepository _meetingRepository;
  final DocumentRepository _documentRepository;
  final LlmEngine _llmEngine;
  final LlmRequestQueue _llmRequestQueue;
  final ContextBuilder _contextBuilder;

  /// Runs one chat turn for [session]: persists the user's [question],
  /// runs it through [HybridRetrievalPipeline] scoped to [session.scope],
  /// answers either from retrieved content or (per the approved product
  /// decision, Phase 6B) from the model's own general knowledge, persists
  /// the answer with its [AnswerProvenance], and touches
  /// [session.updatedAt].
  ///
  /// [onToken] streams the answer progressively (ADR-026). [onRequestQueued]
  /// fires synchronously with the [LlmRequestQueue] request id the instant
  /// it's enqueued (before generation starts), letting a caller capture it
  /// for cancellation ([LlmRequestQueue.cancel], ADR-027).
  ///
  /// [isAbandoned], if provided, is checked once the LLM call resolves. When
  /// it returns true, the answer is discarded - **not** persisted as a
  /// [ChatMessage] and not counted as touching the session - and this
  /// method returns null instead. The user's own question (persisted
  /// before generation starts) is never discarded this way, matching
  /// ADR-027: only the generation step is abandonable.
  ///
  /// [persistQuestion] (Phase 8B.1, "Regenerate") - set to false when
  /// [question] is *already* the most recent persisted message in
  /// [session] (a caller regenerating an answer without re-asking the
  /// question) so it isn't inserted a second time. Retrieval and the LLM
  /// call are unaffected either way - this only changes what gets
  /// persisted, never what gets retrieved or asked.
  ///
  /// [onQuestionPersisted] (Phase 8B.1) fires synchronously right after the
  /// user's question is actually inserted, with its real database id - a
  /// caller (`ChatController.sendMessage`) uses this to patch its
  /// optimistic, `id: null` copy of the same message with the real one,
  /// since features like "Edit" need a real id to later find and delete
  /// that exact message. Never fires when [persistQuestion] is false (there
  /// is nothing new to report - the question already has a real id from
  /// its original turn).
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

    // Fetched *before* inserting this turn's question - otherwise the
    // question would appear twice (once here, once as the current turn
    // passed separately to the LLM below). When [persistQuestion] is
    // false, [question] is already the last row `getForSession` returns
    // (a regenerate caller deleted only the old *answer*), so it's
    // excluded from history the same way - it's "the current turn," not
    // a prior one.
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

    final retrieval = await _hybridRetrievalPipeline.run(
      question: trimmed,
      scope: session.scope,
      meetingId: session.meetingId,
      documentId: session.documentId,
    );

    final answerLocally =
        retrieval.confidence == RetrievalConfidence.high || retrieval.confidence == RetrievalConfidence.medium;

    final ChatMessage assistantMessage;
    if (answerLocally) {
      final resolved = await _resolveSources(retrieval.selectedChunks, retrieval.chunkConfidence);
      final context = _contextBuilder.build(retrieval.selectedChunks, resolved.labelForChunkId).text;

      final handle = _llmRequestQueue.enqueue(
        LlmQueueRequest(
          isForeground: true,
          run: () => _llmEngine.answerQuestionStream(context, trimmed, onToken: onToken, history: history),
        ),
      );
      onRequestQueued?.call(handle.id);
      final answer = await handle.result;

      if (isAbandoned?.call() ?? false) return null;

      assistantMessage = await _persist(session.id!, answer, resolved.sources, AnswerProvenance.local);
    } else {
      // Low/none confidence: nothing in the user's own content confidently
      // answers this - the approved product decision (Phase 6B) is to
      // answer from the model's own general knowledge instead, never a
      // fixed "couldn't find anything" string, and never with citations
      // (there is no retrieved content behind this answer to cite).
      final handle = _llmRequestQueue.enqueue(
        LlmQueueRequest(
          isForeground: true,
          run: () => _llmEngine.answerGeneralKnowledgeStream(trimmed, onToken: onToken, history: history),
        ),
      );
      onRequestQueued?.call(handle.id);
      final answer = await handle.result;

      if (isAbandoned?.call() ?? false) return null;

      assistantMessage = await _persist(session.id!, answer, const [], AnswerProvenance.generalKnowledge);
    }

    await _chatSessionRepository.update(session.copyWith(updatedAt: DateTime.now()));
    return assistantMessage;
  }

  /// The last [_maxHistoryMessages] of [priorMessages] (already
  /// oldest-first from [ChatMessageRepository.getForSession]), mapped to
  /// [LlmChatTurn]s so a follow-up question ("translate that into
  /// French") can be understood against what was actually just said,
  /// instead of every turn being answered as if it were the first message
  /// in the conversation.
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

  Future<ChatMessage> _persist(
    int sessionId,
    String content,
    List<ChatSourceRef> sources,
    AnswerProvenance provenance,
  ) async {
    final message = ChatMessage(
      id: null,
      sessionId: sessionId,
      role: ChatMessageRole.assistant,
      content: content,
      createdAt: DateTime.now(),
      sourcesJson: ChatSourceRef.encodeList(sources),
      answerProvenance: provenance,
    );
    final id = await _chatMessageRepository.insert(message);
    return message.copyWith(id: id);
  }

  /// Resolves fused/ranked chunks to labeled [ChatSourceRef]s (deduped by
  /// label - a meeting can contribute several chunks of the same kind,
  /// which should show as one citation, not two) and a per-chunk-id label
  /// map for [ContextBuilder]. Each [ChatSourceRef] carries the chunk's
  /// real cosine-similarity [ChatSourceRef.confidence] from
  /// [HybridRetrievalResult.chunkConfidence] (Source Attribution /
  /// Confidence Scoring, Phase 6B objectives 9/10) - when a label is
  /// shared by multiple chunks, the highest of their confidences is kept,
  /// so the citation never understates how relevant its best-matching
  /// chunk was.
  Future<({List<ChatSourceRef> sources, Map<int, String> labelForChunkId})> _resolveSources(
    List<RankedChunk> rankedChunks,
    Map<int, double> chunkConfidence,
  ) async {
    final meetingIds = rankedChunks.map((rc) => rc.chunk.meetingId).whereType<int>().toSet();
    final documentIds = rankedChunks.map((rc) => rc.chunk.documentId).whereType<int>().toSet();

    final meetingTitles = {
      for (final m in await _meetingRepository.getByIds(meetingIds)) m.id!: m.title,
    };
    final documentTitles = {
      for (final d in await _documentRepository.getByIds(documentIds)) d.id!: d.title,
    };

    final byLabel = <String, ChatSourceRef>{};
    final labelForChunkId = <int, String>{};
    for (final rankedChunk in rankedChunks) {
      final chunk = rankedChunk.chunk;
      final id = chunk.id;
      if (id == null) continue;
      final label = chunk.meetingId != null
          ? '${meetingTitles[chunk.meetingId] ?? 'Meeting'} — ${_kindLabel(chunk.contentType)}'
          : (documentTitles[chunk.documentId] ?? 'Document');
      labelForChunkId[id] = label;

      final confidence = chunkConfidence[id];
      final existing = byLabel[label];
      if (existing == null || (confidence != null && confidence > (existing.confidence ?? 0))) {
        byLabel[label] = ChatSourceRef(
          label: label,
          contentType: chunk.contentType,
          meetingId: chunk.meetingId,
          documentId: chunk.documentId,
          confidence: confidence,
        );
      }
    }
    return (sources: byLabel.values.toList(), labelForChunkId: labelForChunkId);
  }

  String _kindLabel(ContentType contentType) => switch (contentType) {
        ContentType.transcript => 'Transcript',
        ContentType.summary => 'Summary',
        ContentType.note => 'Notes',
        ContentType.meeting => 'Meeting',
        ContentType.actionItem => 'Action Items',
        ContentType.document => 'Document',
      };
}
