import '../../../services/ai/llm_engine.dart';
import '../../../services/ai/llm_request_queue.dart';
import '../../../services/resume/resume_suggestion_prompt_builder.dart';

/// Generates one JD-agnostic rewrite suggestion for a block editor's own
/// bullets/details field (docs/v3/01-prd.md §12, FR3-17, Tier 2 - "an
/// explicit user-triggered action after a pause/blur, never continuous").
///
/// Deliberately **does not** persist a [SuggestedEdit] row or touch
/// [SuggestedEditRepository]/[AcceptSuggestedEditUseCase] - unlike
/// Milestone 3's JD-tailoring suggestions, a block editor edits the
/// *shared library block's own canonical content* directly (via its own
/// pre-existing `_save()` method, e.g. `ExperienceBlockRepository.update`),
/// never through a per-resume [ResumeBlockRef.overrideJson]. Routing a
/// Tier-2 rewrite through [AcceptSuggestedEditUseCase] would silently
/// create an unrelated per-resume override instead of updating the field
/// the user is actually editing - the wrong operation for this context.
/// "AI proposes, user decides" (§2 non-negotiable #10) is upheld here the
/// same way a manual edit already is: this use case only ever returns a
/// candidate string for the caller to display; nothing reaches any
/// database row until the user's own pre-existing, explicit "Save" action
/// on the block form - the identical review discipline as if the user had
/// typed the replacement text themselves.
///
/// Reuses [ResumeSuggestionPromptBuilder] with an empty `jdRequirement`
/// (the builder's own fallback: "(no specific job requirement - improve
/// the wording only)") rather than a second prompt-construction
/// implementation, and the same [LlmRequestQueue]/[LlmEngine.generateFromPrompt]
/// path Milestone 3's generation already uses - no new AI plumbing.
class GenerateBulletRewriteUseCase {
  GenerateBulletRewriteUseCase({
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
    ResumeSuggestionPromptBuilder promptBuilder = const ResumeSuggestionPromptBuilder(),
  })  : _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue,
        _promptBuilder = promptBuilder;

  final LlmEngine _llmEngine;
  final LlmRequestQueue _llmRequestQueue;
  final ResumeSuggestionPromptBuilder _promptBuilder;

  /// Returns the rewritten text (bullets/details, newline-joined) or null
  /// when there is nothing to propose: empty input, the model is
  /// unavailable or fails (AC3-05 - never throws), the output is empty/
  /// malformed after parsing, or the model returned the original text
  /// unchanged.
  Future<String?> call({required String entryContextLabel, required String originalText}) async {
    final trimmedOriginal = originalText.trim();
    if (trimmedOriginal.isEmpty) return null;

    final prompt = _promptBuilder.build(
      entryContextLabel: entryContextLabel,
      originalText: trimmedOriginal,
      jdRequirement: '',
    );

    final String raw;
    try {
      raw = await _llmRequestQueue
          .enqueue(
            LlmQueueRequest(
              isForeground: true,
              run: () => _llmEngine.generateFromPrompt(prompt.systemPrompt, prompt.userPrompt),
            ),
          )
          .result;
    } catch (_) {
      return null;
    }

    final lines =
        raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(growable: false);
    if (lines.isEmpty) return null;

    final suggestedText = lines.join('\n');
    return suggestedText == trimmedOriginal ? null : suggestedText;
  }
}
