import '../../../services/ai/llm_engine.dart';
import '../../../services/ai/llm_request_queue.dart';
import '../../../services/resume/resume_import_parser.dart';
import '../../../services/resume/resume_import_second_pass.dart';
import '../../../services/resume/resume_import_second_pass_prompt_builder.dart';

/// Runs the optional LLM-assisted import second pass (docs/v3/01-prd.md
/// §10, Milestone 4) over a [ParsedResumeDraft]'s still-unclassified text
/// and returns a new draft with any newly-structured entries merged in.
///
/// Deterministic parsing remains the default and first attempt always -
/// this use case is only ever invoked explicitly by the user, from the
/// import review screen, after [shouldOfferImportSecondPass] has already
/// decided the unclassified ratio is high enough to be worth offering.
/// "Presented with the same review-before-commit discipline" (the PRD's own
/// words) is upheld structurally: this returns a plain in-memory draft, the
/// same shape [ResumeImportParser.parse] already produces, which the
/// caller feeds straight back into the same per-entry-editable review
/// state (`ResumeImportController.updateDraft`) - nothing here is ever
/// persisted, and every entry it proposes is still fully reviewable/
/// editable/removable before `confirmImport`, exactly like a first-pass
/// entry.
///
/// Never throws: a model failure, empty output, or an output the parser
/// can't extract anything new from all safely degrade to returning
/// [draft] unchanged (see [call]'s own doc comment).
class GenerateImportSecondPassUseCase {
  GenerateImportSecondPassUseCase({
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
    ResumeImportParser parser = const ResumeImportParser(),
    ResumeImportSecondPassPromptBuilder promptBuilder = const ResumeImportSecondPassPromptBuilder(),
  })  : _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue,
        _parser = parser,
        _promptBuilder = promptBuilder;

  final LlmEngine _llmEngine;
  final LlmRequestQueue _llmRequestQueue;
  final ResumeImportParser _parser;
  final ResumeImportSecondPassPromptBuilder _promptBuilder;

  /// Returns a new draft with the second pass's findings merged in via
  /// [mergeImportSecondPass], or [draft] unchanged when: there is no
  /// unclassified text to work with, the model is unavailable or fails
  /// (never throws), or the model's output round-trips through
  /// [ResumeImportParser] without producing anything new.
  Future<ParsedResumeDraft> call(ParsedResumeDraft draft) async {
    if (draft.unclassifiedText.isEmpty) return draft;

    final prompt = _promptBuilder.build(unclassifiedBlocks: draft.unclassifiedText);

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
      return draft;
    }

    if (raw.trim().isEmpty) return draft;

    final secondPassDraft = _parser.parse(raw);
    return mergeImportSecondPass(draft, secondPassDraft);
  }
}
