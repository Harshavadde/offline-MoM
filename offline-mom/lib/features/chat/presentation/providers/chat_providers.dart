import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../../models/chat_message.dart';
import '../../../../models/chat_session.dart';
import '../../../../models/document.dart';
import '../../../../models/meeting.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/llm_request_queue.dart';
import '../../workspace_chat_use_case.dart';

/// Reads mirror the existing `meeting_providers.dart` shape. Pinned
/// conversations sort first (Phase 2B "pin conversation" requirement,
/// docs/v2/implementation/03-decisions.md ADR-028) - the repository itself
/// stays a plain most-recently-updated-first query
/// (`SqfliteChatSessionRepository.getAll`), same convention as
/// `MeetingRepository`/`DocumentRepository`; pinning is a presentation-layer
/// re-sort on top of it, not a second query.
final chatSessionListProvider = FutureProvider<List<ChatSession>>((ref) async {
  final sessions = await ref.watch(chatSessionRepositoryProvider).getAll();
  final pinned = sessions.where((s) => s.isPinned).toList();
  final unpinned = sessions.where((s) => !s.isPinned).toList();
  return [...pinned, ...unpinned];
});

/// Meetings/documents the in-chat scope selector lets a user pick from -
/// only `ready` ones are offered, since an unready meeting/document has
/// nothing indexed yet to make meeting-/document-scoped chat meaningful.
final chatEligibleMeetingsProvider = FutureProvider<List<Meeting>>((ref) async {
  final meetings = await ref.watch(meetingRepositoryProvider).getAll();
  return meetings.where((m) => m.status == MeetingStatus.ready).toList();
});

final chatEligibleDocumentsProvider = FutureProvider<List<Document>>((ref) async {
  final documents = await ref.watch(documentRepositoryProvider).getAll();
  return documents.where((d) => d.status == DocumentStatus.ready).toList();
});

/// Navigation payload for `RoutePaths.chat` (`state.extra`) - lets any
/// screen open the single chat screen pre-scoped (a meeting/document's
/// "Chat about this" action) or resume a specific past conversation
/// (`ChatHistoryScreen`), without adding a second route or a second
/// screen (ADR-013, docs/v2/implementation/03-decisions.md).
class ChatLaunchArgs {
  const ChatLaunchArgs({this.sessionId, this.scope, this.meetingId, this.documentId});

  /// When set, the chat screen resumes this existing conversation instead
  /// of starting a new one - every other field is ignored.
  final int? sessionId;

  final ChatScope? scope;
  final int? meetingId;
  final int? documentId;
}

/// Single chat screen, scope-aware per ADR-013
/// (docs/v2/implementation/03-decisions.md) - one controller/one state
/// class handles [ChatScope.workspace]/[ChatScope.meeting]/
/// [ChatScope.document]/[ChatScope.general] (M2.1/FR-31) rather than four
/// separate controllers or a sealed per-scope state hierarchy.
class ChatState {
  const ChatState({
    required this.scope,
    this.meetingId,
    this.documentId,
    this.session,
    this.messages = const [],
    this.streamingText,
    this.isSending = false,
    this.isPreparingModel = false,
    this.modelPrepProgress,
    this.isLoadingHistory = false,
    this.error,
  });

  final ChatScope scope;
  final int? meetingId;
  final int? documentId;

  /// Null until the first message of a new conversation is sent (lazy
  /// session creation - visiting the chat screen and picking a scope
  /// doesn't itself create history clutter) or until [openSession] loads
  /// an existing one.
  final ChatSession? session;

  final List<ChatMessage> messages;

  /// The in-progress assistant answer's text so far, updated token-by-token
  /// (ADR-026, docs/v2/implementation/03-decisions.md) - null whenever
  /// [isSending] is false. Not yet a persisted [ChatMessage].
  final String? streamingText;

  final bool isSending;

  /// True only while [ChatController] is waiting on
  /// [LlmEngine.ensureModelReady] before the actual generation call starts -
  /// a real, on-device model load (first use since app start, or a reload
  /// after [ModelLifecycleManager]'s idle-unload) can take a genuinely long
  /// time with no tokens to stream yet, which previously looked identical
  /// to [isSending] alone (a bare typing indicator, indistinguishable from
  /// a stuck app). Always false whenever [isSending] is false; implies
  /// [isSending] is true whenever it's true itself.
  final bool isPreparingModel;

  /// 0.0-1.0 progress during a real model download, mirroring
  /// [LlmEngine.ensureModelReady]'s own `onProgress` contract - null
  /// whenever nothing is downloading (a plain from-disk load reports no
  /// fraction, since there's no byte count to report), including whenever
  /// [isPreparingModel] is false.
  final double? modelPrepProgress;

  final bool isLoadingHistory;

  /// Set on a real failure (never on user-initiated cancellation, which
  /// returns to idle silently per ADR-027) - cleared on the next send or
  /// scope/session change.
  final String? error;

  bool get hasActiveSession => session != null;

  ChatState copyWith({
    ChatScope? scope,
    int? meetingId,
    bool clearMeetingId = false,
    int? documentId,
    bool clearDocumentId = false,
    ChatSession? session,
    List<ChatMessage>? messages,
    String? streamingText,
    bool clearStreamingText = false,
    bool? isSending,
    bool? isPreparingModel,
    double? modelPrepProgress,
    bool clearModelPrepProgress = false,
    bool? isLoadingHistory,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      scope: scope ?? this.scope,
      meetingId: clearMeetingId ? null : (meetingId ?? this.meetingId),
      documentId: clearDocumentId ? null : (documentId ?? this.documentId),
      session: session ?? this.session,
      messages: messages ?? this.messages,
      streamingText: clearStreamingText ? null : (streamingText ?? this.streamingText),
      isSending: isSending ?? this.isSending,
      isPreparingModel: isPreparingModel ?? this.isPreparingModel,
      modelPrepProgress: clearModelPrepProgress ? null : (modelPrepProgress ?? this.modelPrepProgress),
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState(scope: ChatScope.workspace);

  int? _activeRequestId;

  /// Set by [cancel] - tells the in-flight [sendMessage] call to discard
  /// whatever the request eventually resolves with (ADR-027,
  /// docs/v2/implementation/03-decisions.md: UI-level abandon, since a
  /// request already running against the shared engine can't actually be
  /// interrupted).
  bool _abandoned = false;

  String? _lastFailedQuestion;

  /// Routes a chat turn to the right use case for [session.scope] - the
  /// only two callers of this are [sendMessage] and [regenerateMessage], so
  /// this exists purely to avoid duplicating the branch in both. The two
  /// use cases have no common supertype (deliberately - see
  /// `GeneralChatUseCase`'s doc comment), but share an identical `call(...)`
  /// signature, so branching once here and calling through it reads no
  /// differently than calling either directly would have.
  Future<ChatMessage?> _runTurn({
    required ChatSession session,
    required String question,
    void Function(String token)? onToken,
    void Function(int requestId)? onRequestQueued,
    bool Function()? isAbandoned,
    bool persistQuestion = true,
    void Function(ChatMessage persistedQuestion)? onQuestionPersisted,
  }) {
    if (session.scope == ChatScope.general) {
      return ref.read(generalChatUseCaseProvider).call(
            session: session,
            question: question,
            onToken: onToken,
            onRequestQueued: onRequestQueued,
            isAbandoned: isAbandoned,
            persistQuestion: persistQuestion,
            onQuestionPersisted: onQuestionPersisted,
          );
    }
    return ref.read(workspaceChatUseCaseProvider).call(
          session: session,
          question: question,
          onToken: onToken,
          onRequestQueued: onRequestQueued,
          isAbandoned: isAbandoned,
          persistQuestion: persistQuestion,
          onQuestionPersisted: onQuestionPersisted,
        );
  }

  /// Waits for the shared on-device model to actually be ready to generate,
  /// surfacing [ChatState.isPreparingModel]/[ChatState.modelPrepProgress]
  /// while it does - the fix for a real product gap: [LlmEngine
  /// .answerQuestionStream]/[answerGeneralKnowledgeStream] silently call
  /// their own internal model-load before generating, with nothing telling
  /// the UI apart "the model is loading" from "the model is generating
  /// slowly" - both looked like the same bare typing indicator. Calling
  /// [LlmEngine.ensureModelReady] explicitly, first, closes that gap using
  /// the engine's own existing callbacks rather than adding a new one.
  /// A no-op in wall-clock terms whenever the model is already warm
  /// ([LlamaDartLlmEngine._ensureLoaded] returns immediately if already
  /// loaded) - this call is unconditional, not just for a "cold" case,
  /// since there's no cheap way to know in advance which case this is.
  Future<void> _prepareModel() async {
    state = state.copyWith(isPreparingModel: true, clearModelPrepProgress: true);
    try {
      await ref.read(llmEngineProvider).ensureModelReady(
            onProgress: (fraction) {
              state = state.copyWith(modelPrepProgress: fraction);
            },
          );
    } finally {
      state = state.copyWith(isPreparingModel: false, clearModelPrepProgress: true);
    }
  }

  /// Resets to a fresh, not-yet-persisted conversation in [scope]. Safe to
  /// call any time the chat screen mounts with no specific session to
  /// resume.
  void startNewConversation({
    ChatScope scope = ChatScope.workspace,
    int? meetingId,
    int? documentId,
  }) {
    state = ChatState(scope: scope, meetingId: meetingId, documentId: documentId);
  }

  /// Changes the scope of a not-yet-started conversation (no messages sent
  /// yet) - once a conversation has a persisted [ChatSession], its scope is
  /// fixed for that conversation's lifetime (starting a new one is how a
  /// user switches scope mid-use, exactly like starting a new browser tab
  /// rather than teleporting an existing one).
  void setScope(ChatScope scope, {int? meetingId, int? documentId}) {
    if (state.hasActiveSession) return;
    state = ChatState(scope: scope, meetingId: meetingId, documentId: documentId);
  }

  Future<void> openSession(int sessionId) async {
    state = state.copyWith(isLoadingHistory: true, clearError: true);
    final session = await ref.read(chatSessionRepositoryProvider).getById(sessionId);
    if (session == null) {
      state = ChatState(
        scope: state.scope,
        isLoadingHistory: false,
        error: 'This conversation could not be found - it may have been deleted.',
      );
      return;
    }
    final messages = await ref.read(chatMessageRepositoryProvider).getForSession(sessionId);
    state = ChatState(
      scope: session.scope,
      meetingId: session.meetingId,
      documentId: session.documentId,
      session: session,
      messages: messages,
    );
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    // `isSending` is set synchronously here, before the first `await`
    // below (session creation) - real-device QA finding: it was
    // previously only set after that await resolved, leaving a real
    // window where a fast double-tap of Send could pass the guard above
    // twice (state.isSending and state.session are both still stale for
    // both calls), creating two ChatSessions/two concurrent LLM requests
    // for one intended message. Mirrors ModelDownloadController.start()'s
    // identical fix for the identical race (ADR-036).
    state = state.copyWith(clearError: true, isSending: true);

    var session = state.session;
    if (session == null) {
      final now = DateTime.now();
      final draft = ChatSession(
        id: null,
        title: _titleFrom(trimmed),
        scope: state.scope,
        createdAt: now,
        updatedAt: now,
        meetingId: state.meetingId,
        documentId: state.documentId,
      );
      final id = await ref.read(chatSessionRepositoryProvider).insert(draft);
      session = draft.copyWith(id: id);
      state = state.copyWith(session: session);
    }

    final optimisticUserMessage = ChatMessage(
      id: null,
      sessionId: session.id!,
      role: ChatMessageRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, optimisticUserMessage],
      isSending: true,
      streamingText: '',
    );

    _abandoned = false;
    try {
      await _prepareModel();
      if (_abandoned) {
        // Cancelled while the model itself was still loading, before any
        // generation request ever reached the queue (see `cancel()`) - the
        // model load isn't itself cancellable, but the turn it was for is
        // already abandoned, so it must not proceed to actually generate.
        _abandoned = false;
        return;
      }

      final assistantMessage = await _runTurn(
        session: session,
        question: trimmed,
        onQuestionPersisted: (persisted) {
          // Patches the optimistic (`id: null`) message above with its
          // real database id, matched by reference (this is the only
          // message this call could have just persisted) - without
          // this, every user message in `state.messages` stays
          // `id: null` forever, and Edit (which needs a real id to
          // later find and truncate from) would silently no-op.
          final index = state.messages.indexWhere((m) => identical(m, optimisticUserMessage));
          if (index == -1) return;
          final updated = [...state.messages];
          updated[index] = persisted;
          state = state.copyWith(messages: updated);
        },
        onToken: (token) {
          if (_abandoned) return;
          state = state.copyWith(streamingText: (state.streamingText ?? '') + token);
        },
        onRequestQueued: (id) => _activeRequestId = id,
        isAbandoned: () => _abandoned,
      );

      _activeRequestId = null;
      if (assistantMessage == null) {
        // Abandoned per ADR-027 - the use case already discarded it
        // without persisting; state was already reset by cancel().
        _abandoned = false;
        return;
      }
      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        isSending: false,
        clearStreamingText: true,
      );
    } on LlmQueueCancelledException {
      _activeRequestId = null;
      if (_abandoned) {
        _abandoned = false;
        return;
      }
      state = state.copyWith(isSending: false, clearStreamingText: true);
    } catch (e) {
      _activeRequestId = null;
      if (_abandoned) {
        _abandoned = false;
        return;
      }
      _lastFailedQuestion = trimmed;
      state = state.copyWith(
        isSending: false,
        clearStreamingText: true,
        error: _friendlyError(e),
      );
    }
  }

  /// Cancels the current turn - see ADR-027
  /// (docs/v2/implementation/03-decisions.md) for why this is a UI-level
  /// abandon rather than true mid-generation interruption once the request
  /// has actually started running against the shared engine.
  void cancel() {
    if (!state.isSending) return;
    final id = _activeRequestId;
    if (id != null) {
      ref.read(llmRequestQueueProvider).cancel(id);
    }
    _abandoned = true;
    state = state.copyWith(isSending: false, clearStreamingText: true);
  }

  /// Re-sends the question from the most recent failed turn, if any.
  void retry() {
    final question = _lastFailedQuestion;
    if (question != null) sendMessage(question);
  }

  /// Regenerates [assistantMessage] in place (Phase 8B.1, Priority 3):
  /// deletes that one answer (DB + state) and re-asks the *same* preceding
  /// question, replacing it with a fresh answer - unlike the old
  /// behavior (re-sending the question as a brand-new turn), this never
  /// leaves the stale answer sitting in the conversation alongside the new
  /// one. The user's question itself is untouched (not re-inserted) -
  /// [WorkspaceChatUseCase.call]'s `persistQuestion: false` tells it this
  /// question is already the most recent persisted row.
  Future<void> regenerateMessage(ChatMessage assistantMessage) async {
    if (state.isSending) return;
    final session = state.session;
    if (session == null) return;
    if (assistantMessage.role != ChatMessageRole.assistant) return;

    final index = state.messages.indexWhere((m) => m.id == assistantMessage.id);
    if (index <= 0) return;
    final question = state.messages[index - 1];
    if (question.role != ChatMessageRole.user) return;

    await ref.read(chatMessageRepositoryProvider).deleteMessage(assistantMessage.id!);
    state = state.copyWith(
      messages: state.messages.sublist(0, index),
      clearError: true,
      isSending: true,
      streamingText: '',
    );

    _abandoned = false;
    try {
      await _prepareModel();
      if (_abandoned) {
        _abandoned = false;
        return;
      }

      final newAssistantMessage = await _runTurn(
        session: session,
        question: question.content,
        persistQuestion: false,
        onToken: (token) {
          if (_abandoned) return;
          state = state.copyWith(streamingText: (state.streamingText ?? '') + token);
        },
        onRequestQueued: (id) => _activeRequestId = id,
        isAbandoned: () => _abandoned,
      );

      _activeRequestId = null;
      if (newAssistantMessage == null) {
        _abandoned = false;
        return;
      }
      state = state.copyWith(
        messages: [...state.messages, newAssistantMessage],
        isSending: false,
        clearStreamingText: true,
      );
    } on LlmQueueCancelledException {
      _activeRequestId = null;
      if (_abandoned) {
        _abandoned = false;
        return;
      }
      state = state.copyWith(isSending: false, clearStreamingText: true);
    } catch (e) {
      _activeRequestId = null;
      if (_abandoned) {
        _abandoned = false;
        return;
      }
      state = state.copyWith(
        isSending: false,
        clearStreamingText: true,
        error: _friendlyError(e),
      );
    }
  }

  /// Deletes exactly [message] (Phase 8B.1, Priority 3: per-message
  /// Delete) - every other message is untouched, unlike [editAndResend]'s
  /// deliberate truncate-from-here-onward behavior.
  Future<void> deleteMessage(ChatMessage message) async {
    if (message.id == null) return;
    await ref.read(chatMessageRepositoryProvider).deleteMessage(message.id!);
    state = state.copyWith(messages: state.messages.where((m) => m.id != message.id).toList());
  }

  /// Deletes [message] and truncates every message after it, ready for
  /// [newText] to be sent as a fresh turn in its place (Phase 8B.1,
  /// Priority 2 "Edit previous prompt") - the old (pre-edit) turn and
  /// whatever followed it are gone *before* the new one is sent, so they
  /// never coexist. Only meant to be called with a [ChatMessageRole.user]
  /// message; the caller ([ChatScreen]) only ever offers Edit on user
  /// bubbles.
  Future<void> editAndResend(ChatMessage message, String newText) async {
    if (state.isSending) return;
    final session = state.session;
    if (session == null || message.id == null) return;

    await ref.read(chatMessageRepositoryProvider).deleteFromMessageOnward(session.id!, message.id!);
    final index = state.messages.indexWhere((m) => m.id == message.id);
    state = state.copyWith(messages: index == -1 ? state.messages : state.messages.sublist(0, index));

    await sendMessage(newText);
  }

  String _titleFrom(String text) {
    final singleLine = text.replaceAll('\n', ' ').trim();
    if (singleLine.length <= 40) return singleLine;
    return '${singleLine.substring(0, 40).trimRight()}…';
  }

  // V2.2 Production Hardening, Priority 6 (real-device QA finding): this
  // previously returned `error.toString()` directly - a raw exception
  // (e.g. "LlmModelDownloadTimeoutException: ...") shown straight to the
  // user in `_ErrorBanner`. `friendlyErrorMessage` translates it to plain
  // language; the raw error is still logged wherever it was originally
  // caught (this controller doesn't log it itself, since it never was the
  // one place doing that - see `AppLogger` usage in the use-case layer).
  String _friendlyError(Object error) => friendlyErrorMessage(error);
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);
