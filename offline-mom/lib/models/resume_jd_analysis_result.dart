/// How confidently a JD requirement was found in a resume - see
/// `ResumeJdAnalyzer`'s own doc comment for the exact, defensible rule each
/// level requires. Deliberately three levels, not a continuous score per
/// requirement: a requirement either matches exactly, shares enough real
/// overlap to be worth a human's attention, or wasn't found - anything
/// finer-grained would imply a precision this heuristic doesn't actually
/// have.
enum MatchLevel { exact, partial, missing }

/// How a match was found - an orthogonal provenance dimension from
/// [MatchLevel], not a replacement for it (docs/v3/01-prd.md §25 Milestone
/// 2). Deterministic matching remains the trust anchor: [exactKeyword] and
/// [alias] are produced by `ResumeJdAnalyzer`'s pre-existing whole-word
/// substring/alias-table logic, [tokenOverlap] by its pre-existing
/// shared-significant-token fallback. [semanticEmbedding] is the new,
/// strictly additive tier - it can only ever turn a [MatchLevel.missing]
/// result into a [MatchLevel.partial] one, never override or remove a
/// deterministic match.
enum MatchSource { exactKeyword, alias, semanticEmbedding, tokenOverlap }

/// One JD requirement (a skill/technology/tool/qualification line) matched
/// against the resume. [resumeEvidence] is the specific resume text that
/// produced the match - always present for [MatchLevel.exact]/[.partial],
/// always null for [MatchLevel.missing] (there is nothing to point to).
/// [matchSource] is null only when [level] is [MatchLevel.missing] - there
/// is nothing to attribute provenance to.
class SkillMatchResult {
  const SkillMatchResult({
    required this.jdRequirement,
    required this.level,
    this.resumeEvidence,
    this.matchSource,
  });

  final String jdRequirement;
  final MatchLevel level;
  final String? resumeEvidence;
  final MatchSource? matchSource;
}

/// The JD's "N years of experience" requirement compared against the
/// resume's own Experience entries. [summary] is always one of a small,
/// fixed set of honest statements - critically including "Unable to
/// determine from resume" for when the resume's dates don't support a
/// confident calculation, never a guessed number presented as fact.
class ExperienceCheckResult {
  const ExperienceCheckResult({
    this.jdRequirementRawText,
    this.requiredMinYears,
    this.requiredMaxYears,
    this.resumeEstimatedYears,
    required this.summary,
  });

  /// Null if the JD had no detectable experience requirement at all.
  final String? jdRequirementRawText;
  final int? requiredMinYears;
  final int? requiredMaxYears;

  /// Null if the resume's Experience entries don't carry enough
  /// confidently-parseable dates to estimate years - see
  /// `ResumeJdAnalyzer._estimateResumeExperienceYears`'s own doc comment.
  final int? resumeEstimatedYears;

  final String summary;
}

/// One JD education or certification requirement compared against the
/// resume's Education/Certification entries - same [MatchLevel] shape as
/// [SkillMatchResult], reused rather than duplicated since the "found /
/// related / not found" question is identical in kind, only applied to a
/// different resume section.
class RequirementCheckResult {
  const RequirementCheckResult({
    required this.jdRequirement,
    required this.level,
    this.resumeEvidence,
    this.matchSource,
  });

  final String jdRequirement;
  final MatchLevel level;
  final String? resumeEvidence;
  final MatchSource? matchSource;
}

/// The full result of comparing one resume against one Job Description -
/// everything the UI needs to render Strong/Partial/Missing/Experience/
/// Education/Certification/Warnings sections without recomputing anything
/// itself. Deliberately a structured result, not a formatted string (see
/// `ResumeJdAnalyzer`'s own doc comment) - the UI decides how to lay this
/// out, this model only decides what's true.
class ResumeJdAnalysisResult {
  const ResumeJdAnalysisResult({
    required this.skillMatches,
    required this.experienceCheck,
    this.educationChecks = const [],
    this.certificationChecks = const [],
    this.warnings = const [],
  });

  final List<SkillMatchResult> skillMatches;
  final ExperienceCheckResult experienceCheck;
  final List<RequirementCheckResult> educationChecks;
  final List<RequirementCheckResult> certificationChecks;
  final List<String> warnings;

  List<SkillMatchResult> get exactSkillMatches =>
      skillMatches.where((m) => m.level == MatchLevel.exact).toList(growable: false);
  List<SkillMatchResult> get partialSkillMatches =>
      skillMatches.where((m) => m.level == MatchLevel.partial).toList(growable: false);
  List<SkillMatchResult> get missingSkillMatches =>
      skillMatches.where((m) => m.level == MatchLevel.missing).toList(growable: false);

  /// A transparent, locally-computed indicator (exact=1.0, partial=0.5,
  /// missing=0.0 weight per requirement, averaged and rounded to a
  /// percentage) - **not** an ATS score, not a claim about how any real
  /// company's or platform's proprietary scoring system would rate this
  /// resume. Null when the JD had no detected requirements to compare at
  /// all, rather than a misleading 0%.
  int? get localMatchIndicatorPercent {
    if (skillMatches.isEmpty) return null;
    final total = skillMatches.fold<double>(0, (sum, m) {
      return sum +
          switch (m.level) {
            MatchLevel.exact => 1.0,
            MatchLevel.partial => 0.5,
            MatchLevel.missing => 0.0,
          };
    });
    return ((total / skillMatches.length) * 100).round();
  }
}
