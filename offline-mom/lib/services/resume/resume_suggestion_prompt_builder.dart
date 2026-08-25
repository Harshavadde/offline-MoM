/// One built prompt, ready to submit to `LlmEngine.generateFromPrompt` -
/// split into system/user halves so the caller never has to know how
/// they're combined.
class ResumeSuggestionPrompt {
  const ResumeSuggestionPrompt({required this.systemPrompt, required this.userPrompt});

  final String systemPrompt;
  final String userPrompt;
}

/// Builds the bounded, single-entry prompt for one resume-suggestion
/// generation call (docs/v3/01-prd.md AC3-01/AC3-04, Milestone 3). Pure and
/// stateless - the same inputs always produce byte-identical output, and
/// every call is fully independent of every other (no shared state, no
/// whole-resume or whole-JD content ever passed in), which is what makes
/// the bounded-scope contract enforceable rather than just documented.
///
/// [entryContextLabel]/[jdRequirement]/[originalText] together form the
/// *entire* grounding the model is given - this class is the one place
/// that bound is drawn, not a convention callers have to remember to
/// respect themselves.
class ResumeSuggestionPromptBuilder {
  const ResumeSuggestionPromptBuilder();

  static const _fallbackRequirement = '(no specific job requirement - improve the wording only)';

  ResumeSuggestionPrompt build({
    required String entryContextLabel,
    required String originalText,
    required String jdRequirement,
  }) {
    final requirement = jdRequirement.trim().isEmpty ? _fallbackRequirement : jdRequirement.trim();
    final original = originalText.trim().isEmpty ? '(empty)' : originalText.trim();

    const systemPrompt = 'You rewrite ONE resume entry\'s bullet points to better address ONE '
        'job requirement - nothing else. Follow these rules exactly:\n'
        '1. Only use facts, skills, technologies, numbers, dates, and names that '
        'already appear in the original text below. Never invent or assume '
        'anything that is not already stated there.\n'
        '2. Never add employers, job titles, dates, certifications, clients, '
        'metrics, or achievements that are not already present in the original '
        'text.\n'
        '3. You may reword, reorganize, emphasize, or tighten the existing '
        'content, and you may use terminology from the job requirement only if '
        'the underlying skill or experience is already present in the original '
        'text.\n'
        '4. If you cannot honestly improve the wording without adding a new '
        'fact, return the original bullet points unchanged.\n'
        '5. Output ONLY the rewritten bullet points, one per line, with no '
        'preamble, explanation, numbering, or markdown formatting.';

    final userPrompt = 'Resume entry: $entryContextLabel\n'
        'Job requirement this entry should better address: $requirement\n\n'
        'Original bullet points:\n$original\n\n'
        'Rewrite the bullet points above, one per line, following the rules exactly.';

    return ResumeSuggestionPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt);
  }
}
