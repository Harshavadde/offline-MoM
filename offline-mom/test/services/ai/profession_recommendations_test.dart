import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/profession_profile.dart';
import 'package:offline_mom/services/ai/model_catalog.dart';
import 'package:offline_mom/services/ai/profession_recommendations.dart';

void main() {
  group('ProfessionRecommendations', () {
    test('every ProfessionProfile has exactly one recommendation', () {
      for (final profession in ProfessionProfile.values) {
        final matches =
            ProfessionRecommendations.all.where((r) => r.profession == profession).toList();
        expect(matches.length, 1, reason: '$profession should have exactly one recommendation');
      }
    });

    test('every recommended model id resolves to a real catalog entry', () {
      for (final recommendation in ProfessionRecommendations.all) {
        expect(
          ModelCatalog.byId(recommendation.recommendedLlmModelId),
          isNotNull,
          reason: '${recommendation.profession} LLM recommendation',
        );
        expect(
          ModelCatalog.byId(recommendation.recommendedEmbeddingModelId),
          isNotNull,
          reason: '${recommendation.profession} embedding recommendation',
        );
        expect(
          ModelCatalog.byId(recommendation.recommendedWhisperModelId),
          isNotNull,
          reason: '${recommendation.profession} Whisper recommendation',
        );
      }
    });

    test('recommended Whisper tiers genuinely differ across professions (not fabricated)', () {
      final whisperIds =
          ProfessionRecommendations.all.map((r) => r.recommendedWhisperModelId).toSet();
      expect(whisperIds.length, greaterThan(1));
    });

    test('every recommendation has a non-empty rationale', () {
      for (final recommendation in ProfessionRecommendations.all) {
        expect(recommendation.rationale.trim(), isNotEmpty);
      }
    });

    test('forProfession returns the matching recommendation', () {
      final r = ProfessionRecommendations.forProfession(ProfessionProfile.researcher);
      expect(r.profession, ProfessionProfile.researcher);
      expect(r.recommendedWhisperModelId, ModelCatalog.whisperLargeV2.id);
    });
  });
}
