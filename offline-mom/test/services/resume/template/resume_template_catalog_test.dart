import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';
import 'package:offline_mom/services/resume/template/resume_template_spec.dart';

/// Beta scope (post-Milestone 4, docs/v3/implementation/03-decisions.md):
/// the catalog ships 10 genuinely distinct archetypes, one curated preset
/// each - not 10 archetypes x 2 presets. A warm/cool color swap is not a
/// second template, so it is deliberately not multiplied into the count
/// here.
void main() {
  test('the catalog has exactly 10 templates - one curated preset per archetype (beta scope, '
      'docs/v3/implementation/03-decisions.md)', () {
    expect(ResumeTemplateCatalog.all, hasLength(10));
  });

  test('every template has a unique id', () {
    final ids = ResumeTemplateCatalog.all.map((s) => s.id).toSet();
    expect(ids, hasLength(10));
  });

  test('all 10 archetypes are present, each exactly once', () {
    final counts = <String, int>{};
    for (final spec in ResumeTemplateCatalog.all) {
      counts[spec.archetypeId] = (counts[spec.archetypeId] ?? 0) + 1;
    }
    expect(counts, {
      ResumeArchetypeIds.classicSingleColumn: 1,
      ResumeArchetypeIds.modernAccentColumn: 1,
      ResumeArchetypeIds.twoColumnSidebar: 1,
      ResumeArchetypeIds.compactTechnical: 1,
      ResumeArchetypeIds.executiveSummaryLed: 1,
      ResumeArchetypeIds.creativeVisual: 1,
      ResumeArchetypeIds.entryLevelStudent: 1,
      ResumeArchetypeIds.minimalistMonochrome: 1,
      ResumeArchetypeIds.governmentDense: 1,
      ResumeArchetypeIds.twoColumnRight: 1,
    });
  });

  test('every archetype has exactly one of the two token presets - never both, never neither', () {
    for (final spec in ResumeTemplateCatalog.all) {
      expect(
        [ResumeTokenPresetIds.warm, ResumeTokenPresetIds.cool],
        contains(spec.tokenPresetId),
        reason: spec.id,
      );
    }
  });

  test('every template has a non-empty displayName and candidateType', () {
    for (final spec in ResumeTemplateCatalog.all) {
      expect(spec.displayName, isNotEmpty, reason: spec.id);
      expect(spec.candidateType, isNotEmpty, reason: spec.id);
    }
  });

  test('no displayName carries a leftover "- Warm"/"- Cool" suffix - beta ships one preset per '
      'archetype, so a preset suffix would misleadingly imply a choice that no longer exists',
      () {
    for (final spec in ResumeTemplateCatalog.all) {
      expect(spec.displayName, isNot(contains('Warm')), reason: spec.id);
      expect(spec.displayName, isNot(contains('Cool')), reason: spec.id);
    }
  });

  test(
    'executive-summary-led sets skillsGroupedByCategory (D-M9-02, product-quality remediation '
    'pass Part C) - regression test for a real bug found by direct visual PDF inspection: setting '
    'only buildResumeContentPlan(groupSkillsByCategory: true) in the archetype file had zero '
    'visual effect, since content_line_renderer.dart\'s paragraph case checks this token '
    'separately before rendering the labeled-group treatment',
    () {
      final specs = ResumeTemplateCatalog.all.where((s) => s.archetypeId == ResumeArchetypeIds.executiveSummaryLed);
      expect(specs, hasLength(1));
      expect(specs.single.tokens.skillsGroupedByCategory, isTrue);
    },
  );

  test('every template respects the 9pt body-size floor (docs/v3/01-prd.md §8)', () {
    for (final spec in ResumeTemplateCatalog.all) {
      expect(spec.tokens.bodySize, greaterThanOrEqualTo(9), reason: spec.id);
    }
  });

  test('the two structurally two-column archetypes (two-column-sidebar, two-column-right) are '
      'rated High, not Maximum, ATS confidence', () {
    final specs = ResumeTemplateCatalog.all.where(
      (s) => s.archetypeId == ResumeArchetypeIds.twoColumnSidebar || s.archetypeId == ResumeArchetypeIds.twoColumnRight,
    );
    expect(specs, hasLength(2));
    for (final spec in specs) {
      expect(spec.atsConfidence, AtsConfidence.high, reason: spec.id);
    }
  });

  test('creative-visual is rated High, not Maximum, ATS confidence (heavier decorative '
      'treatment disclosed, not more actual reading-order risk)', () {
    final specs = ResumeTemplateCatalog.all.where((s) => s.archetypeId == ResumeArchetypeIds.creativeVisual);
    expect(specs, hasLength(1));
    for (final spec in specs) {
      expect(spec.atsConfidence, AtsConfidence.high, reason: spec.id);
    }
  });

  test('every plain single-column archetype is rated Maximum ATS confidence', () {
    final singleColumnArchetypes = [
      ResumeArchetypeIds.classicSingleColumn,
      ResumeArchetypeIds.modernAccentColumn,
      ResumeArchetypeIds.compactTechnical,
      ResumeArchetypeIds.executiveSummaryLed,
      ResumeArchetypeIds.entryLevelStudent,
      ResumeArchetypeIds.minimalistMonochrome,
      ResumeArchetypeIds.governmentDense,
    ];
    final specs = ResumeTemplateCatalog.all.where((s) => singleColumnArchetypes.contains(s.archetypeId));
    expect(specs, hasLength(7));
    for (final spec in specs) {
      expect(spec.atsConfidence, AtsConfidence.maximum, reason: spec.id);
    }
  });

  test('defaultSpec is Classic Single-Column - Warm (docs/v3/01-prd.md §25)', () {
    expect(ResumeTemplateCatalog.defaultSpec.archetypeId, ResumeArchetypeIds.classicSingleColumn);
    expect(ResumeTemplateCatalog.defaultSpec.tokenPresetId, ResumeTokenPresetIds.warm);
  });

  group('specById', () {
    test('returns the matching spec for a known id', () {
      final spec = ResumeTemplateCatalog.specById('compact-technical-cool');
      expect(spec.archetypeId, ResumeArchetypeIds.compactTechnical);
      expect(spec.tokenPresetId, ResumeTokenPresetIds.cool);
    });

    test('returns defaultSpec for null (a resume with no template chosen yet)', () {
      expect(ResumeTemplateCatalog.specById(null).id, ResumeTemplateCatalog.defaultSpec.id);
    });

    test('returns defaultSpec for an unrecognized id, never throws', () {
      expect(
        () => ResumeTemplateCatalog.specById('not-a-real-template-id'),
        returnsNormally,
      );
      expect(
        ResumeTemplateCatalog.specById('not-a-real-template-id').id,
        ResumeTemplateCatalog.defaultSpec.id,
      );
    });

    test('returns defaultSpec for a pre-beta-scope id whose archetype now ships a different '
        'preset (e.g. an old "modern-accent-column-warm" resume, now cool-only) - a retired '
        'combination degrades safely rather than throwing', () {
      expect(
        ResumeTemplateCatalog.specById('modern-accent-column-warm').id,
        ResumeTemplateCatalog.defaultSpec.id,
      );
    });
  });
}
