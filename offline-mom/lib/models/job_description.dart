/// A JD's detected "N years of experience" requirement - kept separate
/// from the surrounding text so the analyzer can compare numbers, not
/// re-parse a sentence. [rawText] is always preserved alongside the parsed
/// numbers so the UI can show exactly what the JD said, never just a
/// number the user can't trace back to source text.
class JdExperienceRequirement {
  const JdExperienceRequirement({
    required this.minYears,
    this.maxYears,
    required this.rawText,
  });

  final int minYears;

  /// Null for an open-ended requirement ("3+ years") rather than a range
  /// ("2-4 years").
  final int? maxYears;

  final String rawText;
}

/// A local, in-memory representation of an imported Job Description -
/// mirrors `ParsedResumeDraft`'s exact reasoning
/// (lib/services/resume/resume_import_parser.dart): nothing here is
/// persisted to the database (Batch 8 deliberately holds a JD only for the
/// lifetime of one analysis session - see the Batch 8 report for why), and
/// every field is either genuinely detected or left null/empty, never
/// invented. [rawText] is always preserved in full regardless of how much
/// (or how little) structure could be confidently extracted from it.
class ParsedJobDescription {
  const ParsedJobDescription({
    required this.rawText,
    this.title,
    this.company,
    this.requirements = const [],
    this.responsibilities = const [],
    this.educationRequirements = const [],
    this.certificationRequirements = const [],
    this.experienceRequirement,
    this.unclassifiedText = const [],
    this.warnings = const [],
  });

  /// The full extracted text, unmodified - always present, since it's
  /// exactly what came out of the document extractor.
  final String rawText;

  final String? title;
  final String? company;

  /// Required skills/technologies/tools/qualifications - one entry per
  /// detected requirement line, verbatim (see `JdParser`'s own doc comment
  /// for why entries are never split or reworded). This is what
  /// `ResumeJdAnalyzer` matches against the resume.
  final List<String> requirements;

  final List<String> responsibilities;
  final List<String> educationRequirements;
  final List<String> certificationRequirements;

  /// Null if no confident "N years of experience"-shaped statement was
  /// found anywhere in the document - never a guessed default.
  final JdExperienceRequirement? experienceRequirement;

  /// Content the parser found but could not confidently classify into any
  /// of the above - the same "safe review area" `ParsedResumeDraft` uses,
  /// never silently dropped.
  final List<String> unclassifiedText;

  final List<String> warnings;

  bool get hasAnyStructuredContent =>
      title != null ||
      company != null ||
      requirements.isNotEmpty ||
      responsibilities.isNotEmpty ||
      educationRequirements.isNotEmpty ||
      certificationRequirements.isNotEmpty ||
      experienceRequirement != null;
}
