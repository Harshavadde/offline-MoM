import '../../../models/resume_snapshot.dart';
import '../../../models/skill_entry.dart' show SkillCategory;
import 'resume_content_plan.dart';

/// Turns a [ResumeSnapshot] into an ordered [ResumeContentPlan] - the one
/// shared "what content, in what order" pass every Milestone 1 archetype
/// builds on, so section order/content assembly is never duplicated
/// per-archetype (docs/v3/01-prd.md §22.2's "no duplicated widgets/layout
/// code" discipline, applied to content assembly as well as visual
/// widgets). Section order (Experience, Education, Skills, Projects,
/// Certifications) matches the existing single-template
/// `PwResumePdfExportService` exactly - a deliberate continuity choice,
/// not a new convention.
///
/// [sidebarContactAndSkills] moves the name/contact/links/Skills lines
/// into [ResumeContentColumn.sidebar] instead of [ResumeContentColumn.main]
/// - used by the two-column archetypes (see `archetypes/two_column_sidebar.dart`);
/// every single-column archetype calls this with the default `false`,
/// keeping every line in the main column.
///
/// [sidebarAlsoTakesEducationAndCertifications] (reference-driven product
/// redesign pass) additionally moves Education and Certifications into the
/// sidebar column - used by `archetypes/two_column_right.dart` to give it
/// a genuinely distinct column-content composition from Two-Column
/// Sidebar's "narrow strip of contact+skills only" shape, rather than the
/// two archetypes differing only in which side the identical sidebar sits
/// on. Only meaningful when [sidebarContactAndSkills] is also `true`.
///
/// [skillsBeforeExperience]/[educationBeforeExperience] (Milestone 4,
/// docs/v3/01-prd.md §25) reorder the *main-column* section sequence for
/// archetypes whose character is specifically about what leads - e.g.
/// Executive Summary-Led (skills-forward) or Entry-Level/Student
/// (education-forward, since a recent graduate's degree is typically more
/// relevant than a thin work history). At most one of the two should be
/// `true` at a time; both default `false`, preserving every existing
/// archetype's exact Experience → Education → Skills → Projects →
/// Certifications order unchanged.
///
/// [capOlderExperienceBullets] (product composition-audit pass) - a real
/// information-hierarchy decision this content plan previously had none
/// of: every Experience entry, regardless of how old or how far down the
/// chronological list, rendered with identical bullet-count weight. A long
/// career history was therefore not *composed* - it was stacked until it
/// ran out of entries. When `true` (the default) and the snapshot has 4 or
/// more Experience entries, the 2 most-recent entries (ranked by parsed
/// end date, `Present`/null ranking highest - never by list position,
/// since `sortOrder` is user-controlled and not guaranteed chronological)
/// keep every bullet the user wrote; every other entry is capped to its
/// first 2 bullets. This never hides an entire entry, never rewrites or
/// invents a bullet, and never applies at all to a resume with 3 or fewer
/// roles - it only changes how much of an *older* role's already-authored
/// detail is shown, matching the recency-weighted emphasis convention
/// real resume writers already use. [ResumeArchetypeIds.governmentDense]
/// passes `false`, since that archetype's own stated identity is a
/// complete, exhaustive chronological record.
ResumeContentPlan buildResumeContentPlan(
  ResumeSnapshot snapshot, {
  bool sidebarContactAndSkills = false,
  bool sidebarAlsoTakesEducationAndCertifications = false,
  bool skillsBeforeExperience = false,
  bool educationBeforeExperience = false,
  bool capOlderExperienceBullets = true,
  bool groupSkillsByCategory = false,
  // Product Phase 3 (real information-architecture differentiation): the
  // Summary paragraph renders as a visually emphasized callout (see
  // ResumeContentLine.emphasized) instead of plain body text - Executive
  // Summary-Led's real distinguishing identity, on top of its existing
  // skillsBeforeExperience reorder, since a "prominent professional
  // summary" only reads as prominent if it's actually rendered with more
  // visual weight than an ordinary paragraph, not merely positioned first.
  bool emphasizeSummary = false,
  // Product Phase 3: promotes Projects to render immediately after
  // Experience, ahead of Education/Skills - Modern Accent's real
  // distinguishing identity (a "modern professional" ordering that
  // foregrounds concrete project execution over credentials), rather than
  // sharing Classic's identical Experience → Education → Skills → Projects
  // flow and differing only in color/header treatment.
  bool projectsBeforeEducation = false,
}) {
  final headerColumn =
      sidebarContactAndSkills ? ResumeContentColumn.sidebar : ResumeContentColumn.main;
  final railColumn = sidebarAlsoTakesEducationAndCertifications ? headerColumn : ResumeContentColumn.main;
  final lines = <ResumeContentLine>[];
  final profile = snapshot.profile;

  lines.add(ResumeContentLine(ResumeContentLineKind.name, profile.fullName, column: headerColumn));

  final roleTagline = profile.roleTagline?.trim();
  if (roleTagline != null && roleTagline.isNotEmpty) {
    lines.add(ResumeContentLine(ResumeContentLineKind.roleTagline, roleTagline, column: headerColumn));
  }

  final contact =
      [profile.email, profile.phone, profile.location].whereType<String>().where((s) => s.isNotEmpty);
  if (contact.isNotEmpty) {
    lines.add(ResumeContentLine(ResumeContentLineKind.contact, contact.join(' | '), column: headerColumn));
  }

  if (profile.links.isNotEmpty) {
    lines.add(ResumeContentLine(
      ResumeContentLineKind.links,
      profile.links.map((l) => '${l.label}: ${l.url}').join('  '),
      column: headerColumn,
    ));
  }

  // Real-device beta fix: a Summary/Objective custom section - however it
  // entered the snapshot (import auto-persistence, or a user manually
  // titling a custom section "Summary") - previously rendered wherever the
  // generic trailing custom-sections loop below placed it: dead last,
  // after Certifications, since that loop has no notion of a summary being
  // different from an Award or a Publication. Every real resume (and the
  // PRD's own section-order expectation) puts a Professional Summary
  // immediately after the header, before Experience/Skills - matched here
  // by rendering a summary-titled section right after the header/links and
  // excluding it from the generic loop later, rather than by reordering
  // custom sections generally (an Award or Publication still belongs at
  // the end).
  const summaryTitles = {
    'summary',
    'professional summary',
    'objective',
    'career objective',
    'career summary',
    'profile',
    'about',
    'about me',
  };
  bool isSummarySection(String title) => summaryTitles.contains(title.trim().toLowerCase());
  final summarySections = snapshot.customSections.where((s) => isSummarySection(s.title));
  for (final section in summarySections) {
    // Real-device beta fix: always the *main* column, never [headerColumn]
    // - a two-column archetype's [headerColumn] is its narrow sidebar
    // (~190pt wide for Balanced Two-Column), and a flowing summary
    // paragraph forced into that width wraps into many short lines,
    // making the sidebar column disproportionately tall relative to the
    // main column. That imbalance is what was actually causing
    // pw.Partitions - package:pdf's own page-balancing primitive for the
    // two-column archetypes - to throw PdfTooBigPageException ("more than
    // 20 pages") on a real resume with a genuine multi-line summary,
    // confirmed by bisection (removing the summary from the sidebar
    // column alone resolved it). A prose paragraph belongs in the wide
    // column regardless of archetype; only list-like content (Skills,
    // Education, Certifications) is ever routed to the narrow rail.
    lines.add(ResumeContentLine(ResumeContentLineKind.sectionHeading, section.title));
    if (section.entries.length == 1) {
      // A single-entry section (a joined paragraph) reads as prose, not a
      // one-item list - a lone bullet dot in front of a whole summary
      // paragraph looks like a rendering defect, not a deliberate list.
      lines.add(ResumeContentLine(
        ResumeContentLineKind.paragraph,
        section.entries.single,
        emphasized: emphasizeSummary,
      ));
    } else {
      for (final entry in section.entries) {
        lines.add(ResumeContentLine(ResumeContentLineKind.bullet, entry, emphasized: emphasizeSummary));
      }
    }
  }

  void addExperience() {
    if (snapshot.experience.isEmpty) return;
    lines.add(const ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'));

    // Recency-weighted bullet density (see this function's own doc
    // comment for the full reasoning) - computed by parsed end date, not
    // list position, since entry order follows the user's own
    // `sortOrder`, not a guaranteed chronological sort.
    const keepFullDetailCount = 2;
    const olderEntryBulletCap = 2;
    final applyCap = capOlderExperienceBullets && snapshot.experience.length >= 4;
    Set<int> fullDetailIndices = const {};
    if (applyCap) {
      final rankedByRecency = List.generate(snapshot.experience.length, (i) => i)
        ..sort((a, b) =>
            (snapshot.experience[b].endDate ?? '9999-99').compareTo(snapshot.experience[a].endDate ?? '9999-99'));
      fullDetailIndices = rankedByRecency.take(keepFullDetailCount).toSet();
    }

    for (var i = 0; i < snapshot.experience.length; i++) {
      final e = snapshot.experience[i];
      lines.add(ResumeContentLine(
        ResumeContentLineKind.entryTitle,
        '${e.role} - ${e.company}',
        primaryText: e.role,
        secondaryText: e.company,
      ));
      final dateRange = '${e.startDate} - ${e.endDate ?? 'Present'}';
      lines.add(ResumeContentLine(
        ResumeContentLineKind.entryMeta,
        e.location != null ? '$dateRange | ${e.location}' : dateRange,
        primaryText: dateRange,
        secondaryText: e.location,
      ));
      final isCappedEntry = applyCap && !fullDetailIndices.contains(i);
      final bullets = isCappedEntry ? e.bullets.take(olderEntryBulletCap).toList() : e.bullets;
      for (final bullet in bullets) {
        lines.add(ResumeContentLine(ResumeContentLineKind.bullet, bullet));
      }
      // Resume -> Experience -> Project -> Project bullets architecture
      // (migration v20, reliability-overhaul pass): each named sub-project
      // nested under this role gets its own `subProjectTitle` line followed
      // by its own `bullet` lines, so content_line_renderer.dart can render
      // it as structurally distinct from the role's own top-level
      // accomplishments. Recency-weighted density (see this function's own
      // doc comment above) applies identically here - an older, capped
      // entry's sub-projects are capped too, never left at full detail
      // while the parent role's own bullets are trimmed.
      for (final subProject in e.subProjects) {
        lines.add(ResumeContentLine(ResumeContentLineKind.subProjectTitle, subProject.name));
        final subBullets = isCappedEntry
            ? subProject.bullets.take(olderEntryBulletCap).toList()
            : subProject.bullets;
        for (final bullet in subBullets) {
          lines.add(ResumeContentLine(ResumeContentLineKind.bullet, bullet));
        }
      }
    }
  }

  void addEducation() {
    if (snapshot.education.isEmpty) return;
    lines.add(ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Education', column: railColumn));
    for (final ed in snapshot.education) {
      lines.add(ResumeContentLine(
        ResumeContentLineKind.entryTitle,
        '${ed.degree} - ${ed.institution}',
        column: railColumn,
        primaryText: ed.degree,
        secondaryText: ed.institution,
      ));
      final dateRange = '${ed.startDate} - ${ed.endDate ?? 'Present'}';
      lines.add(ResumeContentLine(
        ResumeContentLineKind.entryMeta,
        dateRange,
        column: railColumn,
        primaryText: dateRange,
      ));
      for (final detail in ed.details) {
        lines.add(ResumeContentLine(ResumeContentLineKind.bullet, detail, column: railColumn));
      }
    }
  }

  // Human labels for SkillCategory - approved design specification pass.
  // The category itself is real, already-collected data
  // (SkillEntry.category); these are only display labels for that data,
  // never an invented grouping.
  const skillCategoryLabels = {
    SkillCategory.technical: 'Technical',
    SkillCategory.tool: 'Tools',
    SkillCategory.soft: 'Soft Skills',
  };

  void addSkills() {
    if (snapshot.skills.isEmpty) return;
    lines.add(ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Skills', column: headerColumn));
    if (groupSkillsByCategory) {
      // One paragraph line per non-empty category, in a fixed display
      // order, each carrying its human label as primaryText -
      // content_line_renderer.dart's paragraph case renders these as a
      // labeled group instead of one flat line when
      // ResumeDesignTokens.skillsGroupedByCategory is set.
      for (final category in SkillCategory.values) {
        final inCategory = snapshot.skills.where((s) => s.category == category);
        if (inCategory.isEmpty) continue;
        lines.add(ResumeContentLine(
          ResumeContentLineKind.paragraph,
          inCategory.map((s) => s.name).join(', '),
          column: headerColumn,
          primaryText: skillCategoryLabels[category],
          isSkillsList: true,
        ));
      }
      return;
    }
    lines.add(ResumeContentLine(
      ResumeContentLineKind.paragraph,
      snapshot.skills.map((s) => s.name).join(', '),
      column: headerColumn,
      isSkillsList: true,
    ));
  }

  void addProjects() {
    if (snapshot.projects.isEmpty) return;
    lines.add(const ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Projects'));
    for (final p in snapshot.projects) {
      lines.add(ResumeContentLine(
        ResumeContentLineKind.entryTitle,
        p.name,
        primaryText: p.name,
      ));
      if (p.link != null) {
        lines.add(ResumeContentLine(ResumeContentLineKind.entryMeta, p.link!, primaryText: p.link));
      }
      for (final bullet in p.bullets) {
        lines.add(ResumeContentLine(ResumeContentLineKind.bullet, bullet));
      }
    }
  }

  if (skillsBeforeExperience) {
    addSkills();
    addExperience();
    if (projectsBeforeEducation) addProjects();
    addEducation();
  } else if (educationBeforeExperience) {
    addEducation();
    addExperience();
    addSkills();
  } else {
    addExperience();
    if (projectsBeforeEducation) addProjects();
    addEducation();
    addSkills();
  }

  if (!projectsBeforeEducation) addProjects();

  if (snapshot.certifications.isNotEmpty) {
    lines.add(ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Certifications', column: railColumn));
    for (final c in snapshot.certifications) {
      final issuerAndDate = c.issuedDate != null ? '${c.issuer} (${c.issuedDate})' : c.issuer;
      lines.add(ResumeContentLine(
        ResumeContentLineKind.entryTitle,
        '${c.name} - $issuerAndDate',
        column: railColumn,
        primaryText: c.name,
        secondaryText: issuerAndDate,
      ));
    }
  }

  // Generic/custom sections (beta data-fidelity requirement,
  // docs/v3/implementation/03-decisions.md) - rendered with the same
  // primitives every other section already uses (sectionHeading, plus
  // either a single paragraph or a bullet-per-entry list depending on
  // shape - see the summary-rendering block above for why), never a
  // special per-archetype layout. Always last, in the order they appear
  // in the snapshot (import/attach order) - an unknown section never
  // claims a privileged position over the sections this app does have
  // dedicated layouts for. Summary/Objective-titled sections are excluded
  // here since they already rendered right after the header above.
  for (final section in snapshot.customSections) {
    if (isSummarySection(section.title)) continue;
    lines.add(ResumeContentLine(ResumeContentLineKind.sectionHeading, section.title));
    if (section.entries.length == 1) {
      lines.add(ResumeContentLine(ResumeContentLineKind.paragraph, section.entries.single));
    } else {
      for (final entry in section.entries) {
        lines.add(ResumeContentLine(ResumeContentLineKind.bullet, entry));
      }
    }
  }

  return ResumeContentPlan(lines);
}
