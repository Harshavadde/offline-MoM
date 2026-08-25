import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/template/resume_design_tokens.dart';
import 'package:pdf/pdf.dart';

void main() {
  ResumeDesignTokens build({double bodySize = 10}) {
    return ResumeDesignTokens(
      nameSize: 24,
      headingSize: 14,
      subheadingSize: 11,
      bodySize: bodySize,
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

  test('constructs successfully with a body size at the 9pt floor', () {
    expect(() => build(bodySize: 9), returnsNormally);
  });

  test('constructs successfully with a body size above the floor', () {
    expect(() => build(bodySize: 12), returnsNormally);
  });

  test('asserts when body size is below the 9pt-equivalent floor (docs/v3/01-prd.md §8)', () {
    expect(() => build(bodySize: 8.9), throwsA(isA<AssertionError>()));
  });

  test('headingUsesAccentColor defaults to false', () {
    expect(build().headingUsesAccentColor, isFalse);
  });

  test('headingUsesAccentColor can be set explicitly', () {
    const tokens = ResumeDesignTokens(
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
      headingUsesAccentColor: true,
    );
    expect(tokens.headingUsesAccentColor, isTrue);
  });
}
