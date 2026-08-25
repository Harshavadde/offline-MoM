import '../../../models/resume_snapshot.dart';

/// What kind of content one [ResumeContentLine] carries - the vocabulary
/// [layout] primitives (`template/layout/*.dart`) switch on to pick a
/// visual treatment, and what an ATS reading-order test asserts against
/// directly (see this file's own doc comment below for why that matters).
enum ResumeContentLineKind {
  /// The resume owner's name - always the first line of the main column.
  name,

  /// The user's own typed headline/target-role text (`Resume.targetRole`),
  /// if set - **product visual-audit pass**. This is real, user-authored
  /// text that already existed for M2's JD-matching context but was never
  /// surfaced in the rendered document; it is the one genuinely new,
  /// zero-fabrication-risk piece of content this pass adds to the header,
  /// answering the studied references' own "name + role tagline"
  /// composition without inventing anything. Absent (no line emitted at
  /// all, not an empty one) when the field is unset - never a placeholder.
  roleTagline,

  /// The contact line (email | phone | location).
  contact,

  /// The links line (portfolio/LinkedIn/GitHub/etc.), if any.
  links,

  /// A section heading, e.g. "Experience" - literal, standard text
  /// (docs/v3/01-prd.md §9) regardless of which archetype/preset renders
  /// it.
  sectionHeading,

  /// One entry's title line, e.g. "Senior Engineer - Acme Corp".
  entryTitle,

  /// One entry's meta line, e.g. a date range and/or location.
  entryMeta,

  /// One bullet within an entry. If it immediately follows a
  /// [subProjectTitle] line (with no intervening [entryTitle]/
  /// [sectionHeading]/another [subProjectTitle] closing it out), it belongs
  /// to that sub-project rather than to the parent entry's own top-level
  /// bullets - see [subProjectTitle]'s own doc comment.
  bullet,

  /// One named sub-project nested under the entry currently open (e.g.
  /// "SciLab (Web & Android)" under a "Software Engineer" role) - Resume ->
  /// Experience -> Project -> Project bullets architecture (migration v20,
  /// reliability-overhaul pass, see [ExperienceSubProject]'s own doc
  /// comment in experience_block.dart). Every [bullet] line that follows
  /// belongs to this sub-project, not the parent entry, until either
  /// another [subProjectTitle] or a line that closes the entry itself
  /// (`entryTitle`/`sectionHeading`) appears.
  subProjectTitle,

  /// A single-paragraph section body (used for the Skills section, whose
  /// content is one comma-joined line rather than bulleted entries).
  paragraph,
}

/// Which visual column a line belongs to. Every archetype in Milestone 1
/// is either fully [main] (the three single-column archetypes) or splits
/// contact/skills into [sidebar] while chronological content
/// (Experience/Education/Projects/Certifications) stays in [main] (the
/// two-column archetype) - see `archetypes/two_column_sidebar.dart`.
enum ResumeContentColumn { main, sidebar }

/// One line of resume content, independent of any visual styling -
/// carries only what text it is, what kind of line it is, and which
/// column it belongs to.
///
/// **[primaryText]/[secondaryText] (reference-driven product redesign
/// pass):** for [ResumeContentLineKind.entryTitle] and `.entryMeta` lines
/// only, these carry the *real* structured fields a layout can compose
/// however its own identity calls for - role/degree/name and company/
/// institution for a title line; the date range and location for a meta
/// line - instead of a template having to heuristically re-split [text] on
/// a literal `" - "` substring to recover them. [text] itself remains the
/// canonical joined form (unchanged from before this pass, so every
/// existing consumer/test that reads it directly keeps working) - it is
/// always kept in sync with [primaryText]/[secondaryText] by whichever
/// line built it (`resume_content_plan_builder.dart`), never a second,
/// independently-maintained value. Null for every other line kind, and for
/// an entry with no secondary identifier (e.g. a bare project name).
class ResumeContentLine {
  const ResumeContentLine(
    this.kind,
    this.text, {
    this.column = ResumeContentColumn.main,
    this.primaryText,
    this.secondaryText,
    this.emphasized = false,
    this.isSkillsList = false,
  });

  final ResumeContentLineKind kind;
  final String text;
  final ResumeContentColumn column;
  final String? primaryText;
  final String? secondaryText;

  /// True only for the paragraph line(s) `addSkills()` builds
  /// (resume_content_plan_builder.dart) - lets content_line_renderer.dart
  /// scope [ResumeDesignTokens.skillsAsChips] to the actual Skills section
  /// specifically. Real bug this fixed: a Summary paragraph is also a
  /// plain `paragraph`-kind line, and before this field existed, any
  /// archetype with `skillsAsChips: true` (Modern Accent) rendered the
  /// *Summary* as a comma-split row of chip fragments too - confirmed by
  /// direct visual PDF inspection of a real resume.
  final bool isSkillsList;

  /// Product Phase 3 (real information-architecture differentiation, not
  /// color/font-only variants): a generic per-line "give this more visual
  /// weight than its neighbors" flag - currently only set on Executive
  /// Summary-Led's Summary paragraph (see resume_content_plan_builder.dart's
  /// `emphasizeSummary` parameter), rendered by
  /// content_line_renderer.dart's paragraph case as a callout instead of
  /// plain body text. Deliberately generic (not "isSummary") so a future
  /// archetype can reuse the same mechanism for a different line without a
  /// new field.
  final bool emphasized;
}

/// The full, ordered content plan for one resume, produced by
/// `resume_content_plan_builder.dart` from a [ResumeSnapshot] and consumed
/// by both a template's actual `pw.Widget` construction (via the shared
/// layout primitives) *and* this milestone's automated ATS reading-order
/// tests - the same list drives both, so there is no separate "expected
/// order" the real renderer could silently drift out of sync with.
///
/// **Why this class exists at all, disclosed here since it isn't named in
/// docs/v3/01-prd.md §25's Milestone 1 file list:** the PRD's own ATS
/// round-trip test description calls for extracting text back out of a
/// rendered PDF via the existing `PdfParser`/`read_pdf_text` pipeline
/// (`lib/services/documents/parsers/pdf_parser.dart`). That pipeline wraps
/// a real native plugin (`read_pdf_text`, Android PDFBox-Android / iOS
/// PDFKit via a platform channel) and cannot run under `flutter test` -
/// the same standing, already-disclosed limitation this project's other
/// platform-channel-backed services have (e.g. `ModelDownloadService`'s
/// real network I/O, see its own doc comment; RV3-12,
/// docs/v3/implementation/04-risk-register.md). [ResumeContentPlan] lets
/// this milestone verify the two properties the PRD's ATS test actually
/// cares about - expected section headings present, correct reading order
/// - through the layer that actually determines them, entirely in
/// pure Dart, with no PDF rendering or platform channel involved. A real
/// end-to-end extraction-pipeline check remains a disclosed manual/
/// real-device verification item, not silently skipped.
class ResumeContentPlan {
  const ResumeContentPlan(this.lines);

  final List<ResumeContentLine> lines;

  List<ResumeContentLine> get mainLines =>
      lines.where((l) => l.column == ResumeContentColumn.main).toList(growable: false);

  List<ResumeContentLine> get sidebarLines =>
      lines.where((l) => l.column == ResumeContentColumn.sidebar).toList(growable: false);

  bool get hasSidebar => lines.any((l) => l.column == ResumeContentColumn.sidebar);

  /// Every [ResumeContentLineKind.sectionHeading] line's text, in order -
  /// the exact assertion an ATS reading-order test makes: "these headings
  /// exist, in this order," regardless of which column each lives in.
  List<String> get sectionHeadingsInOrder => lines
      .where((l) => l.kind == ResumeContentLineKind.sectionHeading)
      .map((l) => l.text)
      .toList(growable: false);
}
