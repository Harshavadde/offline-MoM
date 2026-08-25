import 'package:pdf/widgets.dart' as pw;

import '../resume_content_plan.dart';
import '../resume_design_tokens.dart';
import 'chip_list.dart';
import 'divider.dart';
import 'entry_block.dart';
import 'header_block.dart';
import 'section_block.dart';

/// Groups a flat, ordered [ResumeContentLine] list (one column's worth, from
/// [ResumeContentPlan.mainLines] or [.sidebarLines]) into the primitive
/// widgets that actually render it - [buildHeaderBlock]/[buildSectionHeading]/
/// [buildEntryBlock]/[buildDivider]. **Not itself named in
/// docs/v3/01-prd.md §25's Milestone 1 file list** - added because every
/// archetype needs the identical grouping logic (name/contact/links lines
/// into one header; a section heading followed by its entries' title/meta/
/// bullet lines into one entry per title) and duplicating that grouping
/// four times would directly violate the PRD's own "do not duplicate
/// equivalent layout code independently inside every archetype"
/// instruction (§Phase 2). This is the one place that logic lives.
List<pw.Widget> renderContentLines(List<ResumeContentLine> lines, ResumeDesignTokens tokens) {
  final widgets = <pw.Widget>[];

  String? headerName;
  String? headerRoleTagline;
  String? headerContact;
  String? headerLinks;
  var inHeader = false;

  String? entryTitle;
  String? entryTitlePrimary;
  String? entryTitleSecondary;
  String? entryMetaPrimary;
  String? entryMetaSecondary;
  final entryBullets = <String>[];
  final entrySubProjects = <EntrySubProjectView>[];
  var hasOpenEntry = false;
  // The sub-project currently accumulating bullets (Resume -> Experience ->
  // Project -> Project bullets architecture) - null whenever a `bullet`
  // line should instead accumulate into `entryBullets`/render standalone.
  // Closed into `entrySubProjects` by `closeCurrentSubProject()` whenever
  // another `subProjectTitle`, `entryTitle`, or `sectionHeading` line
  // appears, and by `flushEntry()` itself so it is never silently dropped.
  String? currentSubProjectName;
  var currentSubProjectBullets = <String>[];

  void closeCurrentSubProject() {
    final name = currentSubProjectName;
    if (name == null) return;
    entrySubProjects.add(EntrySubProjectView(name, List.of(currentSubProjectBullets)));
    currentSubProjectName = null;
    currentSubProjectBullets = [];
  }
  // Tracks whether the immediately preceding flushed widget was another
  // entry in the *same* section - reset at every section heading - so
  // buildDashedDivider only ever separates two sibling entries, never a
  // section heading from its own first entry (reference-driven redesign
  // pass, ResumeDesignTokens.entryDividerDashed).
  var precedingWasEntryInSection = false;
  // Approved design specification pass: tracks whether the immediately
  // preceding widget was another skill-category group, so consecutive
  // groups (Technical / Tools / Soft Skills) get a real gap between them
  // - the first group after a section heading already has the heading's
  // own trailing spacing and needs none extra.
  var precedingWasSkillGroup = false;

  // Physical-Mobile-First Validation phase (pagination fix): a section
  // heading and its own first content unit must never be split across a
  // page break by pw.MultiPage's automatic flow - previously every widget
  // this function built (heading, spacer, entry, bullet, ...) was pushed
  // as an independent flat sibling, which let MultiPage legally break the
  // page directly between a heading and its first entry, leaving the
  // heading orphaned alone at the bottom of a page (confirmed by direct
  // visual PDF inspection across all 5 beta templates on ordinary
  // resumes, not a contrived edge case). While [pendingSectionHeadingGroup]
  // is non-null, [emit] buffers widgets into it instead of appending them
  // to [widgets] directly; [commitPendingSectionHeadingGroup] wraps that
  // buffer in a pw.Inseparable (package:pdf's own "keep together"
  // primitive - see that function's own doc comment for why a plain
  // pw.Column or pw.Container does not actually achieve this) and pushes
  // it as a single list item - pw.MultiPage only ever moves an
  // Inseparable whole-or-nothing to the next page, never splits inside
  // it. Only the section heading and its *first* content unit are
  // grouped this way (the buffer is committed the moment that first unit
  // finishes emitting) - every later entry/bullet/paragraph in the same
  // section still flows and paginates independently exactly as before, so
  // a section too large for one page still continues naturally onto the
  // next rather than being forced to fit.
  List<pw.Widget>? pendingSectionHeadingGroup;

  // Real-device beta fix: [pendingSectionHeadingGroup] glues a heading to
  // its whole first entry - including every one of that entry's bullets -
  // as one non-splittable pw.Inseparable unit. That was safe when entries
  // were short, but a real resume's own first Experience entry (13 real
  // bullets once sub-project headers stopped being silently dropped, see
  // resume_import_parser.dart's own bullets-extraction fix) made that one
  // atomic unit taller than an entire printable page - pw.MultiPage has no
  // fallback for an Inseparable it can't fit anywhere and simply throws,
  // which would make PDF export fail outright for any resume with one
  // sufficiently bullet-heavy entry. This package exposes no pre-layout
  // height-measurement API (see estimatedTextWidth's own doc comment for
  // the same limitation elsewhere in this file), so total buffered
  // character count is used as a proxy for "this is at real risk of
  // exceeding a page on its own" - a bound comfortably below what any
  // reasonably-sized entry would ever reach, so the orphaned-heading
  // protection this mechanism exists for is unaffected for the
  // overwhelming majority of real entries.
  var pendingGroupContentChars = 0;
  const maxInseparableGroupChars = 1400;

  void emit(pw.Widget widget) {
    final buffer = pendingSectionHeadingGroup;
    if (buffer != null) {
      buffer.add(widget);
    } else {
      widgets.add(widget);
    }
  }

  void commitPendingSectionHeadingGroup() {
    final buffer = pendingSectionHeadingGroup;
    if (buffer == null) return;
    pendingSectionHeadingGroup = null;
    final groupChars = pendingGroupContentChars;
    pendingGroupContentChars = 0;
    if (buffer.isEmpty) return;
    // Real-device beta fix: an unusually large first entry (see this
    // function's own doc comment above pendingGroupContentChars) is
    // emitted as plain, independently-paginating siblings instead of
    // being forced into one atomic unit that pw.MultiPage could never
    // actually fit anywhere - a crash is a far worse outcome than the
    // heading occasionally landing at the bottom of a page in this rare,
    // content-heavy case.
    if (groupChars > maxInseparableGroupChars) {
      widgets.addAll(buffer);
      return;
    }
    // pw.Column (Flex) implements SpanningWidget itself - nesting the
    // buffer in a plain Column does NOT make it atomic, since MultiPage
    // still happily splits *inside* any SpanningWidget it finds, one
    // level deeper in the tree (confirmed by direct visual PDF inspection
    // after the first version of this fix: the orphaned heading defect
    // was completely unchanged). Wrapping in pw.Container instead doesn't
    // work either - Container extends StatelessWidget, and
    // StatelessWidget.canSpan *delegates to its child's own canSpan*, so a
    // Container wrapping a spanning Column still reports canSpan == true
    // and MultiPage still splits inside it exactly as before. pw.Inseparable
    // is package:pdf's own purpose-built "keep together" primitive for
    // this exact case (widgets/widget.dart) - its `canSpan`/`hasMoreWidgets`
    // are hardcoded false regardless of the child, which is what actually
    // makes MultiPage treat it as one atomic, whole-or-nothing unit: move
    // the entire thing to the next page if it doesn't fit here, never
    // split inside it.
    widgets.add(pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: buffer,
      ),
    ));
  }

  // Approximates a heading string's rendered width at [fontSize] - this
  // package exposes no pre-layout text-measurement API (see
  // ResumeDesignTokens.sectionRuleFollowsHeadingWidth's own doc comment).
  // A bold sans-serif glyph averages roughly 0.55x its font size in
  // width; +6pt covers the rule's own small overshoot past the last
  // letter, matching the specification's "heading width + 4pt" intent.
  double estimatedTextWidth(String text, double fontSize) => text.length * fontSize * 0.55 + 6;

  void flushHeader() {
    if (!inHeader) return;
    emit(buildHeaderBlock(
      name: headerName ?? '',
      roleTagline: headerRoleTagline,
      contactLine: headerContact,
      linksLine: headerLinks,
      tokens: tokens,
      centered: tokens.headerCentered,
      nameUsesAccentColor: tokens.nameUsesAccentColor,
      stackedContact: tokens.headerContactStacked,
    ));
    // Post-Milestone-5 visual-quality pass: a thin rule under the header
    // for archetypes with no other header/body separation (see
    // ResumeDesignTokens.headerDivider's own doc comment) - archetypes
    // that already draw their own bespoke accent bar there (Modern
    // Accent-Rule and its siblings) leave this token false to avoid a
    // doubled-up rule.
    if (tokens.headerDivider) {
      emit(pw.SizedBox(height: tokens.entryGap / 2));
      emit(buildDivider(tokens));
    }
    inHeader = false;
  }

  void flushEntry() {
    if (!hasOpenEntry) return;
    closeCurrentSubProject();
    if (widgets.isNotEmpty) {
      emit(pw.SizedBox(height: tokens.entryGap / (precedingWasEntryInSection ? 2 : 1)));
      if (precedingWasEntryInSection && tokens.entryDividerDashed) {
        emit(buildDashedDivider(tokens));
        emit(pw.SizedBox(height: tokens.entryGap / 2));
      }
    }
    emit(buildEntryBlock(
      primaryTitle: entryTitlePrimary ?? entryTitle ?? '',
      secondaryTitle: entryTitleSecondary,
      metaPrimary: entryMetaPrimary,
      metaSecondary: entryMetaSecondary,
      bullets: List.of(entryBullets),
      subProjects: List.of(entrySubProjects),
      tokens: tokens,
    ));
    pendingGroupContentChars += (entryTitlePrimary ?? entryTitle ?? '').length +
        (entryTitleSecondary?.length ?? 0) +
        (entryMetaPrimary?.length ?? 0) +
        (entryMetaSecondary?.length ?? 0) +
        entryBullets.fold<int>(0, (sum, b) => sum + b.length) +
        entrySubProjects.fold<int>(
            0, (sum, p) => sum + p.name.length + p.bullets.fold<int>(0, (s, b) => s + b.length));
    entryTitle = null;
    entryTitlePrimary = null;
    entryTitleSecondary = null;
    entryMetaPrimary = null;
    entryMetaSecondary = null;
    entryBullets.clear();
    entrySubProjects.clear();
    hasOpenEntry = false;
    precedingWasEntryInSection = true;
    // The first entry flushed after a section heading is exactly the
    // "first content unit" that must stay glued to that heading - commit
    // now. Every later entry in the same section finds the buffer already
    // null and simply appends to `widgets` as an independent, freely
    // paginating flat item, same as before this fix.
    commitPendingSectionHeadingGroup();
  }

  for (final line in lines) {
    switch (line.kind) {
      case ResumeContentLineKind.name:
        flushEntry();
        inHeader = true;
        headerName = line.text;
      case ResumeContentLineKind.roleTagline:
        headerRoleTagline = line.text;
      case ResumeContentLineKind.contact:
        headerContact = line.text;
      case ResumeContentLineKind.links:
        headerLinks = line.text;
      case ResumeContentLineKind.sectionHeading:
        // Defensive: commit any stray buffer from a previous, unexpectedly
        // content-less section before flushing the header/prior entry -
        // both of those must land in `widgets` directly, not get
        // absorbed into a stale buffer.
        commitPendingSectionHeadingGroup();
        flushHeader();
        flushEntry();
        precedingWasEntryInSection = false;
        precedingWasSkillGroup = false;
        // Open this heading's own buffer now - every widget this case (and
        // the very next content unit that follows it) builds is glued
        // together as one non-splittable page-break unit, see
        // pendingSectionHeadingGroup's own doc comment above.
        pendingSectionHeadingGroup = [];
        if (widgets.isNotEmpty) {
          emit(pw.SizedBox(height: tokens.sectionGap));
        }
        switch (tokens.sectionHeadingStyle) {
          case SectionHeadingStyle.ruleAbove:
            // The original Milestone 1-era rhythm: a full rule above every
            // heading but the very first (nothing to separate from yet).
            if (widgets.isNotEmpty) {
              emit(buildDivider(tokens));
              emit(pw.SizedBox(height: tokens.sectionGap / 2));
            }
            emit(buildSectionHeading(line.text, tokens));
          case SectionHeadingStyle.ruleBelow:
            // One rule per section, directly under its own heading - never
            // a rule floating between two unrelated sections. Approved
            // design specification pass: when sectionRuleFollowsHeadingWidth
            // is set, the rule hugs the heading text's own width instead
            // of spanning the full column.
            emit(buildSectionHeading(line.text, tokens));
            emit(pw.SizedBox(height: tokens.lineGap));
            if (tokens.sectionRuleFollowsHeadingWidth) {
              emit(buildShortDivider(
                tokens,
                width: estimatedTextWidth(line.text, tokens.headingSize),
              ));
            } else {
              emit(buildDivider(tokens));
            }
          case SectionHeadingStyle.label:
            // No rule at all - buildSectionHeading itself carries the
            // hierarchy (reduced size + letter-spacing, see
            // section_block.dart), relying on whitespace alone.
            emit(buildSectionHeading(line.text, tokens));
          case SectionHeadingStyle.centeredFlanked:
            // The heading centered between two rules, each filling the
            // remaining row width via pw.Expanded - lays out correctly
            // regardless of the heading text's own width, no hand-measured
            // fixed-width assumption (post-Milestone-5 visual-quality pass,
            // studied from the Enhance CV reference bar's own centered/
            // flanked section-heading treatment - reproduced as a generic
            // layout technique, not copied pixel-for-pixel).
            emit(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(child: buildDivider(tokens)),
                pw.SizedBox(width: 10),
                buildSectionHeading(line.text, tokens),
                pw.SizedBox(width: 10),
                pw.Expanded(child: buildDivider(tokens)),
              ],
            ));
        }
        emit(pw.SizedBox(height: tokens.entryGap));
      case ResumeContentLineKind.entryTitle:
        flushHeader();
        flushEntry();
        entryTitle = line.text;
        entryTitlePrimary = line.primaryText;
        entryTitleSecondary = line.secondaryText;
        hasOpenEntry = true;
      case ResumeContentLineKind.entryMeta:
        entryMetaPrimary = line.primaryText ?? line.text;
        entryMetaSecondary = line.secondaryText;
      case ResumeContentLineKind.bullet:
        // Beta data-fidelity fix: a bullet only ever accumulates into
        // `entryBullets` while an entry is open (`hasOpenEntry`, only ever
        // set by an `entryTitle` line above). A custom/generic section
        // (resume_content_plan_builder.dart's own custom-sections loop)
        // emits `sectionHeading` immediately followed by `bullet` lines
        // with no `entryTitle` at all - before this fix, `flushEntry()`'s
        // own `if (!hasOpenEntry) return;` guard silently discarded every
        // one of those bullets, since nothing ever opened an entry to
        // flush them from. Confirmed by direct visual PDF inspection: the
        // section heading rendered, its entries did not. A title-less
        // bullet renders immediately, standalone, reusing `buildBullet`
        // (`entry_block.dart`) directly for the identical visual style -
        // never silently dropped.
        if (currentSubProjectName != null) {
          currentSubProjectBullets.add(line.text);
        } else if (hasOpenEntry) {
          entryBullets.add(line.text);
        } else {
          flushHeader();
          emit(buildBullet(line.text, tokens));
          pendingGroupContentChars += line.text.length;
          // A standalone bullet (a custom section with no entry title) is
          // itself the section's first content unit - commit now, same
          // reasoning as flushEntry()'s own commit call above.
          commitPendingSectionHeadingGroup();
        }
      case ResumeContentLineKind.subProjectTitle:
        // Closes out any previously-open sub-project (its own bullets are
        // already accumulated) before opening this one - a resume entry
        // with several sub-projects emits one `subProjectTitle` line per
        // sub-project, each immediately followed by that sub-project's own
        // `bullet` lines.
        closeCurrentSubProject();
        currentSubProjectName = line.text;
      case ResumeContentLineKind.paragraph:
        flushHeader();
        flushEntry();
        // Approved design specification pass: a paragraph line carrying a
        // primaryText category label (see resume_content_plan_builder.dart's
        // addSkills) renders as a small labeled group when
        // skillsGroupedByCategory is set - real, already-collected
        // SkillEntry.category data, never a fabricated grouping. Checked
        // before skillsAsChips so it takes precedence for the Skills
        // section specifically.
        if (line.emphasized) {
          // Product Phase 3 (real information-architecture differentiation):
          // Executive Summary-Led's actual distinguishing identity - the
          // summary renders as a genuine visual callout (a left accent
          // rule, slightly larger type, generous padding) instead of the
          // same plain body paragraph every other archetype uses for it.
          // Every other archetype never sets ResumeContentLine.emphasized,
          // so this branch is unreachable for them - unchanged behavior.
          emit(pw.Container(
            padding: const pw.EdgeInsets.only(left: 12),
            decoration: pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: tokens.accentColor, width: 2.5)),
            ),
            child: pw.Paragraph(
              text: line.text,
              style: pw.TextStyle(
                fontSize: tokens.bodySize + 1,
                color: tokens.inkColor,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ));
        } else if (line.isSkillsList && line.primaryText != null && tokens.skillsGroupedByCategory) {
          if (precedingWasSkillGroup) {
            // Final visual-polish pass, point #5: 10pt→12pt between
            // category groups (Technical / Tools / Soft Skills) - a
            // touch more separation so the rail reads as distinct,
            // scannable groups rather than one continuous block.
            emit(pw.SizedBox(height: 12));
          }
          emit(buildSkillCategoryGroup(line.primaryText!, line.text, tokens));
          precedingWasSkillGroup = true;
        } else if (line.isSkillsList && tokens.skillsAsChips) {
          // Real-device beta fix: `tokens.skillsAsChips` previously applied
          // to *any* paragraph line, so a "modern accent" archetype with
          // this token set turned a Summary paragraph into a row of
          // comma-split chip fragments too - confirmed by direct visual
          // PDF inspection of a real resume ("Django", "FastAPI", "REST
          // APIs"... rendered as chips, mid-sentence). Chips only ever
          // apply to the actual Skills paragraph now.
          emit(buildChipList(line.text.split(','), tokens));
        } else {
          emit(pw.Paragraph(
            text: line.text,
            style: pw.TextStyle(fontSize: tokens.bodySize, color: tokens.inkColor),
          ));
        }
        pendingGroupContentChars += line.text.length;
        // Only the first paragraph/group after a heading needs to stay
        // glued to it - a no-op once the buffer is already committed, so
        // a Skills section with several category groups still lets group
        // 2+ paginate independently exactly as before this fix.
        commitPendingSectionHeadingGroup();
    }
  }
  flushHeader();
  flushEntry();
  commitPendingSectionHeadingGroup();

  return widgets;
}
