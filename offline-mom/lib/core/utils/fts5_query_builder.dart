/// Turns free-form user input into a safe SQLite FTS5 `MATCH` query: each
/// alphanumeric token becomes a prefix match (`word*`), space-separated
/// (FTS5's default implicit AND between terms). Extracted (V2 Phase 6B,
/// ADR-037) from `SqfliteContentSearchRepository._buildMatchQuery`'s
/// original, identical implementation, which itself already mirrored
/// `AskAboutMeetingsUseCase`'s own tokenization convention - now the one
/// place both that repository and the new chunk-level
/// `SqfliteKeywordSearchService` share it from, rather than a second,
/// silently-driftable copy of the same regex.
///
/// Returns `null` when [rawQuery] contains no word/number tokens at all
/// (e.g. empty, or pure punctuation) - callers should treat that as "no
/// query", not run an empty/invalid `MATCH`.
///
/// Splits on Unicode letter/number/mark boundaries (`\p{L}`/`\p{N}`/`\p{M}`),
/// not just ASCII `a-z0-9` - the FTS5 tables this feeds (`content_fts`,
/// `knowledge_chunks_fts`) use SQLite's default `unicode61` tokenizer,
/// which already indexes non-Latin scripts (Devanagari, Tamil, etc.)
/// correctly on the content side; an ASCII-only query-side regex would
/// silently strip every character of a non-Latin query to nothing,
/// making search unusable for exactly the Indian-language content this
/// app's own onboarding advertises. `\p{M}` (combining marks) is included
/// alongside `\p{L}`/`\p{N}` deliberately, not just those two - many Indic
/// scripts attach dependent vowel signs/virama as combining marks
/// (Unicode category M, not L), which a letters-and-numbers-only class
/// would treat as token separators, incorrectly splitting one real word
/// (e.g. "समीक्षा") into several meaningless fragments. Caught by this
/// file's own regression test before it could reach production.
String? buildFts5MatchQuery(String rawQuery) {
  final tokens = rawQuery
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true))
      .where((t) => t.isNotEmpty)
      .map((t) => '$t*')
      .toList();
  if (tokens.isEmpty) return null;
  return tokens.join(' ');
}
