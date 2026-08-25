import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column, same section order as Classic Single-Column, but paired
/// (via `../resume_template_catalog.dart`'s density profile) with smaller
/// type sizes and tighter section/entry/line spacing - built to hold a
/// long technical project/skill history on one page before flowing to a
/// clean second page, rather than by reordering or omitting any content.
/// Suits technical/engineering roles specifically. `AtsConfidence.maximum`
/// - still a single column, no reading-order risk of its own.
List<pw.Widget> buildCompactTechnicalPages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  final plan = buildResumeContentPlan(snapshot);
  return renderContentLines(plan.mainLines, tokens);
}
