import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/template/resume_design_tokens.dart';
import 'package:offline_mom/services/resume/template/resume_template_spec.dart';
import 'package:pdf/pdf.dart';

void main() {
  ResumeDesignTokens buildTokens() {
    return const ResumeDesignTokens(
      nameSize: 24,
      headingSize: 14,
      subheadingSize: 11,
      bodySize: 10,
      captionSize: 9,
      pageMargin: 32,
      sectionGap: 14,
      entryGap: 10,
      lineGap: 3,
      inkColor: PdfColors.black,
      inkSoftColor: PdfColors.grey600,
      accentColor: PdfColors.blue,
      dividerColor: PdfColors.grey300,
    );
  }

  test('id is derived from archetypeId and tokenPresetId', () {
    final spec = ResumeTemplateSpec(
      archetypeId: 'classic-single-column',
      tokenPresetId: 'warm',
      displayName: 'Classic - Warm',
      atsConfidence: AtsConfidence.maximum,
      density: TemplateDensity.low,
      candidateType: 'Conservative industries',
      tokens: buildTokens(),
    );

    expect(spec.id, 'classic-single-column-warm');
  });

  test('two specs with the same archetype but different presets have different ids', () {
    final warm = ResumeTemplateSpec(
      archetypeId: 'compact-technical',
      tokenPresetId: 'warm',
      displayName: 'Compact Technical - Warm',
      atsConfidence: AtsConfidence.maximum,
      density: TemplateDensity.high,
      candidateType: 'Technical roles',
      tokens: buildTokens(),
    );
    final cool = ResumeTemplateSpec(
      archetypeId: 'compact-technical',
      tokenPresetId: 'cool',
      displayName: 'Compact Technical - Cool',
      atsConfidence: AtsConfidence.maximum,
      density: TemplateDensity.high,
      candidateType: 'Technical roles',
      tokens: buildTokens(),
    );

    expect(warm.id, isNot(cool.id));
  });

  test('every AtsConfidence value is exposed and distinct', () {
    expect(AtsConfidence.values, [AtsConfidence.maximum, AtsConfidence.high, AtsConfidence.medium]);
  });

  test('every TemplateDensity value is exposed and distinct', () {
    expect(TemplateDensity.values, [TemplateDensity.low, TemplateDensity.medium, TemplateDensity.high]);
  });
}
