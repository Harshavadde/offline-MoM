import '../../../models/resume_jd_analysis_result.dart';
import '../../../models/resume_snapshot.dart';

/// Deterministically reorders a [ResumeSnapshot]'s Experience, Project, and
/// Skill entries so the ones that produced the most matches against a JD
/// (docs/v3/01-prd.md §25 Milestone 2, hard requirement 5) surface first -
/// pure re-ranking, never a rewrite. No entry's own fields are ever
/// changed, no entry is added or removed - only list order moves. No
/// LLM/embedding call is made here: this operates purely on the
/// already-computed [ResumeJdAnalysisResult] evidence strings the analyzer
/// produced (deterministic or semantic - both count equally as "this
/// entry produced a match"), never on the JD requirements or resume
/// content directly.
///
/// Deliberately scoped to Experience/Projects/Skills, not
/// Education/Certifications: those two sections are conventionally kept in
/// a fixed credential/chronological order rather than relevance-reordered,
/// so leaving them untouched matches real resume-tailoring practice and
/// keeps this use case's blast radius bounded.
class PrioritizeResumeContentUseCase {
  const PrioritizeResumeContentUseCase();

  ResumeSnapshot call(ResumeSnapshot snapshot, ResumeJdAnalysisResult analysisResult) {
    final matchedEvidence = <String>{
      for (final match in analysisResult.skillMatches)
        if (match.resumeEvidence != null) match.resumeEvidence!,
    };

    return snapshot.copyWith(
      experience: _sortByDensity(
        snapshot.experience,
        (e) => [
          '${e.role} ${e.company}',
          ...e.bullets,
          // Part H (JD tailoring re-verification): sub-project bullets
          // (D-M9-01) are now real evidence `ResumeJdAnalyzer` can match
          // against (see that file's own Part H fix) - without also
          // including them here, an entry whose *only* matched evidence
          // came from a sub-project would score 0 density and never
          // surface first, even though it genuinely matched the JD.
          for (final subProject in e.subProjects) ...[subProject.name, ...subProject.bullets],
        ],
        matchedEvidence,
      ),
      projects: _sortByDensity(
        snapshot.projects,
        (p) => [p.name, ...p.bullets],
        matchedEvidence,
      ),
      skills: _sortByDensity(
        snapshot.skills,
        (s) => [s.name],
        matchedEvidence,
      ),
    );
  }

  /// Stable, deterministic descending sort by match density. Dart's
  /// `List.sort()` is not guaranteed stable, so entries are decorated with
  /// their original index first and ties are broken by it - equal-score
  /// entries keep their original relative order rather than an arbitrary
  /// one, which is what "purely ordering, never inventing content" demands
  /// in practice: a re-run with an identical analysis result must always
  /// produce an identical order.
  List<T> _sortByDensity<T>(
    List<T> entries,
    List<String> Function(T) textUnitsOf,
    Set<String> matchedEvidence,
  ) {
    if (entries.isEmpty) return entries;

    final decorated = <(int score, int originalIndex, T entry)>[
      for (var i = 0; i < entries.length; i++)
        (textUnitsOf(entries[i]).where(matchedEvidence.contains).length, i, entries[i]),
    ];

    decorated.sort((a, b) {
      final scoreCompare = b.$1.compareTo(a.$1);
      return scoreCompare != 0 ? scoreCompare : a.$2.compareTo(b.$2);
    });

    return decorated.map((d) => d.$3).toList(growable: false);
  }
}
