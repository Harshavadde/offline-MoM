import 'hybrid_ranker.dart';

/// Which of a fused, ranked chunk list actually fit the LLM's context
/// budget, and whether anything had to be left out.
class TokenBudgetSelection {
  const TokenBudgetSelection({required this.selected, required this.truncated});

  final List<RankedChunk> selected;

  /// True when at least one lower-ranked chunk didn't fit and was left out
  /// - surfaced in Retrieval Statistics (Phase 6B objective 13), not
  /// silently dropped.
  final bool truncated;
}

/// Picks a prefix of a ranked chunk list that fits a character budget,
/// **never cutting a chunk in half** (Phase 6B objective 8, "Token Budget
/// Optimization", ADR-037) - a real improvement over the previous
/// behavior, where `WorkspaceChatUseCase` concatenated every retrieved
/// chunk unconditionally and `LlamaDartLlmEngine` then blindly truncated
/// the *whole* resulting string at a fixed character count, which could
/// cut off mid-sentence and had no way to prefer a highly-relevant chunk
/// over a barely-relevant one that merely came first in the list.
///
/// Uses characters, not tokens, as the budget unit - the same "chars as a
/// token-count proxy" convention `DefaultChunkingService`/ADR-011 already
/// established for this codebase (no on-device tokenizer is available to
/// count real tokens without loading the LLM itself).
class TokenBudgetSelector {
  const TokenBudgetSelector({this.charBudget = 4000, this.perChunkOverheadChars = 60});

  /// Matches `LlamaDartLlmEngine._maxTranscriptChars` - keeping the two in
  /// the same rough range means this selector, not the engine's own blind
  /// tail-truncation, is normally what decides what's included; the
  /// engine's truncation becomes a rarely-triggered safety net instead of
  /// the primary mechanism.
  final int charBudget;

  /// A rough estimate of the `## <label>\n...\n\n` formatting overhead
  /// [ContextBuilder] adds per chunk, accounted for during selection so
  /// the *actually built* context doesn't quietly exceed [charBudget].
  final int perChunkOverheadChars;

  TokenBudgetSelection select(List<RankedChunk> ranked) {
    final selected = <RankedChunk>[];
    var used = 0;
    for (final rankedChunk in ranked) {
      final cost = rankedChunk.chunk.chunkText.length + perChunkOverheadChars;
      if (used + cost > charBudget && selected.isNotEmpty) {
        return TokenBudgetSelection(selected: selected, truncated: true);
      }
      selected.add(rankedChunk);
      used += cost;
    }
    return TokenBudgetSelection(selected: selected, truncated: false);
  }
}
