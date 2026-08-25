import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column with a colored header treatment and accent-colored
/// section headings ([ResumeDesignTokens.headingUsesAccentColor], set for
/// this archetype's catalog entries) - a modern feel without any
/// reading-order or column-structure risk (still `AtsConfidence.maximum`:
/// the accent is decorative color only, never a second column). Suits
/// general corporate/professional roles wanting polish without visual
/// risk. Dispatched to by `ResumeArchetypeIds.modernAccentColumn`
/// (`../resume_template_catalog.dart`) via `ResumeTemplateRenderer`.
List<pw.Widget> buildModernAccentColumnPages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  // Product Phase 3 (real information-architecture differentiation): a
  // real "modern professional" ordering that foregrounds concrete project
  // execution ahead of Education/Skills, rather than sharing Classic's
  // identical Experience → Education → Skills → Projects flow and
  // differing only by color/header treatment - this archetype's own
  // reason to exist beyond a palette swap.
  final plan = buildResumeContentPlan(snapshot, projectsBeforeEducation: true);
  final bodyWidgets = renderContentLines(plan.mainLines, tokens);

  // Product visual-audit pass: this archetype's catalog entry now sets
  // `headerStyle: HeaderStyle.colorBand`, so the header itself
  // (`renderContentLines`'s first emitted widget) already is a solid
  // accent-filled block - drawing the previous thin accent rule directly
  // beneath it would double up the same accent as two separate visual
  // elements stacked back-to-back. This structural difference from
  // Classic Single-Column is now the color-band header itself; no extra
  // rule is added.
  return bodyWidgets;
}
