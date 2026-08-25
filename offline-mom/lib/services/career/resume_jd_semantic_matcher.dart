import 'package:offline_mom/services/ai/embedding_engine.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';

/// Additive, opt-in semantic matching for JD requirements that
/// `ResumeJdAnalyzer`'s deterministic exact/alias/token-overlap matching
/// found nothing for (docs/v3/01-prd.md §25 Milestone 2). This is never the
/// trust anchor - it only ever gets a chance to run on a requirement the
/// deterministic pass already classified as [MatchLevel.missing], and a
/// hit here can only produce [MatchLevel.partial] with
/// [MatchSource.semanticEmbedding], never upgrade to exact and never
/// override a deterministic result.
///
/// Every public method is failure-tolerant by design: any exception thrown
/// by the underlying [EmbeddingEngine] (model not downloaded, load
/// failure, out of memory on a constrained device, etc.) is caught here
/// and turned into `null`, so a caller can always fall back to the
/// deterministic result without special-casing errors itself. This is the
/// concrete mechanism behind hard requirement 4: embeddings being
/// unavailable must never fail the analysis.
class ResumeJdSemanticMatcher {
  const ResumeJdSemanticMatcher({
    required EmbeddingEngine embeddingEngine,
    double similarityThreshold = 0.6,
  })  : _embeddingEngine = embeddingEngine,
        _similarityThreshold = similarityThreshold;

  final EmbeddingEngine _embeddingEngine;

  /// An engineering estimate, not a value derived from any labeled
  /// evaluation set - deliberately conservative (favors precision over
  /// recall) since a false semantic match is worse than a missed one: the
  /// deterministic tier already covers the confident cases, so this tier
  /// only needs to catch genuine synonyms without conflating unrelated
  /// technologies.
  final double _similarityThreshold;

  /// Compares [requirement] against every string in [candidates] (the
  /// resume's own text units - role/company/bullets/skill names/etc, the
  /// same evidence strings the deterministic matcher already works over)
  /// and returns the best-matching candidate whose cosine similarity meets
  /// [_similarityThreshold], or `null` if nothing clears the bar, the
  /// engine isn't ready, or any error occurs.
  Future<String?> findBestMatch(String requirement, List<String> candidates) async {
    if (candidates.isEmpty) return null;
    try {
      final requirementVector = await _embeddingEngine.embed(requirement);
      final candidateVectors = await _embeddingEngine.embedBatch(candidates);

      String? bestCandidate;
      var bestScore = _similarityThreshold;
      for (var i = 0; i < candidates.length; i++) {
        final score = BruteForceVectorStore.cosineSimilarity(requirementVector, candidateVectors[i]);
        if (score >= bestScore) {
          bestScore = score;
          bestCandidate = candidates[i];
        }
      }
      return bestCandidate;
    } catch (_) {
      return null;
    }
  }
}
