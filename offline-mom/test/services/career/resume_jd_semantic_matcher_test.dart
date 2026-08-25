// Tests ResumeJdSemanticMatcher (lib/services/career/resume_jd_semantic_matcher.dart)
// directly, in isolation from ResumeJdAnalyzer - docs/v3/01-prd.md §25
// Milestone 2.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ai/embedding_engine.dart';
import 'package:offline_mom/services/career/resume_jd_semantic_matcher.dart';

import '../../test_helpers/fake_ai_engines.dart';

/// A local, hand-picked-vector embedding fake - see
/// resume_jd_analyzer_test.dart's identical fake for the full rationale
/// (this codebase's own "small, file-local fake when the shared fake
/// isn't precise enough" precedent). Kept file-local rather than shared,
/// since it's a small fixture-lookup with no behavior worth centralizing.
class _FixtureVectorEmbeddingEngine implements EmbeddingEngine {
  _FixtureVectorEmbeddingEngine(this._vectors);

  final Map<String, List<double>> _vectors;

  @override
  Future<List<double>> embed(String text, {bool normalize = true}) async => _vectorFor(text);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts, {bool normalize = true}) async {
    return texts.map(_vectorFor).toList();
  }

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {}

  List<double> _vectorFor(String text) {
    final vector = _vectors[text];
    if (vector == null) {
      throw StateError('_FixtureVectorEmbeddingEngine has no fixture vector registered for "$text"');
    }
    return vector;
  }
}

void main() {
  group('findBestMatch', () {
    test('returns null immediately for an empty candidate list, without calling the engine', () async {
      final matcher = ResumeJdSemanticMatcher(
        embeddingEngine: _FixtureVectorEmbeddingEngine(const {}),
      );

      final result = await matcher.findBestMatch('Kubernetes', const []);

      expect(result, isNull);
    });

    test('catches a genuine synonym with no shared word token, above the similarity threshold', () async {
      const requirement = 'Spreadsheet software proficiency';
      const candidate = 'Advanced Microsoft Excel skills';
      final matcher = ResumeJdSemanticMatcher(
        embeddingEngine: _FixtureVectorEmbeddingEngine({
          requirement: [1.0, 0.0],
          candidate: [0.95, 0.31],
        }),
      );

      final result = await matcher.findBestMatch(requirement, [candidate]);

      expect(result, candidate);
    });

    test('does not conflate two genuinely different technologies - a low-similarity candidate '
        'is never returned', () async {
      const requirement = 'Kubernetes';
      const candidate = 'Watercolor painting';
      final matcher = ResumeJdSemanticMatcher(
        embeddingEngine: _FixtureVectorEmbeddingEngine({
          requirement: [1.0, 0.0],
          candidate: [0.0, 1.0],
        }),
      );

      final result = await matcher.findBestMatch(requirement, [candidate]);

      expect(result, isNull);
    });

    test('among multiple candidates, returns the single most similar one, not just the first '
        'that clears the threshold', () async {
      const requirement = 'Container orchestration';
      const weakCandidate = 'Deployed applications';
      const strongCandidate = 'Managed Kubernetes clusters in production';
      final matcher = ResumeJdSemanticMatcher(
        embeddingEngine: _FixtureVectorEmbeddingEngine({
          requirement: [1.0, 0.0],
          weakCandidate: [0.65, 0.76],
          strongCandidate: [0.99, 0.14],
        }),
      );

      final result = await matcher.findBestMatch(requirement, [weakCandidate, strongCandidate]);

      expect(result, strongCandidate);
    });

    test('an embedding engine failure is caught and returns null, never propagated', () async {
      final matcher = ResumeJdSemanticMatcher(
        embeddingEngine: FakeEmbeddingEngine(errorToThrow: StateError('model not loaded')),
      );

      final result = await matcher.findBestMatch('Kubernetes', const ['Docker']);

      expect(result, isNull);
    });

    test('a candidate exactly at the default 0.6 similarity threshold is accepted (inclusive bound)', () async {
      const requirement = 'A';
      const candidate = 'B';
      // cos([1,0], [0.6, 0.8]) = 0.6 exactly.
      final matcher = ResumeJdSemanticMatcher(
        embeddingEngine: _FixtureVectorEmbeddingEngine({
          requirement: [1.0, 0.0],
          candidate: [0.6, 0.8],
        }),
      );

      final result = await matcher.findBestMatch(requirement, [candidate]);

      expect(result, candidate);
    });
  });
}
