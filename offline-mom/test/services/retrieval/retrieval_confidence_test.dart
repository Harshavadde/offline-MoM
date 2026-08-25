import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/retrieval/retrieval_confidence.dart';

void main() {
  group('RetrievalConfidenceScorer', () {
    const scorer = RetrievalConfidenceScorer();

    test('no candidates at all is always none, regardless of any score', () {
      expect(
        scorer.classify(anyCandidates: false, topCosineSimilarity: 0.99),
        RetrievalConfidence.none,
      );
    });

    test('candidates but no cosine value is none (defensive - should not happen in practice)', () {
      expect(scorer.classify(anyCandidates: true), RetrievalConfidence.none);
    });

    test('a strong match with keyword agreement is high', () {
      expect(
        scorer.classify(anyCandidates: true, topCosineSimilarity: 0.60, keywordAlsoMatched: true),
        RetrievalConfidence.high,
      );
    });

    test('a strong match without keyword agreement needs a higher bar to be high', () {
      // Just above the base high threshold but without keyword agreement -
      // not confident enough to skip the extra margin.
      expect(
        scorer.classify(anyCandidates: true, topCosineSimilarity: 0.60, keywordAlsoMatched: false),
        RetrievalConfidence.medium,
      );
      // Comfortably above the base threshold - high even without agreement.
      expect(
        scorer.classify(anyCandidates: true, topCosineSimilarity: 0.70, keywordAlsoMatched: false),
        RetrievalConfidence.high,
      );
    });

    test('a moderate match is medium', () {
      expect(
        scorer.classify(anyCandidates: true, topCosineSimilarity: 0.40),
        RetrievalConfidence.medium,
      );
    });

    test('a weak match is low', () {
      expect(
        scorer.classify(anyCandidates: true, topCosineSimilarity: 0.25),
        RetrievalConfidence.low,
      );
    });

    test('a negligible match is none', () {
      expect(
        scorer.classify(anyCandidates: true, topCosineSimilarity: 0.05),
        RetrievalConfidence.none,
      );
    });

    test('boundary values are inclusive at each threshold', () {
      expect(scorer.classify(anyCandidates: true, topCosineSimilarity: 0.35), RetrievalConfidence.medium);
      expect(scorer.classify(anyCandidates: true, topCosineSimilarity: 0.20), RetrievalConfidence.low);
    });

    test('custom thresholds are respected', () {
      const strict = RetrievalConfidenceScorer(highThreshold: 0.9, mediumThreshold: 0.7, lowThreshold: 0.5);
      expect(
        strict.classify(anyCandidates: true, topCosineSimilarity: 0.60),
        RetrievalConfidence.low,
      );
    });
  });
}
