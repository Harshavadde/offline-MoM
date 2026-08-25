import 'package:pdf/widgets.dart' as pw;

/// Wraps [children] into the sidebar's own content column for
/// `two-column-sidebar` (the only Milestone 1 archetype that uses it) -
/// contact/skills content visually set apart from the main chronological
/// column it sits beside. Purely a layout container; it never decides
/// *what* content goes in it - see `archetypes/two_column_sidebar.dart`
/// and `resume_content_plan_builder.dart`'s `sidebarContactAndSkills`
/// parameter for that decision.
///
/// Returns a plain [pw.Column] - **not** wrapped in a [pw.Container] -
/// deliberately: `two_column_sidebar.dart` places this inside a
/// [pw.Partition] (`package:pdf`'s purpose-built, pagination-aware
/// multi-column primitive), whose `child` must itself be a
/// `SpanningWidget`. `pw.Column` qualifies (`Flex` mixes in
/// `SpanningWidget`); `pw.Container` does not, and wrapping one around it
/// here would silently break page-overflow handling for a long resume -
/// the exact failure this milestone's own long-synthetic-resume test
/// caught before this fix (docs/v3/01-prd.md §15/§25). The sidebar's
/// width/spacing come from [pw.Partition]'s own `width` parameter at the
/// call site instead of a [pw.Container] here.
pw.Column buildSidebarColumn({required List<pw.Widget> children}) {
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children);
}
