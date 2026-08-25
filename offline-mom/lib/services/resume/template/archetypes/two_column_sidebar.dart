import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../layout/content_line_renderer.dart';
import '../layout/sidebar_column.dart';
import '../resume_content_plan_builder.dart';
import '../resume_design_tokens.dart';

/// Narrow sidebar (name, contact, links, Skills) beside a wider main
/// column (Experience, Education, Projects, Certifications, in that
/// chronological order) - a contemporary, space-efficient layout for
/// tech/marketing/design-adjacent roles. `AtsConfidence.high`, not
/// `.maximum` (see `../resume_template_catalog.dart`): a real ATS's
/// column-reading-order handling varies, so this archetype is explicitly
/// disclosed as one step below the single-column archetypes rather than
/// claimed equally safe (docs/v3/01-prd.md §9).
///
/// **Built on [pw.Partitions]/[pw.Partition], not [pw.Row]/[pw.Expanded]:**
/// an earlier version of this archetype used a plain [pw.Row], which threw
/// `PdfException: Widget won't fit into the page` for a long resume - a
/// real bug this milestone's own long-synthetic-resume test caught, not a
/// theoretical concern (docs/v3/01-prd.md §15's "page-overflow must be
/// handled gracefully" requirement). `pw.Row`/`pw.Expanded` do not support
/// spanning content across a page break; [pw.Partitions] is
/// `package:pdf`'s own purpose-built multi-column primitive that does
/// (`Partitions extends Widget with SpanningWidget`) - still `package:pdf`,
/// no new dependency.
///
/// **Reading order, disclosed:** the sidebar (name/contact/skills)
/// [pw.Partition] is listed *before* the main column's in
/// [pw.Partitions.children] - `package:pdf` emits partitions' content in
/// that child order, so a PDF text extractor reading in emission order
/// encounters the sidebar first, then the main column. This is a
/// best-effort, disclosed claim verified by this milestone's
/// `ResumeContentPlan`-based reading-order test (see
/// `resume_content_plan.dart`'s own doc comment for why that test exists
/// instead of a real PDF-extraction round-trip) - not a guarantee against
/// every real-world ATS's actual column-handling behavior.
///
/// [sidebarOnRight] (Milestone 4, docs/v3/01-prd.md §25) places the sidebar
/// [pw.Partition] *after* the main column's instead of before it - reused
/// unchanged by `two_column_right.dart`'s tenth archetype rather than
/// duplicating this pagination-sensitive composition a second time.
///
/// **[headerSpansFullWidth] (product single-template prototype pass) -
/// the one structural composition fix this pass's design audit found:**
/// with this `false` (the default, Two-Column Sidebar's unchanged
/// behavior), the header (name/tagline/contact/links) is the first
/// content *inside* the narrow rail `pw.Partition`, confining the page's
/// single strongest visual anchor to ~31% of the page width while the
/// main column's very first element is a bare section heading with
/// nothing above it. Every studied Enhance CV two-column reference does
/// the opposite: the name spans the full page width at the top, and the
/// two-column split begins below that. When `true` (Balanced Two-Column
/// only), the header widget - already produced as the first item
/// `renderContentLines` emits for the sidebar's line list, since header
/// lines are always grouped first - is pulled out and rendered once, full
/// width, before `pw.Partitions` begins; only the rail's *remaining*
/// content (Education/Skills/Certifications) renders inside the narrow
/// column. This is a genuine composition-order change, not a token: it
/// changes what belongs above the region split versus inside a region,
/// the minimum architectural correction the audit judged necessary -
/// not the larger page/region-allocation layer investigated and declined
/// in the prior pass (see docs/v3/implementation/03-decisions.md, D-M5-28
/// and this pass's own entry).
List<pw.Widget> buildTwoColumnSidebarPages(
  ResumeSnapshot snapshot,
  ResumeDesignTokens tokens, {
  bool sidebarOnRight = false,
  bool sidebarAlsoTakesEducationAndCertifications = false,
  bool headerSpansFullWidth = false,
  double sidebarWidth = 168,
  bool groupSkillsByCategory = false,
}) {
  final plan = buildResumeContentPlan(
    snapshot,
    sidebarContactAndSkills: true,
    sidebarAlsoTakesEducationAndCertifications: sidebarAlsoTakesEducationAndCertifications,
    groupSkillsByCategory: groupSkillsByCategory,
  );
  final sidebarWidgetsAll = renderContentLines(plan.sidebarLines, tokens);
  final mainWidgets = renderContentLines(plan.mainLines, tokens);

  pw.Widget? fullWidthHeader;
  var sidebarWidgets = sidebarWidgetsAll;
  if (headerSpansFullWidth && sidebarWidgetsAll.isNotEmpty) {
    fullWidthHeader = sidebarWidgetsAll.first;
    sidebarWidgets = sidebarWidgetsAll.skip(1).toList();
  }

  // Product composition-audit pass: widened from a fixed 140pt (~26% of
  // an A4 page's printable width) to 168pt (~31%, Two-Column Sidebar's
  // still-unchanged default) - the prior ratio was a space-allocation
  // number, not a considered proportion, and was measurably too narrow: a
  // realistic role tagline or a "Degree - Institution" entry title
  // wrapped awkwardly at 140pt (found via direct visual inspection).
  // [sidebarWidth] (single-template prototype pass, second round) lets
  // Balanced Two-Column widen further still (190pt) to give its own,
  // larger type scale room to breathe in the rail without wrapping more
  // than before - Two-Column Sidebar keeps 168pt unchanged.
  final sidebarPartition = pw.Partition(width: sidebarWidth, child: buildSidebarColumn(children: sidebarWidgets));
  // A fixed-width empty partition as the gutter between columns -
  // pw.Partition has no padding parameter of its own (unlike
  // pw.Container, which can't be used here at all - see
  // buildSidebarColumn's doc comment).
  final gutterPartition = pw.Partition(width: 16, child: pw.Column());
  final mainPartition =
      pw.Partition(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: mainWidgets));

  final partitions = pw.Partitions(
    children: sidebarOnRight
        ? [mainPartition, gutterPartition, sidebarPartition]
        : [sidebarPartition, gutterPartition, mainPartition],
  );

  if (fullWidthHeader == null) return [partitions];
  return [fullWidthHeader, pw.SizedBox(height: tokens.sectionGap * 0.6), partitions];
}
