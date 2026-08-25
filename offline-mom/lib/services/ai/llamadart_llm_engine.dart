import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:llamadart/llamadart.dart';

import '../../core/logging/app_logger.dart';
import 'download_progress_throttle.dart';
import 'llm_engine.dart';
import 'model_lifecycle_manager.dart';

/// How many output tokens are safe to request for a prompt of roughly
/// [promptChars] characters, inside a [contextSize]-token context window
/// shared between input AND output (llama.cpp holds the whole prompt plus
/// everything generated so far in one KV cache, up to `contextSize` total -
/// it is not two separate budgets).
///
/// R-8 fix: `answerQuestionStream`'s prompt (system prompt + history up to
/// `_maxHistoryChars` + retrieved excerpts up to `_maxTranscriptChars` +
/// the question) can, in the worst case, already use close to the model's
/// full 2048-token context on its own - a single fixed `maxTokens` large
/// enough to fix real truncation on a *typical* request (small excerpts,
/// little/no history) would silently overflow the context on a *heavy*
/// request (near-max excerpts and history at once), trading one kind of
/// truncation for a worse one (or an engine error) instead of fixing it.
/// This computes the *actual* remaining headroom for the specific prompt
/// about to be sent, so a light request gets a genuinely generous budget
/// and a heavy one still gets a smaller, safe one instead of overflowing -
/// without touching `_maxTranscriptChars`/`_maxHistoryChars`/
/// `TokenBudgetSelector` (retrieval/history budgets are unchanged; this
/// only decides how much of what's left goes to the answer).
///
/// Uses the same conservative ~3-chars-per-token "worst case" ratio this
/// file already established for [LlamaDartLlmEngine._maxHistoryChars]'s own
/// doc comment ("1500 chars, ~500 tokens worst case") - deliberately not a
/// tighter average-case ratio, so this stays safe for the less-common,
/// token-dense content (URLs, code, punctuation-heavy excerpts) real
/// documents sometimes contain. [chatTemplateOverheadTokens] is a fixed
/// allowance for the special/role tokens Qwen's chat template adds per
/// message that raw character counts don't capture.
///
/// Even this can't make every combination of maximum excerpts + maximum
/// history + a long question fit inside 2048 tokens with room to spare -
/// that specific combination is rare, and genuinely reducing it further
/// would mean cutting into retrieval/history budgets themselves, which is
/// explicitly out of scope here. [floor] guarantees a request is still
/// attempted rather than requesting zero/negative tokens in that case.
@visibleForTesting
int outputBudgetTokens({
  required int promptChars,
  required int contextSize,
  int ceiling = 800,
  int floor = 64,
  int charsPerTokenWorstCase = 3,
  int chatTemplateOverheadTokens = 64,
}) {
  final estimatedPromptTokens =
      (promptChars / charsPerTokenWorstCase).ceil() + chatTemplateOverheadTokens;
  final remaining = contextSize - estimatedPromptTokens;
  return remaining.clamp(floor, ceiling);
}

/// Thrown when the model's response wasn't valid JSON (or was missing
/// required fields) after parsing/self-heal attempts - a distinct type so
/// callers/logs can tell "the AI produced garbage" apart from other
/// failures (engine crash, out of memory, etc.), while still being a
/// plain `Exception` the existing error-surfacing/retry UI already
/// handles without any changes.
class LlmResponseFormatException implements Exception {
  LlmResponseFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a generation stalls for too long. This engine is shared by
/// every AI feature in the app (meeting summaries, Ask, the conversation
/// translator) via one loaded model instance, and llamadart's own worker
/// only ever runs one generation at a time - it makes every new request
/// wait for whatever's currently running rather than rejecting it (see
/// `llama_cpp/worker.dart`'s `activeGenerate`/`waitForActiveGenerate`).
/// That means a single stuck generation, with no bound on it, doesn't just
/// fail its own caller - it permanently blocks every other AI feature in
/// the app behind it. This timeout (and the `cancelGeneration()` call that
/// goes with it) exists specifically so that can never happen: whichever
/// request stalls gives up and frees the shared engine for the next one,
/// instead of everything queuing forever behind a hang.
class LlmTimeoutException implements Exception {
  LlmTimeoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the one-time model download itself stalls or simply takes
/// too long - distinct from [LlmTimeoutException] (which covers a stuck
/// *generation* after the model is already loaded). llamadart's own
/// downloader already retries stalled chunks internally, but a connection
/// that's technically still trickling bytes (just extremely slowly, e.g.
/// heavy throttling) would never trip that internal per-chunk recovery -
/// so this adds an outer, absolute cap on the whole download, on top of
/// resetting on real progress, so a bad connection can never occupy the
/// shared engine indefinitely.
class LlmModelDownloadTimeoutException implements Exception {
  LlmModelDownloadTimeoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// [LlmEngine] backed by llama.cpp (via `llamadart`), running
/// Qwen2.5-1.5B-Instruct - meaningfully more capable at following the
/// strict-JSON system prompt below than the project's original
/// TinyLlama-1.1B, at a still-modest ~1.1GB (Q4_K_M) that's realistic to
/// run on a mid-range phone. Q4_K_M rather than the legacy Q4_0 quant:
/// llama.cpp's own current guidance is that the K-quants give meaningfully
/// better quality at essentially the same file size, and there's no
/// countervailing reason (e.g. an old ARM fast-path) to prefer Q4_0 here.
///
/// Like the whisper model, the GGUF file is fetched from Hugging Face on
/// first use and cached on-device from then on - a one-time asset download,
/// not a runtime dependency. Every summary generated afterwards runs
/// entirely locally.
///
/// `llamadart` already runs model loading and every inference call on its
/// own dedicated worker Isolate internally (see
/// `llama_cpp/worker.dart` in the package) - this class, and the isolate
/// that owns the native model, never touch the UI isolate directly. There
/// is no additional isolate wrapping to add here; doing so would just
/// double-hop the same work.
class LlamaDartLlmEngine implements LlmEngine {
  static const _defaultModelSource =
      'hf://Qwen/Qwen2.5-1.5B-Instruct-GGUF/'
      'qwen2.5-1.5b-instruct-q4_k_m.gguf';
  // Deliberately generic in the UI/stored data (Summary.modelUsed) - the
  // exact model choice is an internal implementation detail, not something
  // to expose to end users. See the class doc comment above for the real
  // model identity/version.
  static const modelDisplayName = 'On-device language model';

  /// Bump this whenever the system prompt's required JSON shape changes,
  /// so logs/bug reports can tell which contract a given failure was
  /// parsed against.
  static const promptVersion = 3;

  /// Bump whenever [_chatSystemPrompt] changes - the Chat module's own
  /// contract version (ADR-026, docs/v2/implementation/03-decisions.md),
  /// tracked separately from [promptVersion] since the two prompts change
  /// independently.
  static const chatPromptVersion = 1;

  // The model's total context window (input + output combined - see
  // [outputBudgetTokens]'s doc comment) - passed to `ModelParams` below and
  // reused by [outputBudgetTokens] so the two can never silently drift
  // apart.
  static const _contextSize = 2048;

  // Keep the transcript within the model's practical context window once
  // the prompt scaffolding and response budget are accounted for.
  static const _maxTranscriptChars = 4000;

  // Budget for [LlmChatTurn] history injected into the chat prompts, kept
  // well below [_maxTranscriptChars] since it shares the same context
  // window as the RAG excerpts/general-knowledge question and response -
  // this is short-term memory of the last couple of turns, not a transcript.
  static const _maxHistoryChars = 1500;

  /// If the model goes this long without producing a single further token,
  /// treat the generation as stuck rather than waiting indefinitely - see
  /// [LlmTimeoutException].
  static const _stallTimeout = Duration(seconds: 45);

  /// If the one-time model download goes this long without a single new
  /// progress event, treat it as stalled - see [LlmModelDownloadTimeoutException].
  /// R-11 P0 fix: 90s was too aggressive for a real device - this app has
  /// no foreground service keeping the connection alive while backgrounded
  /// (`AppSettings.allowBackgroundDownloads` defaults to false), so a
  /// normal "lock the phone for a bit" during this ~1.1GB download would
  /// reliably trip this timer well before the user meant to interrupt
  /// anything. `llamadart`'s own downloader still resumes correctly from
  /// the `.part` file on the next call regardless of this value (confirmed
  /// by direct source inspection of the installed package's Range/ETag
  /// resume logic) - this only controls how long a genuinely idle
  /// connection is tolerated before this app's own wrapper gives up on the
  /// current attempt, not whether resume works.
  static const _downloadStallTimeout = Duration(minutes: 3);

  /// Absolute wall-clock cap on the whole download, regardless of whether
  /// bytes are still (very slowly) trickling in - a ~1.1GB one-time
  /// download that can't complete in this long on the current connection
  /// should surface a clear "try a better connection" error rather than
  /// silently keep occupying the shared engine. R-11 P0 fix: raised
  /// alongside [_downloadStallTimeout] for the same real-device reason.
  static const _downloadOverallTimeout = Duration(minutes: 30);

  // Action items and decisions were dropped from what the model is asked
  // to extract: getting a small on-device model to reliably produce
  // *structured* nested JSON (task/owner/deadline objects) on top of
  // summarizing at all made the prompt bigger, the output slower, and the
  // JSON more likely to come back malformed - for a feature whose whole
  // point is speed and reliability, that trade wasn't worth it. Manually
  // adding action items is still fully supported from the Action Items
  // tab; only the AI's auto-extraction of them (and of decisions
  // entirely) was removed.
  static const _systemPrompt =
      'You summarize meeting transcripts. Reply with ONLY a single valid '
      'JSON object and nothing else - no markdown fences, no commentary '
      'before or after it. Use exactly this shape:\n'
      '{"summary": "2-4 sentence summary", '
      '"minutes_of_meeting": "a short, formal minutes-of-meeting '
      'paragraph", '
      '"key_topics": ["topic", "..."]}\n'
      'Use an empty array ([]) for key_topics when there genuinely are '
      'none. Never invent facts not in the transcript.';

  /// The Chat module's system prompt (ADR-026,
  /// docs/v2/implementation/03-decisions.md) - deliberately does not ask
  /// the model to produce a parseable "Sources:" line the way
  /// docs/v2/11-ai-architecture.md originally sketched: citations are
  /// derived from the actual retrieved chunks instead (see
  /// `WorkspaceChatUseCase`), so the model is asked only to answer well
  /// and stay honest about the limits of what it was given, not to also
  /// self-report which parts it used.
  static const _chatSystemPrompt =
      'You answer questions using ONLY the excerpts given to you below - '
      'never your own outside knowledge and never information not present '
      'in the excerpts. If the excerpts don\'t contain enough information '
      'to answer, say so plainly instead of guessing or filling gaps with '
      'assumptions. Keep answers focused and free of unnecessary padding.';

  /// The deliberate opposite of [_chatSystemPrompt] - Phase 6B's Hybrid
  /// Retrieval Engine general-knowledge fallback (ADR-037,
  /// docs/v2/implementation/03-decisions.md), used only when retrieval
  /// found nothing confidently relevant in the user's own content. No
  /// excerpts are ever included in this prompt - there is nothing to
  /// ground the answer in, which is exactly the point; the caller is
  /// responsible for labeling the result as general knowledge, not this
  /// prompt's job.
  static const _generalKnowledgeSystemPrompt =
      'You are a helpful, knowledgeable assistant. Answer the question using '
      'your own general knowledge, as accurately and concisely as you can. '
      'If you are not confident in the answer, say so plainly rather than '
      'guessing.';

  /// The "Ask" feature's system prompt ([_answerQuestion]/[answerQuestion])
  /// - a separate, older, non-streaming answer surface from Chat's
  /// [answerQuestionStream], same shape (context excerpts + question, no
  /// history), extracted to a named constant (was inline) so its length can
  /// feed [outputBudgetTokens] the same way [_chatSystemPrompt] does.
  static const _askSystemPrompt =
      'You answer questions using ONLY the meeting notes given to you below '
      '- never your own outside knowledge. If the notes don\'t contain the '
      'answer, say so plainly instead of guessing. Keep the answer short, '
      'and mention which meeting it came from when there\'s more than one.';

  LlamaDartLlmEngine({ModelLifecycleManager? lifecycleManager, String? modelSourceOverride})
      : _lifecycleManager = lifecycleManager,
        _modelSource = modelSourceOverride ?? _defaultModelSource {
    _lifecycleManager?.attach(
      ModelKind.llm,
      unload: unload,
      statusOf: () => status,
    );
  }

  final ModelLifecycleManager? _lifecycleManager;
  final _log = const AppLogger('LlamaDartLlmEngine');

  /// The active model's `hf://...` source - [_defaultModelSource] unless
  /// the AI Model Manager (Phase 6A, `app_providers.dart`'s
  /// `llmEngineProvider`) supplied a different catalog entry's
  /// [AiModelSpec.downloadSource] via `modelSourceOverride`. A provider
  /// rebuild (the settings value changing) constructs a brand-new engine
  /// instance with the new source - the exact same "change = new instance,
  /// not mutation" pattern `speechToTextEngineProvider` already uses for
  /// Whisper model switching, extended here rather than reinvented.
  final String _modelSource;

  LlamaEngine? _engine;

  /// The in-flight first load, if any - see [_ensureLoaded]'s doc comment
  /// for why this exists (Phase 3A: prevents a duplicate concurrent load).
  Future<LlamaEngine>? _loading;

  /// The cancel token backing the in-flight download, if any - lets an
  /// external caller (the AI Model Manager's "Pause" action, Phase 6A)
  /// request cancellation without this engine needing to know anything
  /// about who's asking. `null` whenever [_loading] is `null`. This is
  /// `llamadart`'s own `ModelDownloadCancelToken` type (already imported
  /// via `package:llamadart/llamadart.dart` below) - a distinct type from
  /// this app's `ModelDownloadCancelToken`
  /// (`services/ai/model_download_service.dart`), which only Whisper/OCR/
  /// Vision/Translation downloads use (see that file's doc comment for why
  /// the two are deliberately not unified).
  ModelDownloadCancelToken? _activeDownloadCancelToken;

  /// Requests cancellation of an in-flight download, if any - a no-op if
  /// nothing is currently downloading. Cancelling here always leaves
  /// `llamadart`'s own `.part` cache file in place (see its own Range-resume
  /// support, confirmed by source inspection, ADR-036) - the *next* call to
  /// [ensureModelReady] transparently resumes rather than restarting, so
  /// this doubles as both "Pause" and the seam "Resume" calls back into.
  void cancelActiveDownload() => _activeDownloadCancelToken?.cancel();

  /// Whether a download is currently in flight - drives the AI Model
  /// Manager's per-model download-state UI without duplicating [status]'s
  /// `loading` bucket (which also covers a pure native-load with no
  /// network activity, e.g. resuming after an app restart with the file
  /// already fully cached).
  bool get isDownloading => _loading != null;

  /// Current residency status for [ModelLifecycleManager] - `loading`
  /// while [_loading] is non-null, `loaded` once [_engine] is set, else
  /// `unloaded`.
  ModelStatus get status {
    if (_engine != null) return ModelStatus.loaded;
    if (_loading != null) return ModelStatus.loading;
    return ModelStatus.unloaded;
  }

  /// Loads the shared model, downloading it first if this is the very
  /// first AI call on this device. [onPreparingModel] fires once, only
  /// when a download is actually about to start (never on a cache hit).
  ///
  /// Guarded against duplicate concurrent loads (Phase 3A): two callers
  /// racing to be the first ever call on this engine (e.g. a background
  /// summary and a chat question both landing before either has loaded the
  /// model) previously each saw `_engine == null` and started their own
  /// independent `LlamaEngine().loadModelSource(...)`, doubling the
  /// ~1.1GB memory footprint and native load work until one finished and
  /// silently discarded the other's reference. Caching the in-flight
  /// [Future] itself (not just the eventual result) closes that race: the
  /// second caller awaits the first caller's already-started load instead
  /// of starting a second one.
  Future<LlamaEngine> _ensureLoaded({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) {
    final existing = _engine;
    if (existing != null) return Future.value(existing);

    final inFlight = _loading;
    if (inFlight != null) return inFlight;

    final future = _load(onPreparingModel: onPreparingModel, onProgress: onProgress);
    _loading = future;
    return future;
  }

  Future<LlamaEngine> _load({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {
    final engine = LlamaEngine(LlamaBackend());
    final cancelToken = ModelDownloadCancelToken();
    _activeDownloadCancelToken = cancelToken;
    var announced = false;
    Timer? stallTimer;
    void resetStallTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(_downloadStallTimeout, cancelToken.cancel);
    }

    // Only throttles the UI-facing onProgress callback - the stall timer
    // still resets on every single progress event regardless, so a
    // throttled UI update can never make a genuinely-alive download look
    // stalled. See ProgressThrottle's doc comment for why this exists at
    // all: a large download can report progress thousands of times, and
    // an unthrottled Riverpod state update on every one of them floods the
    // UI thread badly enough to look like the app has hung.
    final uiThrottle = ProgressThrottle();

    final overallTimer = Timer(_downloadOverallTimeout, cancelToken.cancel);
    try {
      await engine.loadModelSource(
        ModelSource.parse(_modelSource),
        modelParams: const ModelParams(contextSize: _contextSize),
        options: ModelLoadOptions(cancelToken: cancelToken),
        onProgress: (progress) {
          if (!announced) {
            announced = true;
            onPreparingModel?.call();
          }
          if (uiThrottle.shouldEmit()) onProgress?.call(progress.fraction);
          resetStallTimer();
        },
      );
      onProgress?.call(1.0);
    } on LlamaStateException {
      if (cancelToken.isCancelled) {
        throw LlmModelDownloadTimeoutException(
          'The AI model download stalled or took too long (over '
          '${_downloadOverallTimeout.inMinutes} min) - try a faster or '
          'more stable connection (Wi-Fi works best) and retry. This is '
          'a one-time ~1.1GB download; it will resume rather than start '
          'over.',
        );
      }
      rethrow;
    } finally {
      stallTimer?.cancel();
      overallTimer.cancel();
      _loading = null;
      _activeDownloadCancelToken = null;
    }
    _log.info('Model loaded.');
    _engine = engine;
    return engine;
  }

  /// Unloads the model, freeing its native memory - called by
  /// [ModelLifecycleManager] after [AppConstants.modelIdleUnloadTimeout] of
  /// no activity (Phase 3A), or directly by tests. The next call to any
  /// method on this engine transparently reloads it (same one-time-download
  /// convention as the very first call ever made). A no-op if nothing is
  /// currently loaded.
  Future<void> unload() async {
    final engine = _engine;
    if (engine == null) return;
    _engine = null;
    await engine.unloadModel();
    _log.info('Model unloaded.');
  }

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {
    _lifecycleManager?.beginUse(ModelKind.llm);
    try {
      await _ensureLoaded(onPreparingModel: onPreparingModel, onProgress: onProgress);
    } finally {
      _lifecycleManager?.endUse(ModelKind.llm);
    }
  }

  /// Streams a chat completion and collects it into plain text, bounded by
  /// [_stallTimeout] so a stuck generation can never hang forever - and,
  /// critically, actually cancels the native generation on timeout (not
  /// just gives up waiting for it), since a cancelled generation is what
  /// frees the shared engine for the next caller. See [LlmTimeoutException].
  Future<String> _collect(
    LlamaEngine engine,
    List<LlamaChatMessage> messages,
    GenerationParams params,
  ) async {
    final buffer = StringBuffer();
    try {
      await for (final chunk in engine.create(messages, params: params).timeout(_stallTimeout)) {
        final text = chunk.choices.first.delta.content;
        if (text != null) buffer.write(text);
      }
    } on TimeoutException {
      engine.cancelGeneration();
      throw LlmTimeoutException(
        'The AI stopped responding and was cancelled after '
        '${_stallTimeout.inSeconds}s - please retry.',
      );
    }
    return buffer.toString();
  }

  /// Maps [history] (oldest-first) to [LlamaChatMessage]s, keeping only as
  /// many of the *most recent* turns as fit within [_maxHistoryChars] -
  /// dropping the oldest ones first when the conversation has grown long,
  /// since what "it"/"that"/"the previous answer" refers to is almost
  /// always in the last turn or two, not further back. Returned oldest-first
  /// again (chronological order), so it can be inserted straight after the
  /// system prompt and before the current question.
  ///
  /// Also returns [chars], the total length of the turns actually kept -
  /// callers feed this into [outputBudgetTokens] for an accurate estimate
  /// of this specific request's real prompt size (never re-implementing
  /// this same trimming logic a second time just to size it).
  ({List<LlamaChatMessage> messages, int chars}) _historyMessages(List<LlmChatTurn> history) {
    final kept = <LlamaChatMessage>[];
    var used = 0;
    for (final turn in history.reversed) {
      final cost = turn.text.length;
      if (used + cost > _maxHistoryChars && kept.isNotEmpty) break;
      used += cost;
      kept.add(
        LlamaChatMessage.fromText(
          role: turn.role == LlmChatRole.user ? LlamaChatRole.user : LlamaChatRole.assistant,
          text: turn.text,
        ),
      );
      if (used >= _maxHistoryChars) break;
    }
    return (messages: kept.reversed.toList(), chars: used);
  }

  /// [_collect] plus progressive delivery: [onToken] fires once per delta,
  /// in order, as it arrives - see [LlmEngine.answerQuestionStream]'s doc
  /// comment for why this doesn't change the stall-timeout/cancellation
  /// behavior [_collect] already has.
  Future<String> _collectStreaming(
    LlamaEngine engine,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    void Function(String token)? onToken,
  }) async {
    final buffer = StringBuffer();
    try {
      await for (final chunk in engine.create(messages, params: params).timeout(_stallTimeout)) {
        final text = chunk.choices.first.delta.content;
        if (text != null && text.isNotEmpty) {
          buffer.write(text);
          onToken?.call(text);
        }
      }
    } on TimeoutException {
      engine.cancelGeneration();
      throw LlmTimeoutException(
        'The AI stopped responding and was cancelled after '
        '${_stallTimeout.inSeconds}s - please retry.',
      );
    }
    return buffer.toString();
  }

  @override
  Future<String> answerQuestionStream(
    String context,
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) async {
    _lifecycleManager?.beginUse(ModelKind.llm);
    try {
      final engine = await _ensureLoaded();

      final truncatedContext = context.length > _maxTranscriptChars
          ? '${context.substring(0, _maxTranscriptChars)}…'
          : context;
      final historyResult = _historyMessages(history);
      final userMessage = 'Excerpts:\n$truncatedContext\n\nQuestion: $question';

      // R-8 fix: this path carries retrieved excerpts (up to
      // `_maxTranscriptChars`) AND history sharing the same `_contextSize`
      // -token context window `answerGeneralKnowledgeStream` below doesn't -
      // a single fixed `maxTokens` big enough to stop truncating a typical
      // question would silently overflow the context on a heavy one (near
      // -max excerpts + near-max history at once). `outputBudgetTokens`
      // sizes the output to what's actually left for *this* prompt instead
      // - see its own doc comment for the full reasoning and worst-case
      // math. Neither `_maxTranscriptChars` nor `_maxHistoryChars`
      // (retrieval/history budgets) are touched by this.
      final maxTokens = outputBudgetTokens(
        promptChars: _chatSystemPrompt.length + historyResult.chars + userMessage.length,
        contextSize: _contextSize,
      );

      final raw = await _collectStreaming(
        engine,
        [
          const LlamaChatMessage.fromText(role: LlamaChatRole.system, text: _chatSystemPrompt),
          ...historyResult.messages,
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: userMessage),
        ],
        GenerationParams(maxTokens: maxTokens, temp: 0.2),
        onToken: onToken,
      );

      final answer = raw.trim();
      return answer.isEmpty
          ? 'I couldn\'t generate an answer for that - try rephrasing the question.'
          : answer;
    } finally {
      _lifecycleManager?.endUse(ModelKind.llm);
    }
  }

  @override
  Future<String> answerGeneralKnowledgeStream(
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) async {
    _lifecycleManager?.beginUse(ModelKind.llm);
    try {
      final engine = await _ensureLoaded();

      final raw = await _collectStreaming(
        engine,
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: _generalKnowledgeSystemPrompt,
          ),
          ..._historyMessages(history).messages,
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: question),
        ],
        // R-6 fix: 300 tokens (~200-250 words) was cutting off mid-answer
        // on exactly the kind of open-ended question this path exists for
        // (screenshot evidence: a multi-point "suggested approach" answer
        // stopped mid-list). This path carries no RAG excerpts sharing the
        // `_contextSize`-token context window - only the short system
        // prompt above, up to `_maxHistoryChars` (1500 chars, ~500 tokens
        // worst case) of history, and the question itself - so a fixed
        // 800 has real, safe headroom to spare even in the worst case
        // (unlike `answerQuestionStream`'s excerpt-carrying path below,
        // which as of R-8 computes its budget dynamically per-request
        // instead of using one fixed number, precisely because it doesn't
        // have this path's safe fixed headroom).
        const GenerationParams(maxTokens: 800, temp: 0.4),
        onToken: onToken,
      );

      final answer = raw.trim();
      return answer.isEmpty
          ? 'I couldn\'t generate an answer for that - try rephrasing the question.'
          : answer;
    } finally {
      _lifecycleManager?.endUse(ModelKind.llm);
    }
  }

  @override
  Future<LlmSummaryResult> generateSummary(
    String transcriptText, {
    void Function()? onPreparingModel,
  }) async {
    _lifecycleManager?.beginUse(ModelKind.llm);
    try {
      final engine = await _ensureLoaded(onPreparingModel: onPreparingModel);

      final truncated = transcriptText.length > _maxTranscriptChars
          ? '${transcriptText.substring(0, _maxTranscriptChars)}…'
          : transcriptText;

      final raw = await _collect(
        engine,
        [
          const LlamaChatMessage.fromText(role: LlamaChatRole.system, text: _systemPrompt),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Transcript:\n$truncated',
          ),
        ],
        const GenerationParams(maxTokens: 500, temp: 0.2),
      );

      return _parse(raw);
    } finally {
      _lifecycleManager?.endUse(ModelKind.llm);
    }
  }

  @override
  Future<String> answerQuestion(String context, String question) async {
    _lifecycleManager?.beginUse(ModelKind.llm);
    try {
      return await _answerQuestion(context, question);
    } finally {
      _lifecycleManager?.endUse(ModelKind.llm);
    }
  }

  Future<String> _answerQuestion(String context, String question) async {
    final engine = await _ensureLoaded();

    final truncatedContext = context.length > _maxTranscriptChars
        ? '${context.substring(0, _maxTranscriptChars)}…'
        : context;
    final userMessage = 'Meeting notes:\n$truncatedContext\n\nQuestion: $question';

    // R-8 fix: same 300-token cap, same underlying problem, and the same
    // fix as `answerQuestionStream` above - see `outputBudgetTokens`'s doc
    // comment. This path carries no conversation history at all (unlike
    // Chat), so its worst-case prompt is smaller and it typically gets a
    // larger dynamic budget than the Chat path does for a comparable
    // amount of excerpt text.
    final maxTokens = outputBudgetTokens(
      promptChars: _askSystemPrompt.length + userMessage.length,
      contextSize: _contextSize,
    );

    final raw = await _collect(
      engine,
      [
        const LlamaChatMessage.fromText(role: LlamaChatRole.system, text: _askSystemPrompt),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: userMessage),
      ],
      GenerationParams(maxTokens: maxTokens, temp: 0.2),
    );

    final answer = raw.trim();
    return answer.isEmpty
        ? 'I couldn\'t generate an answer for that - try rephrasing the question.'
        : answer;
  }

  @override
  Future<String> generateFromPrompt(String systemPrompt, String userPrompt) async {
    _lifecycleManager?.beginUse(ModelKind.llm);
    try {
      final engine = await _ensureLoaded();
      final raw = await _collect(
        engine,
        [
          LlamaChatMessage.fromText(role: LlamaChatRole.system, text: systemPrompt),
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: userPrompt),
        ],
        const GenerationParams(maxTokens: 300, temp: 0.2),
      );
      return raw.trim();
    } finally {
      _lifecycleManager?.endUse(ModelKind.llm);
    }
  }

  LlmSummaryResult _parse(String raw) {
    final jsonText = _extractJsonObject(raw);
    if (jsonText == null) {
      throw LlmResponseFormatException(
        'The AI\'s response wasn\'t in the expected format (prompt v$promptVersion) '
        'and couldn\'t be read - please retry.',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(jsonText);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Top-level JSON value was not an object');
      }
      decoded = parsed;
    } on FormatException catch (e) {
      throw LlmResponseFormatException(
        'The AI\'s response wasn\'t valid JSON (prompt v$promptVersion): $e - '
        'please retry.',
      );
    }

    final summary = (decoded['summary'] as String?)?.trim();
    if (summary == null || summary.isEmpty) {
      throw LlmResponseFormatException(
        'The AI\'s response was missing a summary (prompt v$promptVersion) - '
        'please retry.',
      );
    }

    List<String> stringList(dynamic value) {
      if (value is! List) return const [];
      return value.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    return LlmSummaryResult(
      summaryText: summary,
      minutesOfMeeting: (decoded['minutes_of_meeting'] as String?)?.trim() ?? '',
      keyTopics: stringList(decoded['key_topics']),
      // The model is no longer asked for these (see _systemPrompt) - always
      // empty from here on. Manual action item entry is unaffected.
      actionItems: const [],
      decisions: const [],
      modelUsed: modelDisplayName,
    );
  }

  /// Small local models routinely ignore "JSON only" and wrap the object
  /// in ```json fences or a sentence of commentary either side of it.
  /// Rather than failing on that alone, pull out the first balanced
  /// `{...}` object and hand only that to `jsonDecode`.
  String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    for (var i = start; i < raw.length; i++) {
      if (raw[i] == '{') depth++;
      if (raw[i] == '}') {
        depth--;
        if (depth == 0) return raw.substring(start, i + 1);
      }
    }
    return null;
  }
}
