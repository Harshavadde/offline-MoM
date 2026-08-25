/// One built prompt, ready to submit to `LlmEngine.generateFromPrompt` -
/// split into system/user halves so the caller never has to know how
/// they're combined. Deliberately the same small shape as
/// `ResumeSuggestionPrompt` (resume_suggestion_prompt_builder.dart) rather
/// than a shared base class - two unrelated prompt builders happening to
/// have the same two-field shape isn't a reason to couple them.
class JdTailoredSummaryPrompt {
  const JdTailoredSummaryPrompt({required this.systemPrompt, required this.userPrompt});

  final String systemPrompt;
  final String userPrompt;
}

/// Builds the bounded prompt for the AI-Tailored-Resume-from-JD feature's
/// professional-summary generation call. Pure and stateless - same inputs
/// always produce byte-identical output.
///
/// **The entire grounding this class gives the model is the parameters
/// below** - never the JD's own raw text, never anything the user hasn't
/// already confirmed in the wizard. This is deliberately narrower than
/// [ResumeSuggestionPromptBuilder]'s per-entry rewrite prompt: this call
/// has no "original text" to rewrite (there is no resume yet), so every
/// fact the model is allowed to reference must be listed explicitly here
/// instead, exactly the same "only what's already been given" discipline
/// applied to a from-scratch generation rather than a rewrite.
class JdTailoredResumeSummaryPromptBuilder {
  const JdTailoredResumeSummaryPromptBuilder();

  JdTailoredSummaryPrompt build({
    required String targetRoleLabel,
    List<String> confirmedSkillNames = const [],
    String? educationLabel,
    List<String> experienceOneLiners = const [],
    List<String> existingProjectNames = const [],
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Target role: $targetRoleLabel');
    if (confirmedSkillNames.isNotEmpty) {
      buffer.writeln('Confirmed skills: ${confirmedSkillNames.join(', ')}');
    }
    if (educationLabel != null && educationLabel.trim().isNotEmpty) {
      buffer.writeln('Education: ${educationLabel.trim()}');
    }
    if (experienceOneLiners.isNotEmpty) {
      buffer.writeln('Experience:');
      for (final line in experienceOneLiners) {
        buffer.writeln('- $line');
      }
    }
    if (existingProjectNames.isNotEmpty) {
      buffer.writeln('Existing projects: ${existingProjectNames.join(', ')}');
    }

    const systemPrompt = 'You write ONE short professional summary for a resume, based ONLY on '
        'the facts given below. Follow these rules exactly:\n'
        '1. Only use the target role, skills, education, experience, and '
        'projects listed below. Never invent or assume any employer, job '
        'title, years of experience, achievement, metric, certification, or '
        'skill that is not explicitly listed.\n'
        '2. Do not claim a specific number of years of experience unless one '
        'is explicitly given below.\n'
        '3. If little or no experience/projects are given, write a summary '
        'appropriate for someone new to the field - do not imply experience '
        'that was not stated.\n'
        '4. Write 2-4 sentences, professional tone, no bullet points, no '
        'markdown.\n'
        '5. Output ONLY the summary text, with no preamble, heading, or '
        'explanation.';

    final userPrompt = '${buffer.toString().trim()}\n\n'
        'Write the professional summary now, following the rules exactly.';

    return JdTailoredSummaryPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt);
  }
}
