/// One built prompt, ready to submit to `LlmEngine.generateFromPrompt` -
/// mirrors `ResumeSuggestionPrompt`'s shape.
class ResumeImportSecondPassPrompt {
  const ResumeImportSecondPassPrompt({required this.systemPrompt, required this.userPrompt});

  final String systemPrompt;
  final String userPrompt;
}

/// Builds the prompt for the optional LLM-assisted import second pass
/// (docs/v3/01-prd.md §10, Milestone 4). Pure and stateless, like
/// `ResumeSuggestionPromptBuilder`.
///
/// Deliberately does **not** ask the model to extract structured fields
/// (names, dates, roles) itself - that would mean trusting a local model to
/// both classify *and* transcribe resume content, with no deterministic
/// check on the transcription. Instead the model's only job is to decide
/// which, if any, of a fixed set of section labels each already-existing
/// block of text belongs under, reproducing the block's own text
/// unchanged. The relabeled output is then re-run through the exact same
/// deterministic [ResumeImportParser] the first pass used, which does the
/// actual field extraction - the LLM only ever helps the deterministic
/// parser find a section it missed; it never structures data on its own.
/// This is also what keeps a worst-case model failure safe: if the model
/// ignores the instructions entirely, the reorganized text round-trips
/// through the parser as one big unclassified block, identical to not
/// running the second pass at all.
class ResumeImportSecondPassPromptBuilder {
  const ResumeImportSecondPassPromptBuilder();

  static const _sectionLabels = ['Experience', 'Education', 'Projects', 'Certifications', 'Skills'];

  ResumeImportSecondPassPrompt build({required List<String> unclassifiedBlocks}) {
    const systemPrompt = 'You reorganize leftover resume text that a deterministic parser could '
        'not classify. You will be given several blocks of raw text, separated by blank '
        'lines. Follow these rules exactly:\n'
        '1. For each block, decide whether it clearly belongs to ONE of these resume '
        'sections: Experience, Education, Projects, Certifications, Skills.\n'
        '2. If a block clearly belongs to one of those sections, output a line containing '
        'only that section\'s name, then the block\'s original text completely unchanged, '
        'then a blank line.\n'
        '3. If a block does not clearly belong to any of those sections, output the '
        'block\'s original text completely unchanged, with no section name line, then a '
        'blank line.\n'
        '4. Never invent, remove, translate, reorder within a block, merge separate '
        'blocks together, or reword any part of the original text - only decide which '
        'section (if any) each block belongs to.\n'
        '5. Keep every block in the same relative order you received it in.\n'
        '6. Output ONLY the reorganized blocks - no extra commentary, explanation, '
        'numbering, or markdown formatting.';

    final userPrompt = 'Section names you may use: ${_sectionLabels.join(', ')}.\n\n'
        'Raw blocks:\n\n${unclassifiedBlocks.join('\n\n')}\n\n'
        'Reorganize the blocks above now, following the rules exactly.';

    return ResumeImportSecondPassPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt);
  }
}
