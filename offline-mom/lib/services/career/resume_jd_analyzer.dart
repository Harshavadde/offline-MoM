import '../../models/job_description.dart';
import '../../models/resume_jd_analysis_result.dart';
import '../../models/resume_snapshot.dart';
import 'resume_jd_semantic_matcher.dart';

/// A small, explicit set of abbreviation<->full-name pairs - deliberately
/// not a general synonym dictionary (Batch 8's own "do not build a giant
/// speculative synonym dictionary" rule). Each pair here is a genuine
/// abbreviation of the *same* thing (JS is not a related technology to
/// JavaScript, it *is* JavaScript), unlike "Kubernetes"/"Docker" or
/// "React"/"Angular", which name different technologies and are
/// deliberately never aliased. Every key and value is stored normalized
/// (lowercase); both sides of a pair map to the same canonical form so
/// either spelling compares equal after normalization.
const Map<String, String> _aliases = {
  'js': 'javascript',
  'ts': 'typescript',
  'k8s': 'kubernetes',
  'ci/cd': 'ci-cd',
  'cicd': 'ci-cd',
  'node': 'node.js',
  'nodejs': 'node.js',
  'py': 'python',
  'ml': 'machine learning',
  'ai': 'artificial intelligence',
  'db': 'database',
  'ux': 'user experience',
  'ui': 'user interface',
};

const Set<String> _stopwords = {
  'a', 'an', 'the', 'and', 'or', 'of', 'in', 'with', 'for', 'to', 'is',
  'are', 'on', 'at', 'as', 'be', 'by', 'this', 'that', 'will', 'you',
};

const Map<String, List<String>> _degreeLevelKeywords = {
  'bachelor': ["bachelor", "b.s.", "b.a.", "bsc", 'undergraduate degree'],
  'master': ['master', 'm.s.', 'm.a.', 'mba', 'msc', 'graduate degree'],
  'doctorate': ['phd', 'ph.d', 'doctorate', 'doctoral'],
};

/// Lowercases, trims, strips punctuation other than `./+#-` (kept since
/// they appear inside real tokens like "C++"/"Node.js"/"CI/CD"), and
/// collapses whitespace. Not private: `SuggestionFabricationGuard`
/// (lib/services/resume/suggestion_fabrication_guard.dart) reuses this
/// exact normalization for its own "does this word already appear
/// somewhere in the original text" comparison, rather than duplicating an
/// equivalent function.
String normalizeResumeText(String text) {
  return text
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s./+#-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _canonicalize(String normalized) => _aliases[normalized] ?? normalized;

Set<String> _significantTokens(String normalized) {
  return normalized
      .split(RegExp(r'\s+'))
      .map(_canonicalize)
      .where((t) => t.isNotEmpty && !_stopwords.contains(t) && (t.length >= 3 || RegExp(r'[0-9#+]').hasMatch(t)))
      .toSet();
}

/// One resume text unit a JD requirement can be matched against - a single
/// skill name, or one bullet/degree/detail line - kept alongside the exact
/// resume text it came from so a match can point back to real evidence.
class _ResumeTextUnit {
  const _ResumeTextUnit(this.text);
  final String text;
}

/// Compares an already-compiled [ResumeSnapshot] against an already-parsed
/// [ParsedJobDescription] and produces a [ResumeJdAnalysisResult] - pure,
/// deterministic, offline, no AI model or network call of any kind (see
/// the Batch 8 report's privacy/offline guarantees section). Mirrors
/// `ResumeCompilerService`'s own shape: a stateless class operating only on
/// already-resolved data passed in as plain parameters, never re-reading a
/// repository itself.
///
/// Every match is one of exactly three levels ([MatchLevel]), each backed
/// by an explainable, non-invented rule - see [_matchRequirement]'s own
/// doc comment for the exact rule each level requires. This deliberately
/// does not attempt to reproduce any real company's or platform's
/// proprietary ATS scoring algorithm - [ResumeJdAnalysisResult.localMatchIndicatorPercent]
/// is documented, at the model level, as a local indicator only.
///
/// [semanticMatcher] (docs/v3/01-prd.md §25 Milestone 2) is optional and
/// defaults to null, so every pre-existing call site (`const
/// ResumeJdAnalyzer()`) keeps compiling and behaving exactly as before.
/// When supplied, it runs as a strictly additive tier *after* deterministic
/// matching - see [_applySemanticTier]'s own doc comment. Deterministic
/// matching (exact/alias/token-overlap) remains the trust anchor
/// regardless of whether a semantic matcher is supplied.
class ResumeJdAnalyzer {
  const ResumeJdAnalyzer({ResumeJdSemanticMatcher? semanticMatcher}) : _semanticMatcher = semanticMatcher;

  final ResumeJdSemanticMatcher? _semanticMatcher;

  Future<ResumeJdAnalysisResult> analyze(ResumeSnapshot snapshot, ParsedJobDescription jd) async {
    final resumeUnits = _buildResumeUnits(snapshot);

    final deterministicSkillMatches = jd.requirements
        .map((requirement) => _matchRequirement(requirement, resumeUnits))
        .toList(growable: false);
    final skillMatches = await _applySemanticTier(deterministicSkillMatches, resumeUnits);

    final educationChecks = jd.educationRequirements
        .map((requirement) => _matchEducationRequirement(requirement, snapshot.education))
        .toList(growable: false);

    final certificationUnits = snapshot.certifications
        .map((c) => _ResumeTextUnit(c.name))
        .toList(growable: false);
    final certificationChecks = jd.certificationRequirements.map((requirement) {
      final match = _matchRequirement(requirement, certificationUnits);
      return RequirementCheckResult(
        jdRequirement: requirement,
        level: match.level,
        resumeEvidence: match.resumeEvidence,
        matchSource: match.matchSource,
      );
    }).toList(growable: false);

    final experienceCheck = _checkExperience(jd.experienceRequirement, snapshot.experience);

    final warnings = <String>[...jd.warnings];
    if (jd.requirements.isEmpty) {
      warnings.add('No JD requirements were detected to compare against this resume.');
    }
    if (snapshot.skills.isEmpty && snapshot.experience.isEmpty && snapshot.projects.isEmpty) {
      warnings.add(
        'This resume has no skills, experience, or project entries - '
        'analysis results may be incomplete.',
      );
    }

    return ResumeJdAnalysisResult(
      skillMatches: skillMatches,
      experienceCheck: experienceCheck,
      educationChecks: educationChecks,
      certificationChecks: certificationChecks,
      warnings: warnings,
    );
  }

  /// Runs the optional semantic tier over [matches] - scoped to skill
  /// matches only (not education/certification, which stay purely
  /// deterministic, keeping the additive tier's blast radius small and
  /// testable). For every requirement still [MatchLevel.missing] after
  /// deterministic matching, asks [_semanticMatcher] for the best
  /// semantically-similar resume text unit; a hit becomes
  /// [MatchLevel.partial] tagged [MatchSource.semanticEmbedding]. A
  /// [MatchLevel.exact] or [MatchLevel.partial] deterministic result is
  /// always returned unchanged - this can only add evidence where there
  /// was none, never remove or downgrade an existing match. If no
  /// [_semanticMatcher] was supplied, or it finds nothing (including when
  /// it silently swallowed an embedding failure - see
  /// [ResumeJdSemanticMatcher]'s own doc comment), the deterministic
  /// result passes through unchanged, so an unavailable/failed embedding
  /// model never fails the analysis.
  Future<List<SkillMatchResult>> _applySemanticTier(
    List<SkillMatchResult> matches,
    List<_ResumeTextUnit> units,
  ) async {
    final matcher = _semanticMatcher;
    if (matcher == null || units.isEmpty) return matches;

    final candidateTexts = units.map((u) => u.text).toList(growable: false);
    final result = <SkillMatchResult>[];
    for (final match in matches) {
      if (match.level != MatchLevel.missing) {
        result.add(match);
        continue;
      }
      final semanticEvidence = await matcher.findBestMatch(match.jdRequirement, candidateTexts);
      result.add(
        semanticEvidence == null
            ? match
            : SkillMatchResult(
                jdRequirement: match.jdRequirement,
                level: MatchLevel.partial,
                resumeEvidence: semanticEvidence,
                matchSource: MatchSource.semanticEmbedding,
              ),
      );
    }
    return result;
  }

  List<_ResumeTextUnit> _buildResumeUnits(ResumeSnapshot snapshot) {
    final units = <_ResumeTextUnit>[];
    for (final skill in snapshot.skills) {
      units.add(_ResumeTextUnit(skill.name));
    }
    for (final e in snapshot.experience) {
      units.add(_ResumeTextUnit('${e.role} ${e.company}'));
      for (final bullet in e.bullets) {
        units.add(_ResumeTextUnit(bullet));
      }
      // Part H (JD tailoring re-verification, product-quality remediation
      // pass): sub-project content (D-M9-01, migration v20) was
      // previously invisible to JD matching entirely - a requirement
      // genuinely demonstrated only inside a named sub-project's own
      // bullets (e.g. "AWS S3" mentioned only under a role's "SciLab"
      // sub-project, not the role's own top-level bullets) was reported
      // as missing even though the resume actually shows it. Read-only:
      // this only affects what counts as *evidence* for a match, never a
      // write path, so it carries none of the override-mechanism risk
      // sub-projects were deliberately kept out of (see
      // resume_compiler_service.dart's own comment on that boundary).
      for (final subProject in e.subProjects) {
        units.add(_ResumeTextUnit(subProject.name));
        for (final bullet in subProject.bullets) {
          units.add(_ResumeTextUnit(bullet));
        }
      }
    }
    for (final p in snapshot.projects) {
      units.add(_ResumeTextUnit(p.name));
      for (final bullet in p.bullets) {
        units.add(_ResumeTextUnit(bullet));
      }
    }
    for (final ed in snapshot.education) {
      units.add(_ResumeTextUnit('${ed.degree} ${ed.fieldOfStudy ?? ''}'.trim()));
      for (final detail in ed.details) {
        units.add(_ResumeTextUnit(detail));
      }
    }
    for (final c in snapshot.certifications) {
      units.add(_ResumeTextUnit(c.name));
    }
    return units;
  }

  /// - [MatchLevel.exact]: the requirement's normalized (and alias-resolved)
  ///   text equals a resume unit exactly, or appears as a whole-word-bounded
  ///   substring within one.
  /// - [MatchLevel.partial]: not exact, but the requirement and a resume
  ///   unit share at least one "significant" word token (3+ letters, or
  ///   containing a digit/symbol, and not a stopword) - e.g. "Azure
  ///   DevOps" (JD) sharing "azure" with a resume's "Azure" skill entry.
  /// - [MatchLevel.missing]: no resume unit satisfies either rule.
  SkillMatchResult _matchRequirement(String requirement, List<_ResumeTextUnit> units) {
    final rawNormalizedRequirement = normalizeResumeText(requirement);
    final normalizedRequirement = _canonicalize(rawNormalizedRequirement);
    final requirementTokens = _significantTokens(rawNormalizedRequirement);

    for (final unit in units) {
      final rawNormalizedUnit = normalizeResumeText(unit.text);
      final normalizedUnit = _canonicalize(rawNormalizedUnit);
      if (normalizedUnit == normalizedRequirement ||
          RegExp(r'\b' + RegExp.escape(normalizedRequirement) + r'\b').hasMatch(normalizedUnit)) {
        // Canonicalization only changes the compared string when an alias
        // table entry applied on either side - if neither side needed it,
        // the match was on the raw text as written in both the JD and the
        // resume.
        final usedAlias = rawNormalizedRequirement != normalizedRequirement || rawNormalizedUnit != normalizedUnit;
        return SkillMatchResult(
          jdRequirement: requirement,
          level: MatchLevel.exact,
          resumeEvidence: unit.text,
          matchSource: usedAlias ? MatchSource.alias : MatchSource.exactKeyword,
        );
      }
    }

    if (requirementTokens.isNotEmpty) {
      for (final unit in units) {
        final unitTokens = _significantTokens(normalizeResumeText(unit.text));
        if (requirementTokens.intersection(unitTokens).isNotEmpty) {
          return SkillMatchResult(
            jdRequirement: requirement,
            level: MatchLevel.partial,
            resumeEvidence: unit.text,
            matchSource: MatchSource.tokenOverlap,
          );
        }
      }
    }

    return SkillMatchResult(jdRequirement: requirement, level: MatchLevel.missing);
  }

  RequirementCheckResult _matchEducationRequirement(
    String requirement,
    List<ResolvedEducationEntry> education,
  ) {
    final normalizedRequirement = normalizeResumeText(requirement);
    final requiredLevel = _degreeLevelKeywords.entries
        .firstWhere(
          (entry) => entry.value.any((kw) => normalizedRequirement.contains(kw)),
          orElse: () => const MapEntry('', []),
        )
        .key;

    final units = education
        .map((ed) => _ResumeTextUnit('${ed.degree} ${ed.fieldOfStudy ?? ''}'.trim()))
        .toList(growable: false);

    if (requiredLevel.isNotEmpty) {
      for (final unit in units) {
        final normalizedUnit = normalizeResumeText(unit.text);
        final keywords = _degreeLevelKeywords[requiredLevel]!;
        if (keywords.any((kw) => normalizedUnit.contains(kw))) {
          return RequirementCheckResult(
            jdRequirement: requirement,
            level: MatchLevel.exact,
            resumeEvidence: unit.text,
            matchSource: MatchSource.exactKeyword,
          );
        }
      }
    }

    final match = _matchRequirement(requirement, units);
    return RequirementCheckResult(
      jdRequirement: requirement,
      level: match.level,
      resumeEvidence: match.resumeEvidence,
      matchSource: match.matchSource,
    );
  }

  ExperienceCheckResult _checkExperience(
    JdExperienceRequirement? requirement,
    List<ResolvedExperienceEntry> experience,
  ) {
    if (requirement == null) {
      return const ExperienceCheckResult(
        summary: 'No specific years-of-experience requirement was detected '
            'in this job description.',
      );
    }

    final estimatedYears = _estimateResumeExperienceYears(experience);
    if (estimatedYears == null) {
      return ExperienceCheckResult(
        jdRequirementRawText: requirement.rawText,
        requiredMinYears: requirement.minYears,
        requiredMaxYears: requirement.maxYears,
        summary: 'Unable to determine from resume - the resume\'s '
            'experience entries don\'t have dates specific enough to '
            'calculate total years.',
      );
    }

    final meets = estimatedYears >= requirement.minYears;
    final rangeText = requirement.maxYears != null
        ? '${requirement.minYears}-${requirement.maxYears} years'
        : '${requirement.minYears}+ years';

    return ExperienceCheckResult(
      jdRequirementRawText: requirement.rawText,
      requiredMinYears: requirement.minYears,
      requiredMaxYears: requirement.maxYears,
      resumeEstimatedYears: estimatedYears,
      summary: meets
          ? 'The resume shows approximately $estimatedYears year(s) of '
              'experience, which meets or exceeds the $rangeText requirement.'
          : 'The resume shows approximately $estimatedYears year(s) of '
              'experience, which is below the $rangeText requirement.',
    );
  }

  /// Estimates total years of experience as the span between the earliest
  /// confidently-parsed start year and the latest end year (an open/null
  /// end date, or one containing "present"/"current", counts as the
  /// current year) - not a sum across entries, which would double-count
  /// overlapping roles. Returns null if not a single experience entry has
  /// a parseable 4-digit start year, rather than guessing a number from
  /// nothing.
  int? _estimateResumeExperienceYears(List<ResolvedExperienceEntry> experience) {
    final yearPattern = RegExp(r'(19|20)\d{2}');
    int? earliestStart;
    int? latestEnd;

    for (final entry in experience) {
      final startMatch = yearPattern.firstMatch(entry.startDate);
      if (startMatch == null) continue;
      final startYear = int.parse(startMatch.group(0)!);

      final endDate = entry.endDate;
      final int endYear;
      if (endDate == null || RegExp(r'present|current', caseSensitive: false).hasMatch(endDate)) {
        endYear = DateTime.now().year;
      } else {
        final endMatch = yearPattern.firstMatch(endDate);
        endYear = endMatch != null ? int.parse(endMatch.group(0)!) : startYear;
      }

      earliestStart = earliestStart == null ? startYear : (startYear < earliestStart ? startYear : earliestStart);
      latestEnd = latestEnd == null ? endYear : (endYear > latestEnd ? endYear : latestEnd);
    }

    if (earliestStart == null || latestEnd == null) return null;
    final years = latestEnd - earliestStart;
    return years < 0 ? 0 : years;
  }
}
