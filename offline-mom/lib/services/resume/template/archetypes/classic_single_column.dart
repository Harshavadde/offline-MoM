import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column, strict reverse-chronological, generous whitespace,
/// minimal color - the maximum-ATS-safety archetype (see
/// docs/v3/implementation/01-master-roadmap.md's Milestone 1 entry).
/// Suits conservative industries and any heavily ATS-gated pipeline.
/// Dispatched to by [ResumeArchetypeIds.classicSingleColumn]
/// (`../resume_template_catalog.dart`) via `ResumeTemplateRenderer`.
List<pw.Widget> buildClassicSingleColumnPages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  final plan = buildResumeContentPlan(snapshot);
  return renderContentLines(plan.mainLines, tokens);
}
