import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column, same section order as Classic Single-Column, with the
/// most restrained typographic treatment of any archetype - no accent
/// rule, no accent-colored headings (its catalog entries always set
/// `headingUsesAccentColor: false`), generous whitespace (docs/v3/01-prd.md
/// §8, Milestone 4). "Monochrome" describes the *character* of this
/// archetype's own layout (it never draws an accent-colored element,
/// unlike Modern Accent-Rule/Executive Summary-Led), not a separate color
/// system - `AtsConfidence.maximum`, still a single column, no reading-
/// order risk. Dispatched to by [ResumeArchetypeIds.minimalistMonochrome]
/// (`../resume_template_catalog.dart`) via `ResumeTemplateRenderer`.
List<pw.Widget> buildMinimalistMonochromePages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  final plan = buildResumeContentPlan(snapshot);
  return renderContentLines(plan.mainLines, tokens);
}
