/// Who spoke a prior turn in [LlmChatTurn] - the engine-level equivalent of
/// [ChatMessageRole] (`models/chat_message.dart`), kept as a separate,
/// smaller type here so this file never depends on the app's persistence
/// model - only role+text are needed to give the model short-term memory of
/// the conversation, never `sourcesJson`/`answerProvenance`/timestamps.
enum LlmChatRole { user, assistant }

/// One prior turn of the conversation, supplied so a follow-up like
/// "translate that into French" is understood as referring to the previous
/// answer rather than met with "what should I translate?" (Phase 7A). Always
/// oldest-first when passed as a list; callers are responsible for bounding
/// how much history they supply - this type itself has no size limit.
class LlmChatTurn {
  const LlmChatTurn({required this.role, required this.text});

  final LlmChatRole role;
  final String text;
}

/// A single action item. [LlmEngine] no longer extracts these itself (see
/// [LlmSummaryResult.actionItems]) - the type stays only because
/// [ActionItem]-shaped data still flows through this same result record
/// wherever a caller might supply it (e.g. tests), and because reversing
/// this again someday shouldn't need a type resurrected from scratch.
class LlmActionItem {
  const LlmActionItem({required this.task, this.owner, this.deadline});

  final String task;
  final String? owner;
  final DateTime? deadline;
}

class LlmSummaryResult {
  const LlmSummaryResult({
    required this.summaryText,
    required this.minutesOfMeeting,
    required this.keyTopics,
    required this.actionItems,
    required this.decisions,
    required this.modelUsed,
  });

  final String summaryText;
  final String minutesOfMeeting;
  final List<String> keyTopics;

  /// Always empty from [LlamaDartLlmEngine] - see its `_systemPrompt` doc
  /// comment for why action items and decisions were dropped from what
  /// the model is asked to produce. Manually adding action items from the
  /// Action Items tab is unaffected; this is only about AI auto-extraction.
  final List<LlmActionItem> actionItems;

  /// Always empty from [LlamaDartLlmEngine] - see [actionItems].
  final List<String> decisions;
  final String modelUsed;
}

/// Contract for turning transcript text into a summary, Minutes of Meeting
/// and key topics - entirely on-device.
///
/// Presentation/use-case code depends only on this interface, never on
/// llama.cpp or any specific wrapper package directly, so the engine can be
/// swapped without touching a single screen.
abstract class LlmEngine {
  /// [onPreparingModel] fires once, only the very first time this device
  /// runs any AI feature: the LLM (~1.1GB) has to be downloaded before it
  /// can generate anything. Callers use it to show "downloading the AI
  /// model" instead of leaving the user staring at a generic "generating
  /// summary" spinner for however long that one-time download takes.
  Future<LlmSummaryResult> generateSummary(
    String transcriptText, {
    void Function()? onPreparingModel,
  });

  /// Answers a free-form question using only [context] (excerpts pulled
  /// from the user's own meetings) - entirely on-device, no web search or
  /// general knowledge the model happens to know.
  Future<String> answerQuestion(String context, String question);

  /// Same contract as [answerQuestion], for the Chat module's prompt
  /// (docs/v2/11-ai-architecture.md's chat prompt contract, ADR-026 -
  /// docs/v2/implementation/03-decisions.md), with progressive delivery:
  /// [onToken] fires once per token/delta as the model produces it, in
  /// order, before this method's returned [Future] resolves with the full
  /// answer. Still a single request/response as far as [LlmRequestQueue]
  /// is concerned - the queue awaits this whole call before considering
  /// the engine free, so this adds real token-by-token UI streaming
  /// without changing the queue's one-request-at-a-time contract at all
  /// (ADR-026). [onToken] is best-effort UI sugar: a caller that never
  /// reads the stream still gets the correct complete answer from the
  /// returned [Future].
  ///
  /// [history], if supplied, is recent prior turns of the same session
  /// (oldest-first) - short-term conversation memory (Phase 7A) so a
  /// follow-up question can refer back to what was just discussed. Empty by
  /// default: a caller that never supplies it gets the original
  /// single-turn behavior unchanged.
  Future<String> answerQuestionStream(
    String context,
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  });

  /// Answers [question] from the model's own parametric knowledge - the
  /// *opposite* prompt contract from [answerQuestionStream]: no
  /// [context] is supplied at all, and the system prompt explicitly
  /// permits (rather than forbids) the model to draw on what it already
  /// knows. Added in Phase 6B (Hybrid Retrieval Engine, ADR-037) for the
  /// approved product decision that a question with no confident match in
  /// the user's own content should still get answered, using the
  /// downloaded local model's general knowledge - never a network call,
  /// never a different model, just a different question asked of the
  /// same on-device one.
  ///
  /// Callers **must** treat every answer from this method as
  /// [AnswerProvenance.generalKnowledge] and must never attach citations
  /// to it - there is no retrieved content behind this answer to cite
  /// (`WorkspaceChatUseCase`'s "do not fabricate citations" contract,
  /// unchanged, now extended to this second prompt mode too). [onToken]
  /// streams progressively, identical semantics to
  /// [answerQuestionStream]'s. [history] is the same short-term
  /// conversation memory described on [answerQuestionStream].
  Future<String> answerGeneralKnowledgeStream(
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  });

  /// Submits one bounded, caller-composed prompt and returns the model's
  /// raw text response - entirely on-device, single request/response, no
  /// streaming. Unlike every other method on this interface, the full
  /// prompt (system instructions and user content) is supplied by the
  /// caller rather than hard-coded here: added for V3 Milestone 3's resume
  /// suggestion pipeline (docs/v3/01-prd.md AC3-01/AC3-04), where a
  /// separate, independently-testable prompt builder
  /// (`ResumeSuggestionPromptBuilder`) owns the prompt content
  /// (fabrication-ban instructions, bounded one-entry scope,
  /// structured-output format) - this method's only job is
  /// submitting it and returning the raw result, never interpreting or
  /// validating it. Callers remain responsible for their own bounded-scope
  /// discipline; this method enforces none itself.
  Future<String> generateFromPrompt(String systemPrompt, String userPrompt);

  /// Downloads and loads the model without generating anything - used by
  /// onboarding's model-setup step, so the user waits once, up front, on a
  /// screen that says exactly what's happening, instead of the download
  /// silently happening the first time they generate a summary or ask a
  /// question. [onProgress] reports 0.0-1.0 (or null if the total size
  /// isn't known yet).
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  });
}
