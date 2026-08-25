/// The 9 profession profiles Phase 6A's recommendation engine supports
/// (product requirement, ADR-036) - stored as `AppSettings.professionProfile`
/// (the `.name` string, `null` = not yet chosen). Deliberately a closed
/// enum, not free text: every value must have a matching entry in
/// `ProfessionRecommendations.all` (validated in
/// `test/services/ai/profession_recommendations_test.dart`), which a
/// free-text profession could never guarantee.
enum ProfessionProfile {
  student,
  teacher,
  softwareEngineer,
  doctor,
  lawyer,
  researcher,
  writer,
  businessProfessional,
  generalUser,
}

extension ProfessionProfileLabel on ProfessionProfile {
  /// Display label for the profession picker - kept here (not duplicated
  /// in the widget layer) so the recommendation engine and the UI can
  /// never drift on what a profession is called, the same
  /// single-source-of-truth reasoning `ToolkitToolTypeIcons` already
  /// applies to `ToolkitToolType`.
  String get label => switch (this) {
        ProfessionProfile.student => 'Student',
        ProfessionProfile.teacher => 'Teacher',
        ProfessionProfile.softwareEngineer => 'Software Engineer',
        ProfessionProfile.doctor => 'Doctor',
        ProfessionProfile.lawyer => 'Lawyer',
        ProfessionProfile.researcher => 'Researcher',
        ProfessionProfile.writer => 'Writer',
        ProfessionProfile.businessProfessional => 'Business Professional',
        ProfessionProfile.generalUser => 'General User',
      };
}

/// One profession's recommended model set - see
/// `ProfessionRecommendations.all` for the actual per-profession data and
/// ADR-036 for why, today, only [recommendedWhisperModelId] genuinely
/// differs between professions (6 real Whisper size tiers exist to
/// recommend between; the catalog has only one real tier each for LLM and
/// embedding today - see [AiModelSpec]'s doc comment).
class ProfessionRecommendation {
  const ProfessionRecommendation({
    required this.profession,
    required this.recommendedLlmModelId,
    required this.recommendedEmbeddingModelId,
    required this.recommendedWhisperModelId,
    required this.rationale,
  });

  final ProfessionProfile profession;
  final String recommendedLlmModelId;
  final String recommendedEmbeddingModelId;
  final String recommendedWhisperModelId;

  /// One or two honest sentences explaining *why* this profession gets
  /// this Whisper tier specifically (accuracy/RAM/storage/speed trade-off),
  /// shown on the Profession Setup screen - never a generic "recommended
  /// for you" with no reasoning, matching this project's "explain trade-offs,
  /// don't just assert them" documentation ethos extended into product copy.
  final String rationale;
}
