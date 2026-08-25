/// Which specific check produced a [WritingHint] - lets a caller style or
/// filter hints by kind without parsing [WritingHint.message] text.
enum WritingHintKind { weakVerb, noMeasurableDetail }

/// One deterministic, always-available writing suggestion for a single
/// resume bullet (docs/v3/01-prd.md §12, Tier 1) - never auto-inserted
/// into any field; purely advisory text a UI may choose to display next
/// to the field the user is editing.
class WritingHint {
  const WritingHint({required this.kind, required this.message});

  final WritingHintKind kind;
  final String message;
}

/// Deterministic, offline, no-model-required writing-quality checks for one
/// resume bullet line at a time (docs/v3/01-prd.md §12: "Tier 1 -
/// deterministic - weak-verb detection, 'consider adding a measurable
/// detail' prompts, never auto-inserted - requires no model and is always
/// available"). This is the always-on half of `BulletSuggestionField`'s two
/// tiers - Tier 2 (model-backed rewrite) is a separate, explicit,
/// user-triggered action layered on top, never a replacement for this.
///
/// Deliberately a small, explicit, disclosed set of checks - the same
/// "no giant speculative dictionary" discipline `ResumeJdAnalyzer`'s own
/// alias table already follows, not an attempt at exhaustive style
/// linting.
class ResumeWritingHeuristics {
  const ResumeWritingHeuristics();

  /// Weak/passive openers that read as vague rather than as an owned
  /// accomplishment - each one is a genuine, common resume-writing
  /// weakness, not a broad grammatical rule (e.g. "worked on" and "helped
  /// with" bury the writer's actual contribution; a genuinely strong verb
  /// like "Built"/"Led"/"Designed" states it directly).
  static const _weakOpeners = [
    'helped',
    'worked on',
    'worked with',
    'responsible for',
    'assisted with',
    'assisted in',
    'involved in',
    'participated in',
    'was tasked with',
    'in charge of',
    'duties included',
  ];

  static final _measurableDetailPattern = RegExp(r'\d');

  /// Returns every hint that applies to [bulletText] - empty if the text
  /// has no detected weaknesses. Purely advisory: the caller decides
  /// whether/how to display these, and nothing here ever modifies
  /// [bulletText] itself.
  List<WritingHint> analyze(String bulletText) {
    final trimmed = bulletText.trim();
    if (trimmed.isEmpty) return const [];

    final hints = <WritingHint>[];

    final lower = trimmed.toLowerCase();
    for (final opener in _weakOpeners) {
      if (lower.startsWith(opener)) {
        hints.add(
          WritingHint(
            kind: WritingHintKind.weakVerb,
            message: 'Consider starting with a stronger action verb instead of "$opener" - '
                'e.g. "Built", "Led", "Designed", "Reduced".',
          ),
        );
        break;
      }
    }

    if (!_measurableDetailPattern.hasMatch(trimmed)) {
      hints.add(
        const WritingHint(
          kind: WritingHintKind.noMeasurableDetail,
          message: 'Consider adding a measurable detail - a number, percentage, or count - '
              'if one honestly applies.',
        ),
      );
    }

    return hints;
  }
}
