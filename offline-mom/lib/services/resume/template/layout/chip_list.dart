import 'package:pdf/widgets.dart' as pw;

import '../resume_design_tokens.dart';

/// One skill-category group - a small, accent-colored, letter-spaced label
/// (e.g. "Technical", derived directly from [SkillCategory]'s own enum
/// name, never invented) followed by that category's skill names as
/// flowing, dot-joined text - **approved design specification pass**,
/// used in place of [buildChipList] when
/// [ResumeDesignTokens.skillsGroupedByCategory] is set. No border, no
/// background fill: the review that requested this treatment explicitly
/// named bordered chips as reading "like default UI controls" rather than
/// an editorial typeset list - flowing text with a label is the direct
/// answer, and every skill name is still real, selectable `pw.Text`.
/// Label letter-spacing (0.8→1.0) and item line-height (1.3→1.4) both
/// nudged slightly in the final visual-polish pass, point #5, for a touch
/// more editorial breathing room - never chips, never a proficiency
/// indicator of any kind.
pw.Widget buildSkillCategoryGroup(String categoryLabel, String commaJoinedItems, ResumeDesignTokens tokens) {
  final items = commaJoinedItems.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        categoryLabel,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.0,
          color: tokens.accentColor,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        items.join(' · '),
        style: pw.TextStyle(fontSize: 9.5, color: tokens.inkColor, lineSpacing: 1.4),
      ),
    ],
  );
}

/// Renders [items] as a wrapped row of small bordered tag chips - the
/// scannable, contemporary Skills treatment (Beta Template Quality Pass,
/// docs/v3/01-prd.md §2 #6/§8) used when [ResumeDesignTokens.skillsAsChips]
/// is set, in place of `renderContentLines`'s default plain
/// `pw.Paragraph` for a Skills section.
///
/// Built once here rather than duplicated per archetype (docs/v3/01-prd.md
/// §22.2's shared-primitive discipline). Uses `pw.Wrap`, not a fixed-size
/// `pw.Row`/`pw.Container`: `pw.Wrap` mixes in `SpanningWidget`
/// (`package:pdf`'s own multi-column/pagination-aware primitive, the same
/// property `sidebar_column.dart`'s own doc comment requires of anything
/// placed inside a `pw.Partition`), so a long chip list wraps and, if
/// needed, continues cleanly onto the next page - it never overflows or
/// gets silently clipped, matching this project's own long-resume
/// pagination requirement (docs/v3/01-prd.md §15/§25) and safe whether
/// this is placed in a single-column main flow or a two-column sidebar
/// `pw.Partition`.
///
/// Every chip's text is still real, selectable `pw.Text` - no image, no
/// rasterized content, no reading-order risk of its own (docs/v3/01-prd.md
/// §9). A border only, never a filled background: a filled/colored
/// background block risks poor contrast against an arbitrary preset's
/// accent color and reads as more decorative than the restrained,
/// professional tag treatment this is meant to be.
pw.Widget buildChipList(List<String> items, ResumeDesignTokens tokens) {
  final chips = items.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  return pw.Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final item in chips)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: tokens.dividerColor, width: 0.75),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Text(item, style: pw.TextStyle(fontSize: tokens.captionSize, color: tokens.inkColor)),
        ),
    ],
  );
}
