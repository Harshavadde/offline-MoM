import '../career/resume_jd_analyzer.dart';

/// Result of running [SuggestionFabricationGuard.check] on one suggestion.
/// [isSafe] is false whenever [newNumbers] or [newProperNouns] is
/// non-empty - a *flag*, not a rejection (docs/v3/01-prd.md AC3-03/D-08):
/// the caller decides what to do with an unsafe result, this class only
/// reports what was found.
class FabricationCheckResult {
  const FabricationCheckResult({
    required this.isSafe,
    this.newNumbers = const [],
    this.newProperNouns = const [],
  });

  final bool isSafe;

  /// Numeric tokens (counts, percentages, years) present in the suggested
  /// text but absent, verbatim, from the grounding text.
  final List<String> newNumbers;

  /// Capitalized word-like tokens (candidate employers, technologies,
  /// certifications, place names, month names, ...) present in the
  /// suggested text but whose lowercased form doesn't appear anywhere in
  /// the grounding text.
  final List<String> newProperNouns;
}

/// Deterministic, offline post-check comparing a suggested rewrite against
/// the resume text it was grounded in (docs/v3/01-prd.md §22.3,
/// AC3-03/D-08) - the "SuggestionFabricationGuard" the architecture
/// diagram names. Runs after generation, entirely independent of the LLM:
/// this is what makes the fabrication check a real, testable application
/// boundary rather than only a prompt instruction the model might ignore.
///
/// **Disclosed limitation, not a guarantee** (matches AC3-03's own
/// wording): this is a lexical check, not a semantic one. It can miss a
/// genuine fabrication phrased using only words already present elsewhere
/// in the text (e.g. reusing "led" from one bullet to falsely claim
/// leadership in another), and it can flag legitimate rewording that
/// happens to introduce a synonym or a reformatted number
/// ("5 years" -> "five years") as new. It is a best-effort, defensible
/// heuristic - explicitly never a factual-correctness verifier - and its
/// result is surfaced to the user for their own judgment (flag, never
/// auto-reject), never used to silently discard a suggestion.
class SuggestionFabricationGuard {
  const SuggestionFabricationGuard();

  static final _numberPattern = RegExp(r'\d+(\.\d+)?%?\+?');

  /// A whole word-like token *starting with* an uppercase letter - letters
  /// plus the same in-token punctuation [normalizeResumeText] preserves
  /// (so "Node.js"/"C++"/"CI/CD"-shaped names survive as one token), at
  /// least 2 characters so a lone initial isn't flagged on its own.
  /// Anchored (`^...$`), not a bare `hasMatch`, so a token like
  /// "myKubernetes" (uppercase only mid-token) is correctly *not* treated
  /// as a proper-noun candidate.
  static final _properNounCandidatePattern = RegExp(r"^[A-Z][A-Za-z0-9+#./-]+$");

  static final _wordPattern = RegExp(r"[A-Za-z][A-Za-z0-9+#./-]*");

  /// Compares [suggestedText] against [originalText] plus
  /// [additionalGroundingText] (already-true resume facts the model was
  /// legitimately given as context - e.g. the entry's own role/company/
  /// institution - but that don't live in the specific field being
  /// rewritten, so mentioning them is not a fabrication).
  ///
  /// A capitalized token is only flagged from the *non-first* word of each
  /// suggested line: bullets conventionally start with a capitalized verb
  /// ("Built", "Led", "Managed"), which is a style choice, not evidence of
  /// a proper noun - flagging every line's first word would make this
  /// guard fire on nearly every suggestion regardless of content.
  FabricationCheckResult check({
    required String originalText,
    required String suggestedText,
    List<String> additionalGroundingText = const [],
  }) {
    final groundingText = ([originalText, ...additionalGroundingText]).join('\n');
    // Reuses ResumeJdAnalyzer's own normalization (lowercase, punctuation
    // stripped except in-token symbols, whitespace collapsed) rather than
    // a second, slightly-different definition of "what counts as a word"
    // for the same kind of text. Edge punctuation is stripped per-word
    // (via [_stripEdgePunctuation]) so a term that ends one sentence in
    // the grounding text (picking up a trailing ".") still matches the
    // same term appearing mid-sentence in the suggestion.
    final knownWords = normalizeResumeText(groundingText)
        .split(RegExp(r'\s+'))
        .map(_stripEdgePunctuation)
        .where((w) => w.isNotEmpty)
        .toSet();
    final knownNumbers = _numberPattern.allMatches(groundingText).map((m) => m.group(0)!).toSet();

    final newNumbers = _numberPattern
        .allMatches(suggestedText)
        .map((m) => m.group(0)!)
        .where((n) => !knownNumbers.contains(n))
        .toSet()
        .toList(growable: false);

    final newProperNouns = <String>{};
    for (final line in suggestedText.split('\n')) {
      final tokens = _wordPattern
          .allMatches(line)
          .map((m) => _stripEdgePunctuation(m.group(0)!))
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
      for (var i = 1; i < tokens.length; i++) {
        final token = tokens[i];
        if (!_properNounCandidatePattern.hasMatch(token)) continue;
        if (!knownWords.contains(token.toLowerCase())) {
          newProperNouns.add(token);
        }
      }
    }

    return FabricationCheckResult(
      isSafe: newNumbers.isEmpty && newProperNouns.isEmpty,
      newNumbers: newNumbers,
      newProperNouns: newProperNouns.toList(growable: false),
    );
  }

  /// Strips leading/trailing punctuation ([_wordPattern]'s in-token
  /// characters `./+#-`) from a single already-extracted token, so a term
  /// that happens to sit at a sentence boundary (picking up a trailing
  /// "." or a leading "-" from a bullet marker) still compares equal to
  /// the same term appearing mid-sentence elsewhere. Internal punctuation
  /// ("Node.js", "C++", "CI/CD") is untouched.
  String _stripEdgePunctuation(String token) {
    return token.replaceAll(RegExp(r'^[./+#-]+|[./+#-]+$'), '');
  }
}
