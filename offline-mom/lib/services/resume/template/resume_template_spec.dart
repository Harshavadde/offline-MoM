import 'resume_design_tokens.dart';

/// How confident this app is that a template's compiled PDF will parse
/// correctly through a real ATS (docs/v3/01-prd.md §9) - a disclosed,
/// honest bucket shown to the user at template-selection time, never
/// hidden and never overstated as a guarantee. Mirrors
/// `ModelSpeedTier`/`RecommendedDeviceTier`'s existing "coarse, honest
/// bucket, not a false-precision number" convention
/// (`lib/models/ai_model_spec.dart`).
enum AtsConfidence {
  /// Single-column, no tables, no multi-column reading-order risk.
  maximum,

  /// Multi-column or sidebar layout, verified for reading order by this
  /// template's own extraction round-trip test, but inherently less
  /// certain against real-world ATS variety than a single-column layout.
  high,

  /// Visual-first / denser layouts where reading-order or density trades
  /// against ATS certainty more than the other two tiers.
  medium,
}

/// How much content a template is designed to comfortably hold on one
/// page before flowing to a second.
enum TemplateDensity { low, medium, high }

/// One selectable template: an archetype (structural layout) paired with
/// one design-token preset (visual mood) - docs/v3/01-prd.md §8/§22.2's
/// "archetypes × token presets, not 20 independently coded documents."
/// [id] is the stable, persisted identifier (`resumes.template_id`/
/// `resume_versions.template_id`, migration v17) - derived from
/// [archetypeId]/[tokenPresetId] rather than a separately hand-maintained
/// field, so it can never drift out of sync with the pair it names.
class ResumeTemplateSpec {
  const ResumeTemplateSpec({
    required this.archetypeId,
    required this.tokenPresetId,
    required this.displayName,
    required this.atsConfidence,
    required this.density,
    required this.candidateType,
    required this.tokens,
    this.isEnabledInBeta = true,
  });

  /// Which structural layout renders this template - matches one of the
  /// archetype ids in `template/archetypes/` (e.g. `'classic-single-column'`).
  final String archetypeId;

  /// Which token preset supplies this template's typography/color mood
  /// (e.g. `'warm'`, `'cool'`).
  final String tokenPresetId;

  /// User-facing name shown in the template gallery, e.g. "Classic - Warm".
  final String displayName;

  final AtsConfidence atsConfidence;
  final TemplateDensity density;

  /// Short, human-readable description of who this template suits, e.g.
  /// "Conservative industries: finance, legal, government, academia."
  /// Shown in the gallery alongside [displayName] - free text, not an
  /// enum, since candidate framing is descriptive copy, not a filterable
  /// category.
  final String candidateType;

  /// The typography/spacing/color values this template renders with.
  final ResumeDesignTokens tokens;

  /// Whether this template is exposed in the beta template selection UI
  /// (`ResumeTemplateCatalog.enabled`). Defaults to `true`; the beta scope
  /// decision (docs/v3/implementation/03-decisions.md) narrows the 10
  /// archetypes down to 5 for the selection screen without deleting the
  /// other 5's implementation - a resume that already has one of the
  /// disabled ids persisted still resolves and renders correctly via
  /// [ResumeTemplateCatalog.specById]/[ResumeTemplateCatalog.all], which
  /// stay unfiltered.
  final bool isEnabledInBeta;

  /// Stable persisted identifier - `'$archetypeId-$tokenPresetId'`, e.g.
  /// `'classic-single-column-warm'`.
  String get id => '$archetypeId-$tokenPresetId';
}
