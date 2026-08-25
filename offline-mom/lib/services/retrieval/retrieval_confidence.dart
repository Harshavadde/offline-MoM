/// How confident the Hybrid Retrieval Engine is that its top-ranked
/// result(s) actually answer the question (Phase 6B objective 10,
/// ADR-037) - drives whether `WorkspaceChatUseCase` answers from the
/// user's own content ([high]/[medium]) or falls back to the LLM's
/// general knowledge ([low]/[none]).
enum RetrievalConfidence { high, medium, low, none }

/// Buckets a real, recomputed cosine similarity (not a rank, not a BM25
/// value - see [HybridRanker]'s doc comment for why those aren't
/// comparable across queries/corpora) into a [RetrievalConfidence] band.
///
/// **These thresholds are disclosed, unvalidated heuristic starting
/// points**, not measured against real `embeddinggemma-300M` output
/// distributions - no device is available in this implementation
/// environment to gather that data (same standing disclosure as
/// R-04/R-18/R-19 for every other AI-adjacent numeric choice in this
/// project). They should be tuned against real query/answer pairs once
/// device testing is possible (tracked as a new risk, see the risk
/// register) rather than trusted as final.
class RetrievalConfidenceScorer {
  const RetrievalConfidenceScorer({
    this.highThreshold = 0.55,
    this.mediumThreshold = 0.35,
    this.lowThreshold = 0.20,
  });

  final double highThreshold;
  final double mediumThreshold;
  final double lowThreshold;

  /// [topCosineSimilarity] is the real cosine similarity (not RRF score)
  /// of the top fused result, recomputed cheaply against the already-
  /// computed query embedding. [keywordAlsoMatched] is
  /// [RankedChunk.bothMatched] for that same top result - independent
  /// agreement between the two retrieval signals raises confidence at a
  /// slightly lower cosine bar, since two different methods agreeing is
  /// itself real evidence.
  RetrievalConfidence classify({
    required bool anyCandidates,
    double? topCosineSimilarity,
    bool keywordAlsoMatched = false,
  }) {
    if (!anyCandidates || topCosineSimilarity == null) return RetrievalConfidence.none;
    if (topCosineSimilarity >= highThreshold &&
        (keywordAlsoMatched || topCosineSimilarity >= highThreshold + 0.10)) {
      return RetrievalConfidence.high;
    }
    if (topCosineSimilarity >= mediumThreshold) return RetrievalConfidence.medium;
    if (topCosineSimilarity >= lowThreshold) return RetrievalConfidence.low;
    return RetrievalConfidence.none;
  }
}
