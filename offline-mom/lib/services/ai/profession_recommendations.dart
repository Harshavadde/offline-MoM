import '../../models/profession_profile.dart';
import 'model_catalog.dart';

/// The Phase 6A profession-based recommendation engine (ADR-036,
/// docs/v2/implementation/03-decisions.md; ADR-035 approved this direction
/// in principle).
///
/// **Honest scope, stated once here rather than repeated at every call
/// site:** every profession recommends the same LLM ([ModelCatalog
/// .llmQwen25_1_5b]) and the same embedding model ([ModelCatalog
/// .embeddingGemma300m]), because those are the catalog's only real tiers
/// today (see [ModelCatalog]'s doc comment) - there is nothing to
/// differentiate *between* yet for those two kinds. What genuinely differs
/// per profession is [ProfessionRecommendation.recommendedWhisperModelId],
/// since 6 real Whisper size tiers exist to choose between on real
/// accuracy/RAM/storage/speed trade-offs. This is a deliberately honest,
/// partial delivery of the ambitious "profession-based recommendations"
/// product ask - not a differentiated LLM/embedding recommendation
/// dressed up to look like one. Once a second LLM/embedding tier is
/// approved and built (ADR-035), this file is the one place that needs
/// updating to make those recommendations genuinely differ too.
class ProfessionRecommendations {
  ProfessionRecommendations._();

  static final List<ProfessionRecommendation> all = [
    ProfessionRecommendation(
      profession: ProfessionProfile.student,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperSmall.id,
      rationale:
          'Small balances accuracy for lecture-length recordings against the storage '
          'and battery budget of a typical student device.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.teacher,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperSmall.id,
      rationale:
          'Small keeps classroom/staff-meeting recordings accurate without the large '
          'storage footprint of Medium or Large across a full term of recordings.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.softwareEngineer,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperBase.id,
      rationale:
          'Base favors speed for short, frequent standups and design reviews, where '
          'turnaround matters more than maximum transcription accuracy.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.doctor,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperMedium.id,
      rationale:
          'Medium\'s higher accuracy matters for clinical terminology, at the cost of a '
          'larger download and more RAM - worth it when misheard terms carry real risk.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.lawyer,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperMedium.id,
      rationale:
          'Medium reduces transcription errors in depositions and client meetings where '
          'precise wording matters, accepting the larger storage/RAM cost for it.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.researcher,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperLargeV2.id,
      rationale:
          'Large (v2) gives the highest transcription accuracy for interview transcripts '
          'that may be quoted verbatim - the largest download and slowest tier, accepted '
          'here because citation accuracy outweighs speed.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.writer,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperSmall.id,
      rationale:
          'Small is accurate enough for voice-memo drafts and interview notes without '
          'committing to Medium/Large\'s storage cost for early-stage material.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.businessProfessional,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperBase.id,
      rationale:
          'Base keeps quick meeting/call notes fast and storage-light - the common case '
          'for frequent, shorter recordings rather than long-form content.',
    ),
    ProfessionRecommendation(
      profession: ProfessionProfile.generalUser,
      recommendedLlmModelId: ModelCatalog.llmQwen25_1_5b.id,
      recommendedEmbeddingModelId: ModelCatalog.embeddingGemma300m.id,
      recommendedWhisperModelId: ModelCatalog.whisperTiny.id,
      rationale:
          'Tiny is the fastest, smallest option - a reasonable default for casual use '
          'where minimizing download size and device resources matters most.',
    ),
  ];

  static ProfessionRecommendation forProfession(ProfessionProfile profession) =>
      all.firstWhere((r) => r.profession == profession);
}
