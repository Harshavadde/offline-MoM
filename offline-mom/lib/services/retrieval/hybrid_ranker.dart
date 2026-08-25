import 'dart:math' as math;

import '../../models/knowledge_chunk.dart';
import 'scored_chunk.dart';

/// One [KnowledgeChunk] after fusion - carries enough provenance to explain
/// *why* it ranked where it did (Retrieval Statistics, Phase 6B objective
/// 13), not just the final number.
class RankedChunk {
  const RankedChunk({
    required this.chunk,
    required this.fusedScore,
    required this.matchedVector,
    required this.matchedKeyword,
  });

  final KnowledgeChunk chunk;
  final double fusedScore;

  /// Whether this chunk appeared in the vector-retrieval candidate list.
  final bool matchedVector;

  /// Whether this chunk appeared in the keyword-retrieval candidate list.
  final bool matchedKeyword;

  /// True when both retrieval paths independently agreed this chunk was
  /// relevant - a real, useful confidence signal
  /// ([RetrievalConfidence.classify] uses it), not just a display detail.
  bool get bothMatched => matchedVector && matchedKeyword;
}

/// Fuses vector-retrieval and keyword-retrieval result lists into one
/// ranked, deduplicated list (Phase 6B objectives 5 "Intelligent Result
/// Ranking" and 7 "Duplicate Chunk Removal", ADR-037).
///
/// **Fusion method: Reciprocal Rank Fusion (RRF)**, a well-established,
/// scale-invariant rank-fusion technique (Cormack et al. 2009; used in
/// production hybrid-search systems including Elasticsearch's and Azure AI
/// Search's own hybrid retrieval) - deliberately chosen over combining raw
/// scores directly. Cosine similarity (roughly [0,1] for normalized
/// embeddings) and BM25 (corpus-dependent, unbounded) are not
/// commensurable numbers; any raw-score-weighted-sum fusion would need
/// invented normalization constants this project has no real data to
/// validate (the same category of "don't fabricate a number you can't
/// justify" discipline ADR-011 already established for chunk-size
/// estimation). RRF sidesteps the problem entirely by fusing on *rank
/// position*, not score magnitude - a chunk ranked #1 by either signal
/// contributes the same regardless of how "confident" that signal's raw
/// score happened to be.
///
/// Recency is layered on top as a small, capped multiplicative boost -
/// deliberately *not* a third RRF-fused ranked list, since recency should
/// break ties among similarly-relevant chunks, not let an old-but-highly-
/// relevant chunk lose to a new-but-barely-relevant one.
class HybridRanker {
  const HybridRanker({
    this.rrfK = 60,
    this.recencyHalfLifeDays = 30,
    this.maxRecencyBoost = 0.10,
  });

  /// The RRF smoothing constant - 60 is the value the original RRF paper
  /// (Cormack, Clarke & Buettcher, 2009) evaluated and the value most
  /// production hybrid-search implementations default to; not re-derived
  /// or tuned against this app's own corpus (no real corpus available in
  /// this implementation environment to tune against - disclosed as an
  /// unvalidated-but-standard starting point, the same honesty this
  /// project applies to every other AI-adjacent numeric choice, e.g.
  /// ADR-011's chunk-size estimate).
  final int rrfK;

  /// How many days for the recency boost to decay to roughly a third of
  /// its maximum - an unvalidated starting point (see [rrfK]'s identical
  /// disclosure).
  final int recencyHalfLifeDays;

  /// The recency boost is capped at this fraction (10% by default) of the
  /// fused RRF score, so a very recent but marginally-relevant chunk can
  /// never outrank a highly-relevant older one - recency breaks ties, it
  /// doesn't override relevance.
  final double maxRecencyBoost;

  /// Fuses [vectorRanked] (already ordered best-first by
  /// [RetrievalEngine.retrieve]) and [keywordRanked] (already ordered
  /// best-first by [KeywordSearchService.search]) into one ranked,
  /// deduplicated-by-id list, descending by [RankedChunk.fusedScore].
  List<RankedChunk> fuse({
    required List<KnowledgeChunk> vectorRanked,
    required List<ScoredChunk> keywordRanked,
    DateTime? now,
  }) {
    final rrfScores = <int, double>{};
    final chunksById = <int, KnowledgeChunk>{};
    final matchedVector = <int>{};
    final matchedKeyword = <int>{};

    void accumulate(int id, KnowledgeChunk chunk, int rank) {
      rrfScores[id] = (rrfScores[id] ?? 0) + 1.0 / (rrfK + rank + 1);
      chunksById[id] = chunk;
    }

    for (var i = 0; i < vectorRanked.length; i++) {
      final chunk = vectorRanked[i];
      final id = chunk.id;
      if (id == null) continue; // an unpersisted chunk can't be cited/deduped by id
      accumulate(id, chunk, i);
      matchedVector.add(id);
    }
    for (var i = 0; i < keywordRanked.length; i++) {
      final chunk = keywordRanked[i].chunk;
      final id = chunk.id;
      if (id == null) continue;
      accumulate(id, chunk, i);
      matchedKeyword.add(id);
    }

    // A flat percentage-of-own-score boost is *not* actually bounded by
    // rank position: RRF's score gap between adjacent ranks shrinks as
    // rrfK grows (e.g. ~1.6% per rank at rrfK=60), so a naive "+10% of my
    // own score" boost can easily leapfrog several ranks. To honor this
    // class's own invariant (recency breaks ties, never overrides
    // relevance), the boost actually applied is capped to strictly less
    // than half the smallest gap between any two distinct RRF scores in
    // *this* candidate set - so it can never flip the order between two
    // chunks whose base relevance genuinely differs, no matter how old or
    // new either one is. Only chunks with equal (or near-equal) base scores
    // - genuine ties - can have their order decided by recency.
    final sortedScores = rrfScores.values.toList()..sort();
    var minGap = double.infinity;
    for (var i = 1; i < sortedScores.length; i++) {
      final gap = sortedScores[i] - sortedScores[i - 1];
      if (gap > 1e-12 && gap < minGap) minGap = gap;
    }
    final boostBudget = minGap.isFinite ? minGap / 2 : 1e-6;

    final nowTime = now ?? DateTime.now();
    final ranked = rrfScores.entries.map((entry) {
      final chunk = chunksById[entry.key]!;
      final ageDays = nowTime.difference(chunk.createdAt).inHours / 24.0;
      final recencyFactor = math.exp(-math.max(0, ageDays) / recencyHalfLifeDays);
      final boost = math.min(maxRecencyBoost * entry.value, boostBudget) * recencyFactor;
      final boostedScore = entry.value + boost;
      return RankedChunk(
        chunk: chunk,
        fusedScore: boostedScore,
        matchedVector: matchedVector.contains(entry.key),
        matchedKeyword: matchedKeyword.contains(entry.key),
      );
    }).toList()
      ..sort((a, b) => b.fusedScore.compareTo(a.fusedScore));

    return ranked;
  }
}
