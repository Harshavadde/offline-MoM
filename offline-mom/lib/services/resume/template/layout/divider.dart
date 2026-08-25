import 'package:pdf/widgets.dart' as pw;

import '../resume_design_tokens.dart';

/// A thin horizontal rule in [ResumeDesignTokens.dividerColor] - purely
/// decorative (never the sole carrier of section boundaries; every
/// section is already introduced by its own heading text). Never placed
/// behind or through text (docs/v3/01-prd.md §9: no decorative elements
/// that interfere with parsing).
///
/// **Design-execution pass:** when [ResumeDesignTokens.sectionRuleUsesAccentColor]
/// is set, the rule renders in [ResumeDesignTokens.accentColor] at a
/// slightly heavier weight instead of the neutral [dividerColor] every
/// other archetype uses - a functional signal ("a new information group
/// starts here") rather than a decorative tint, reserved for the one
/// archetype this pass judged needed it.
pw.Widget buildDivider(ResumeDesignTokens tokens) {
  if (tokens.sectionRuleUsesAccentColor) {
    return pw.Container(height: 1.25, color: tokens.accentColor);
  }
  return pw.Container(height: 0.75, color: tokens.dividerColor);
}

/// A short horizontal rule, [width] wide, left-aligned - **approved design
/// specification pass**. Used under a section heading when
/// [ResumeDesignTokens.sectionRuleFollowsHeadingWidth] is set, so the rule
/// "hugs" the heading text instead of spanning the full column width (see
/// that token's own doc comment for why [width] is an approximation, not
/// an exact text measurement). Always renders in [ResumeDesignTokens
/// .accentColor] at [buildDivider]'s heavier accent weight - a short,
/// unaccented rule would read as an accidental fragment, not a deliberate
/// mark.
pw.Widget buildShortDivider(ResumeDesignTokens tokens, {required double width}) {
  return pw.Align(
    alignment: pw.Alignment.centerLeft,
    child: pw.SizedBox(width: width, child: pw.Container(height: 1.5, color: tokens.accentColor)),
  );
}

/// A thin *dashed* horizontal rule, used between consecutive entries
/// within one section when [ResumeDesignTokens.entryDividerDashed] is set
/// (reference-driven redesign pass) - a visually lighter organizational
/// cue than [buildDivider]'s solid rule, which remains reserved for
/// section boundaries. Built via `pw.Border.bottom`'s own dashed
/// `BorderStyle` rather than a custom-drawn pattern - `package:pdf`'s own
/// built-in mechanism, not a hand-rolled one.
pw.Widget buildDashedDivider(ResumeDesignTokens tokens) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: tokens.dividerColor, width: 0.75, style: pw.BorderStyle.dashed),
      ),
    ),
  );
}
