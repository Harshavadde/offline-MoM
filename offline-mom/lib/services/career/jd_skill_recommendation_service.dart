import '../../models/job_description.dart';
import '../../models/resume_jd_analysis_result.dart';
import '../../models/resume_snapshot.dart';
import '../../models/skill_entry.dart';
import 'resume_jd_analyzer.dart';

/// One JD requirement the user hasn't already confirmed as a skill they
/// have - a proposal only, never auto-included in a resume (AI-Tailored-
/// Resume-from-JD feature's core "no fabrication" rule: a recommendation
/// becomes part of the resume only once the user explicitly accepts it,
/// mirroring `BeginnerResumeInput.confirmedSkills`/`SuggestedSkill`'s own
/// "a suggestion never becomes part of the resume on its own" precedent).
class RecommendedSkill {
  const RecommendedSkill({
    required this.name,
    required this.sourceRequirement,
    this.suggestedCategory = SkillCategory.technical,
  });

  /// The JD requirement text itself, exactly as it appeared in the JD -
  /// this service never rewrites or paraphrases a requirement into a
  /// different skill name.
  final String name;

  /// Kept distinct from [name] in case a future pass wants to show the
  /// original requirement line alongside a cleaned-up display name; today
  /// they're identical.
  final String sourceRequirement;

  /// Always [SkillCategory.technical] - this service has no basis to
  /// decide "tool" vs "soft" vs "technical" from a JD requirement line
  /// alone, and guessing would be exactly the kind of invented detail this
  /// feature must avoid. The user can re-categorize after accepting, like
  /// any other skill, via the normal Resume Editor.
  final SkillCategory suggestedCategory;
}

/// The result of comparing a JD against the skills a user has already
/// confirmed - everything here is either "the user already covers this"
/// (covered) or "the JD wants this and the user hasn't confirmed it yet"
/// (recommended). Nothing here has been added to any resume.
class JdSkillRecommendationResult {
  const JdSkillRecommendationResult({
    required this.recommendedSkills,
    required this.jdKeywordsCovered,
    required this.jdKeywordsMissing,
  });

  final List<RecommendedSkill> recommendedSkills;

  /// JD requirement text the user's confirmed skills already satisfy
  /// (exact match) - display-only, never editable here.
  final List<String> jdKeywordsCovered;

  /// == every [RecommendedSkill.sourceRequirement] - kept as a separate,
  /// plain string list because the review screen's "JD Keywords" section
  /// (user spec §5/§4D) is a read-only display concept distinct from the
  /// "Recommended Skills, each with Add/Remove" section, even though both
  /// are derived from the same underlying analysis.
  final List<String> jdKeywordsMissing;
}

/// Deterministic, offline, no LLM call - reuses the exact same matching
/// logic every other JD-comparison feature in this app already relies on
/// ([ResumeJdAnalyzer]) rather than asking an LLM to judge what skills a
/// user "really" has. This is a deliberate fabrication-risk reduction: an
/// LLM inferring "the user probably knows Django because they know Python
/// and the JD wants Django" would be exactly the kind of invented fact
/// this feature's own spec forbids. Pure text matching has no such failure
/// mode - it can only ever say "the JD mentions X and none of your
/// confirmed skills matched it," never "you know X."
class JdSkillRecommendationService {
  const JdSkillRecommendationService({this.analyzer = const ResumeJdAnalyzer()});

  final ResumeJdAnalyzer analyzer;

  Future<JdSkillRecommendationResult> recommend({
    required ParsedJobDescription jd,
    required List<String> confirmedSkillNames,
  }) async {
    if (jd.requirements.isEmpty) {
      return const JdSkillRecommendationResult(
        recommendedSkills: [],
        jdKeywordsCovered: [],
        jdKeywordsMissing: [],
      );
    }

    // A throwaway snapshot carrying nothing but the user's already-
    // confirmed skills - not a real, persisted resume. resumeId: -1 marks
    // it as synthetic; ResumeJdAnalyzer.analyze() never re-queries a
    // repository by id, it only ever reads the fields it's given, so this
    // is safe.
    final now = DateTime.now();
    final syntheticSnapshot = ResumeSnapshot(
      resumeId: -1,
      compiledAt: now,
      profile: const ResumeSnapshotProfile(fullName: ''),
      skills: [
        for (var i = 0; i < confirmedSkillNames.length; i++)
          ResolvedSkillEntry(
            sourceBlockId: i,
            name: confirmedSkillNames[i],
            category: SkillCategory.technical,
          ),
      ],
    );

    final analysis = await analyzer.analyze(syntheticSnapshot, jd);

    final recommendedSkills = <RecommendedSkill>[];
    final covered = <String>[];
    final missing = <String>[];

    for (final match in analysis.skillMatches) {
      if (match.level == MatchLevel.exact) {
        covered.add(match.jdRequirement);
      } else {
        // MatchLevel.partial (some overlap, but not a confirmed exact
        // skill) and MatchLevel.missing (no overlap at all) are both
        // treated as "not yet confirmed" - a partial token-overlap hit
        // (e.g. confirmed "Azure" vs JD "Azure DevOps") does not mean the
        // user has confirmed "Azure DevOps" itself.
        missing.add(match.jdRequirement);
        recommendedSkills.add(
          RecommendedSkill(name: match.jdRequirement, sourceRequirement: match.jdRequirement),
        );
      }
    }

    return JdSkillRecommendationResult(
      recommendedSkills: recommendedSkills,
      jdKeywordsCovered: covered,
      jdKeywordsMissing: missing,
    );
  }
}
