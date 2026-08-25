import 'package:pdf/widgets.dart' as pw;

import '../../../../models/resume_snapshot.dart';
import '../resume_design_tokens.dart';
import 'two_column_sidebar.dart';

/// The tenth archetype, chosen during Milestone 4 based on the gap the
/// first nine reveal (docs/v3/01-prd.md §8: "one held-open slot for a
/// tenth archetype selected during Milestone 4 based on what the first
/// nine reveal about gaps"): every two-column layout among the first nine
/// puts its sidebar on the *left* only - a right-sidebar mirror is a
/// genuine, common resume convention with zero representation otherwise.
/// An Academic/CV archetype was considered and explicitly rejected for
/// this slot, since §22.6 already defers Academic/CV content types out of
/// V3's scope entirely - choosing it here would just be building the same
/// deferred thing under a different milestone.
///
/// Reuses [buildTwoColumnSidebarPages]'s `sidebarOnRight: true` option
/// rather than a second copy of the same pagination-sensitive
/// `pw.Partitions` composition (`AtsConfidence.high`, matching Two-Column
/// Sidebar's own identical structural-risk disclosure). Dispatched to by
/// [ResumeArchetypeIds.twoColumnRight] (`../resume_template_catalog.dart`)
/// via `ResumeTemplateRenderer`.
///
/// **Reference-driven product redesign pass:** also passes
/// `sidebarAlsoTakesEducationAndCertifications: true`, which
/// [buildTwoColumnSidebarPages] threads into `buildResumeContentPlan` -
/// Education and Certifications move into the rail alongside Skills,
/// leaving the wide main column to Experience and Projects only. This is
/// the archetype's real distinguishing identity now ("Balanced
/// Two-Column" - a wide prose-heavy column beside a denser, list-like
/// rail, matching an asymmetric column-content composition studied in the
/// reference resumes), not merely Two-Column Sidebar mirrored - the
/// previously-genuine redundancy this pass's own design audit flagged.
List<pw.Widget> buildTwoColumnRightPages(ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
  return buildTwoColumnSidebarPages(
    snapshot,
    tokens,
    sidebarOnRight: true,
    sidebarAlsoTakesEducationAndCertifications: true,
    // Product single-template prototype pass: the one structural
    // composition fix that pass's design audit found - see
    // buildTwoColumnSidebarPages's own doc comment for the full
    // reasoning. Two-Column Sidebar deliberately does not set this,
    // leaving its own output unchanged.
    headerSpansFullWidth: true,
    // Single-template prototype pass, second round: pairs with the
    // archetype's own larger density profile (_DensityProfiles
    // .balancedTwoColumn) so the bigger type has room in the rail.
    sidebarWidth: 190,
    // Approved design specification pass: groups the rail's Skills
    // section by SkillEntry.category (Technical / Tools / Soft Skills)
    // instead of one flat list - real, already-collected data.
    groupSkillsByCategory: true,
  );
}
