import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Single column with Skills promoted to lead, directly under the header,
/// before Experience/Education - suits a candidate who wants their core
/// competencies read first (docs/v3/01-prd.md §8, Milestone 4). Otherwise
/// structurally identical to Modern Accent-Rule (same accent-rule-under-header
/// treatment, `AtsConfidence.maximum` - still a single column, no reading-
/// order risk). Dispatched to by [ResumeArchetypeIds.executiveSummaryLed]
/// (`../resume_template_catalog.dart`) via `ResumeTemplateRenderer`.
List<pw.Widget> buildExecutiveSummaryLedPages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  // Product Phase 3 (real information-architecture differentiation): a
  // "prominent professional summary" only actually reads as prominent if
  // it renders with more visual weight than an ordinary paragraph, not
  // merely by being positioned first - emphasizeSummary gives it a real
  // callout treatment (content_line_renderer.dart's emphasized branch),
  // on top of the existing skillsBeforeExperience reorder.
  //
  // Product-quality remediation pass, Part C: groupSkillsByCategory (D-M9-02)
  // - already implemented and used by Balanced Two-Column, but never wired
  // into this archetype, despite Skills being promoted to lead position
  // right under the header here specifically. A flat comma-joined skills
  // line reads noticeably weaker than a categorized one exactly where this
  // archetype puts the most visual weight on skills - real,
  // already-collected SkillEntry.category data, never a fabricated
  // grouping. Closes the smallest safe gap D-M8-07 (03-decisions.md)
  // identified against the reference resume's "categorized technical
  // skills" structure without introducing a 6th template.
  final plan = buildResumeContentPlan(
    snapshot,
    skillsBeforeExperience: true,
    emphasizeSummary: true,
    groupSkillsByCategory: true,
  );
  final bodyWidgets = renderContentLines(plan.mainLines, tokens);

  // Post-Milestone-5 visual-quality pass: this archetype's header is now
  // centered (docs/v3/implementation/03-decisions.md) to match its
  // centered/flanked section-heading treatment - the accent bar underneath
  // it must be centered too, or it reads as visibly misaligned against a
  // centered name/contact block above it.
  return [
    bodyWidgets.first,
    pw.SizedBox(height: tokens.entryGap / 2),
    pw.Center(child: pw.Container(height: 2.5, width: 60, color: tokens.accentColor)),
    pw.SizedBox(height: tokens.entryGap / 2),
    ...bodyWidgets.skip(1),
  ];
}
