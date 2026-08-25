import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column with Education promoted to lead, directly under the
/// header, before Experience - suits a recent graduate or student whose
/// degree is typically more relevant than a thin or nonexistent work
/// history (docs/v3/01-prd.md §8, Milestone 4, §3 "Student / recent
/// graduate" persona). Otherwise structurally identical to Classic
/// Single-Column - `AtsConfidence.maximum`, single column, no reading-order
/// risk. Dispatched to by [ResumeArchetypeIds.entryLevelStudent]
/// (`../resume_template_catalog.dart`) via `ResumeTemplateRenderer`.
List<pw.Widget> buildEntryLevelStudentPages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  final plan = buildResumeContentPlan(snapshot, educationBeforeExperience: true);
  return renderContentLines(plan.mainLines, tokens);
}
