/// One built prompt, ready to submit to `LlmEngine.generateFromPrompt`.
class ProjectIdeaPrompt {
  const ProjectIdeaPrompt({required this.systemPrompt, required this.userPrompt});

  final String systemPrompt;
  final String userPrompt;
}

/// Builds one bounded prompt for one JD-relevant project *idea* (never a
/// claim of completed work) for the AI-Tailored-Resume-from-JD feature.
/// Pure and stateless.
///
/// This is the one generative call in the whole feature that is inherently
/// creative rather than a rewrite/summary of facts already provided - a
/// project idea is, by definition, something the user has not built. The
/// "no fabrication" requirement therefore can't be enforced by "only use
/// facts already given" the way the summary/rewrite prompts do it; instead
/// it's enforced structurally, in two layers: (1) this prompt explicitly
/// forbids first-person completed-tense language and demands a fixed,
/// clearly-idea-framed output format, and (2)
/// `GenerateJdTailoredDraftUseCase` runs a deterministic completed-tense
/// regex check on the raw output afterward and discards (never displays)
/// any idea that leaks through anyway - see that use case's own doc
/// comment. Wording alone here is a strong first layer, not the only one.
class ProjectIdeaPromptBuilder {
  const ProjectIdeaPromptBuilder();

  ProjectIdeaPrompt build({
    required String jdTitle,
    required List<String> topRequirements,
    List<String> confirmedSkillNames = const [],
  }) {
    final requirementsText =
        topRequirements.isEmpty ? '(general requirements for this role)' : topRequirements.join(', ');
    final skillsText = confirmedSkillNames.isEmpty ? '(none given)' : confirmedSkillNames.join(', ');

    const systemPrompt = 'You suggest ONE project IDEA that would help someone\'s resume stand '
        'out for a specific job - not a description of something they have '
        'already built. Follow these rules exactly:\n'
        '1. NEVER use first-person or completed-tense language such as "I '
        'built", "I developed", "I created", "I completed", "I delivered", '
        '"I shipped", "I launched", "I implemented", or "I deployed". This is '
        'only a suggestion, not a claim of finished work.\n'
        '2. Frame it explicitly as an idea, e.g. "A project that would '
        'demonstrate..." or "Building a ... would show...".\n'
        '3. Base the idea on the job requirements and skills given below - do '
        'not assume the person already has skills beyond what is listed.\n'
        '4. Output EXACTLY three lines, in this exact format, nothing else:\n'
        'Title: <a short project title>\n'
        'Technologies: <comma-separated list of relevant technologies>\n'
        'Features: <comma-separated list of 2-4 suggested features>';

    final userPrompt = 'Target role: $jdTitle\n'
        'Key job requirements: $requirementsText\n'
        'Skills the person has already confirmed: $skillsText\n\n'
        'Suggest one project idea now, in the exact 3-line format, following the rules exactly.';

    return ProjectIdeaPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt);
  }
}
