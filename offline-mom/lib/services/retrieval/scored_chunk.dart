import '../../models/knowledge_chunk.dart';

/// A [KnowledgeChunk] paired with a relevance score from whichever
/// retrieval stage produced it - shared between [KeywordSearchService]
/// (a sign-corrected BM25 value) and [HybridRetrievalPipeline]'s own
/// confidence-scoring step (a recomputed cosine similarity), so both
/// stages return data shaped the same way into [HybridRanker].
///
/// **Not a universal cross-stage-comparable score** - a BM25-derived 5.2
/// and a cosine-similarity 0.52 are not the same kind of number and must
/// never be compared directly; [HybridRanker] fuses by *rank* (Reciprocal
/// Rank Fusion), not by combining these raw values, precisely so this
/// type never needs to pretend otherwise. See [HybridRanker]'s doc
/// comment for why.
class ScoredChunk {
  const ScoredChunk({required this.chunk, required this.score});

  final KnowledgeChunk chunk;
  final double score;
}
