import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column with the boldest header treatment of any archetype - a
/// full color-band header (`HeaderStyle.colorBand`, set in this
/// archetype's catalog entry) paired with `headingUsesAccentColor: true`
/// catalog entries so every section heading also carries the accent color
/// - suits visual/design-adjacent roles wanting more personality on the
/// page (docs/v3/01-prd.md §8, Milestone 4; color-band header added in the
/// product visual-audit pass).
///
/// Still real, selectable `pw.Text`/`pw.Column` content in a single column
/// - no image, no table, no reading-order risk of its own - but the
/// heavier decorative treatment is disclosed via `AtsConfidence.high`
/// rather than `.maximum` in the catalog (mirrors Two-Column Sidebar's own
/// disclosed-caution precedent: more visual choices than the plainest
/// archetypes, not more actual reading-order risk). Dispatched to by
/// [ResumeArchetypeIds.creativeVisual] (`../resume_template_catalog.dart`)
/// via `ResumeTemplateRenderer`.
List<pw.Widget> buildCreativeVisualPages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  final plan = buildResumeContentPlan(snapshot);
  final bodyWidgets = renderContentLines(plan.mainLines, tokens);

  // Product visual-audit pass: the previous "accent rule above and below
  // the header" pair is now redundant - the header itself is already a
  // solid accent-filled block (`HeaderStyle.colorBand`), so this
  // archetype's distinguishing "boldest accent treatment" identity now
  // lives in the header, not two extra thin bars stacked against it.
  return bodyWidgets;
}
