import 'package:pdf/widgets.dart' as pw;

import '../resume_design_tokens.dart';

/// A section heading (e.g. "Experience") - literal, plain text
/// (docs/v3/01-prd.md §9: standard section names must exist as real text
/// regardless of visual treatment). [ResumeDesignTokens.headingUsesAccentColor]
/// varies its color; [ResumeDesignTokens.sectionHeadingStyle] (Beta Template
/// Quality Pass) varies its size/letter-spacing when set to
/// [SectionHeadingStyle.label] - **never** its case or content: every
/// archetype renders the exact same string a [ResumeContentLine] of kind
/// [ResumeContentLineKind.sectionHeading] carries, never a decorated/
/// abbreviated/uppercased/iconified substitute for the underlying text
/// (an uppercased heading would change what a real PDF-text extractor
/// reads back, silently breaking the "Experience"/"Education"/etc. literal
/// match this project's own ATS verification checks against).
pw.Widget buildSectionHeading(String text, ResumeDesignTokens tokens) {
  final isLabelStyle = tokens.sectionHeadingStyle == SectionHeadingStyle.label;
  // Final visual-polish pass: a [ruleBelow] heading previously had no
  // letter-spacing at all, unlike [label]-style headings - reusing
  // [sectionRuleFollowsHeadingWidth] (already exclusive to Balanced
  // Two-Column, no new token) to add a small amount, refining the
  // heading's presence as a navigation anchor without changing its size
  // or introducing a new decorative element. Every other [ruleBelow]
  // archetype (Two-Column Sidebar) is unaffected.
  final rulesBelowWithSpacing =
      tokens.sectionHeadingStyle == SectionHeadingStyle.ruleBelow && tokens.sectionRuleFollowsHeadingWidth;
  return pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: isLabelStyle ? tokens.headingSize * 0.85 : tokens.headingSize,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: isLabelStyle ? 1.2 : (rulesBelowWithSpacing ? 0.6 : null),
      color: tokens.headingUsesAccentColor ? tokens.accentColor : tokens.inkColor,
    ),
  );
}
