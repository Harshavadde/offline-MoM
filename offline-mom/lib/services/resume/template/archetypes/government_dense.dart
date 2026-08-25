import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column, same section order as Classic Single-Column, paired
/// (via `../resume_template_catalog.dart`'s density profile) with the
/// tightest type sizes and spacing of any archetype - built for a long,
/// detailed, formally-structured chronological history, the shape most
/// government/public-sector applications expect (docs/v3/01-prd.md §8,
/// Milestone 4). No accent color anywhere, matching the plain,
/// unadorned convention of that context - `AtsConfidence.maximum`, single
/// column, no reading-order risk. Dispatched to by
/// [ResumeArchetypeIds.governmentDense] (`../resume_template_catalog.dart`)
/// via `ResumeTemplateRenderer`.
List<pw.Widget> buildGovernmentDensePages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  // Product composition-audit pass: this archetype's whole identity is a
  // complete, exhaustive chronological record, so it opts out of the
  // recency-weighted bullet cap every other archetype now applies to long
  // careers - see buildResumeContentPlan's own doc comment.
  final plan = buildResumeContentPlan(snapshot, capOlderExperienceBullets: false);
  return renderContentLines(plan.mainLines, tokens);
}
