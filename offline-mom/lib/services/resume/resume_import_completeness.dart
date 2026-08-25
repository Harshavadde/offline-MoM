/// Machine-checkable evidence that [ResumeImportParser.parse] genuinely
/// preserved everything it found in the source document - real-device
/// findings remediation follow-up: prior passes fixed specific reported
/// data-loss bugs one at a time (missing Experience, missing Education, a
/// dropped location), but had no general mechanism to *prove* a given
/// import run didn't silently drop something else. This report is built
/// from the exact same block/section counts the parser itself already
/// computes while parsing (never a second, independently-guessed count
/// that could drift from what the parser actually did), and expresses one
/// invariant per section: every source item the parser found must end up
/// either a real structured entry or a `unclassifiedText`/review item -
/// never neither. [SectionCompleteness.missingCount] should always be `0`
/// by construction; a positive value is a genuine parser bug, not a
/// judgment call, and is exactly what this report exists to surface
/// instead of letting it pass unnoticed.
class ResumeImportCompletenessReport {
  const ResumeImportCompletenessReport({this.sections = const []});

  /// A report with no sections at all - used as the default for
  /// [ParsedResumeDraft] constructions that don't supply a real one (test
  /// fixtures built directly, or a draft from before this field existed),
  /// so adding this field doesn't require touching every existing call
  /// site. Vacuously complete (`isComplete` is `true`) since there is
  /// nothing to check.
  static const empty = ResumeImportCompletenessReport();

  final List<SectionCompleteness> sections;

  /// True only if every section accounted for every source item it found -
  /// the property [ResumeImportParser] itself should always guarantee by
  /// construction (every block either becomes a structured entry or is
  /// pushed to `unclassifiedText`, never dropped in between).
  bool get isComplete => sections.every((s) => s.missingCount == 0);

  int get totalMissing => sections.fold(0, (sum, s) => sum + s.missingCount);

  /// Sections where [SectionCompleteness.missingCount] is nonzero - the
  /// real, actionable output of this report. Empty on a healthy import.
  List<SectionCompleteness> get incompleteSections =>
      sections.where((s) => s.missingCount > 0).toList();

  /// The exact "Source / Imported / Missing" shape requested for this
  /// feature - a stable, human-readable summary suitable for a debug/QA
  /// screen or a test failure message, not just an internal data
  /// structure.
  String toReportString() {
    final buffer = StringBuffer();
    buffer.writeln('Source:');
    for (final s in sections) {
      buffer.writeln('  ${s.label} = ${s.sourceCount}');
    }
    buffer.writeln('Imported:');
    for (final s in sections) {
      buffer.writeln('  ${s.label} = ${s.importedCount}');
    }
    final flaggedTotal = sections.fold(0, (sum, s) => sum + s.flaggedForReviewCount);
    if (flaggedTotal > 0) {
      buffer.writeln('Flagged for manual review (not auto-structured, but not lost):');
      for (final s in sections.where((s) => s.flaggedForReviewCount > 0)) {
        buffer.writeln('  ${s.label} = ${s.flaggedForReviewCount}');
      }
    }
    buffer.writeln('Missing: $totalMissing');
    return buffer.toString();
  }
}

/// One category's source-vs-imported accounting (Experience, Education,
/// Projects, Certifications, Skills, Custom Sections, Links). See
/// [ResumeImportCompletenessReport]'s own doc comment for the invariant
/// this exists to check.
class SectionCompleteness {
  const SectionCompleteness({
    required this.label,
    required this.sourceCount,
    required this.importedCount,
    this.flaggedForReviewCount = 0,
  });

  final String label;

  /// How many distinct items the parser found for this category in the
  /// source text - a block of lines under a known section header
  /// (Experience/Education/Projects/Certifications), a detected custom
  /// section header, a deduplicated skill token, or a deduplicated URL
  /// match anywhere in the document.
  final int sourceCount;

  /// How many of those became a real structured entry the app can render
  /// (an `ExperienceBlock`, a `ResumeLink`, etc.).
  final int importedCount;

  /// How many of those the parser couldn't confidently structure but
  /// still preserved as raw text for manual review
  /// (`ParsedResumeDraft.unclassifiedText`/`warnings`) rather than
  /// dropping - not "missing" in the sense this report cares about, since
  /// the content is still there and visible to the user, just not
  /// auto-structured.
  final int flaggedForReviewCount;

  /// Source items accounted for by neither [importedCount] nor
  /// [flaggedForReviewCount] - genuinely, silently gone. Should always be
  /// `0`; [ResumeImportParser]'s own control flow is built so every block
  /// it identifies takes exactly one of those two paths, never neither -
  /// a positive value here means that invariant broke somewhere, a real
  /// parser bug worth its own regression test, not an expected outcome to
  /// design around.
  int get missingCount {
    final missing = sourceCount - importedCount - flaggedForReviewCount;
    return missing > 0 ? missing : 0;
  }
}
