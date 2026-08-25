import 'package:pdf/pdf.dart';

/// How a section heading (e.g. "Experience") is visually introduced -
/// Beta Template Quality Pass (post-Milestone 4, docs/v3/01-prd.md §2 #6/
/// §8): the single highest-leverage lever for making archetypes feel
/// genuinely different from each other, since every archetype's body
/// content funnels through the same `renderContentLines` primitive
/// (`layout/content_line_renderer.dart`) - varying *how* a heading is
/// introduced there changes the whole document's visual rhythm without
/// duplicating any rendering logic per archetype.
enum SectionHeadingStyle {
  /// A full-width divider rule *above* every heading (the original,
  /// Milestone 1-era treatment) - reads as a traditional, formally
  /// separated document.
  ruleAbove,

  /// A short rule directly *under* the heading text - a single rule per
  /// section instead of one floating between two sections, reading as
  /// cleaner and more contemporary.
  ruleBelow,

  /// No rule at all - the heading itself carries the hierarchy, at a
  /// slightly reduced size with extra letter-spacing (`buildSectionHeading`,
  /// `layout/section_block.dart`), relying on whitespace alone. Never
  /// changes the heading's literal text/casing (docs/v3/01-prd.md §9 -
  /// section names must exist as literal, standard text).
  label,

  /// The heading text centered on the page, flanked on both sides by a
  /// horizontal rule that fills the remaining width (post-Milestone-5
  /// visual-quality pass) - the signature "— Heading —" motif studied from
  /// the Enhance CV reference bar this pass targets. Composed in
  /// `layout/content_line_renderer.dart` as a `pw.Row` of
  /// `Expanded(rule)`/`Text`/`Expanded(rule)`, which lays out correctly
  /// regardless of the heading text's own width - never a hand-measured
  /// fixed-width assumption. Reserved for the one or two archetypes whose
  /// whole identity is a more formal, letterhead-style presentation
  /// (paired with [ResumeDesignTokens.headerCentered]); the majority of
  /// archetypes keep [ruleBelow]/[label]/[ruleAbove] for differentiation.
  centeredFlanked,
}

/// How one entry's structured header (role/degree/name, company/
/// institution, date range, location) composes into a widget
/// (reference-driven product redesign pass) - the real structural lever
/// this pass adds, replacing the single fixed "title left, date right, one
/// line" shape every archetype previously shared regardless of identity.
enum EntryHeaderStyle {
  /// Role/degree and company/institution on one line (role emphasized,
  /// company subordinate via `layout/entry_block.dart`'s two-tone
  /// treatment), date right-aligned on the same line, location omitted or
  /// folded in only if space allows - the dense, space-efficient
  /// convention most of the catalog uses.
  inline,

  /// Role/degree on its own line, company/institution on the line below
  /// it, then date range and location together on a third line -
  /// reproduces the studied Enhance CV reference resumes' own multi-line
  /// entry composition, reserved for the archetypes whose whole identity
  /// is a more formal, expansive, "senior/leadership document" character
  /// (Executive, Dense Senior/Leadership) rather than applied everywhere -
  /// this uses meaningfully more vertical space per entry, a real
  /// trade-off against density that only suits those two archetypes'
  /// character.
  stacked,

  /// Role/degree and its date range share one row (role left, date
  /// right-aligned) - the two facts a quick scan needs together - while
  /// company/institution and location drop to a quiet second row, joined
  /// by a middle dot, in a distinctly subordinate style. **Approved
  /// design specification pass.** Reserved for Balanced Two-Column, the
  /// one archetype this composition was specified for; every other
  /// archetype keeps [inline] or [stacked].
  editorial,
}

/// How a bullet's leading marker renders - **approved design
/// specification pass**. [shape] (the default, every archetype's
/// unchanged behavior) draws a small filled geometric shape via
/// `pw.Bullet`'s own `bulletShape`. [dash] renders a literal "–" glyph
/// instead, composed by hand (`pw.Bullet` has no glyph-marker option) -
/// a typographic marker rather than a UI-list-item shape, specified for
/// Balanced Two-Column only.
enum BulletMarkerStyle { shape, dash }

/// How an entry's internal spacing rhythm is computed - **design-execution
/// pass**: an independent visual review judged the prior passes' fixed,
/// uniform gaps (the same `lineGap` between every element - title,
/// company, meta, and every bullet alike) as reading like "programmatic
/// spacing" rather than an editorial rhythm that itself communicates
/// hierarchy. [standard] is every archetype's unchanged existing behavior;
/// [editorial] differentiates title→company, company→meta, meta→first-
/// bullet, and bullet→bullet gaps from each other (tight within the
/// entry's own header, more generous before the achievements begin),
/// deliberately opted into by only one archetype at a time via
/// [ResumeDesignTokens.entryRhythmStyle] rather than changed globally -
/// the explicit instruction this pass works under is "only the flagship,"
/// and a shared primitive change would otherwise leak into every other
/// archetype using [EntryHeaderStyle.stacked] (Executive Summary-Led,
/// Government Dense).
enum EntryRhythmStyle { standard, editorial }

/// How the header block (name/role-tagline/contact) is visually composed -
/// **product visual-audit pass**: the audit's own P0 finding was that every
/// archetype's header is plain black text on white with no visual anchor,
/// where the studied Enhance CV references use a colored role-tagline pill
/// or a full-width color band as the page's first, strongest visual
/// signal. Kept as three explicit options rather than a boolean, since
/// [colorBand] and [pill] are visually distinct treatments an archetype
/// commits to, not two toggles that can combine.
enum HeaderStyle {
  /// Name + optional role tagline + contact, plain text on the page
  /// background - the original, maximum-neutrality treatment every
  /// archetype used before this pass. Kept as the default for archetypes
  /// whose whole identity is restraint (Minimalist Monochrome) or maximum
  /// ATS/conservative safety (Classic, Compact Technical, Government
  /// Dense) - a color block would contradict, not support, those
  /// identities.
  plain,

  /// The role tagline (only) rendered inside a rounded, filled
  /// [ResumeDesignTokens.accentColor] pill with light text - reproduces
  /// the studied reference's own "colored banner directly under the name"
  /// treatment without touching the name or contact line's plain styling.
  pill,

  /// The entire header (name, role tagline, contact) rendered inside a
  /// solid [ResumeDesignTokens.accentColor] block spanning the full
  /// content width (not true edge-to-edge page bleed - see
  /// `layout/header_block.dart`'s own doc comment for why), with light
  /// text throughout - the boldest treatment, reserved for the archetypes
  /// whose identity is explicitly "more visual personality" (Modern
  /// Accent, Creative Visual).
  colorBand,
}

/// Which half of an entry's title (role/degree vs. company/institution)
/// carries the bold, ink-dark visual weight - **product visual-audit
/// pass**: the two full-detail Enhance CV references studied for this pass
/// disagree with each other on this (one bolds the role, the other bolds
/// the company), which is itself the finding - it is a per-template
/// creative choice, not a universal rule. [EntryTitleEmphasis.role] was
/// the only option this catalog had before this pass (implicitly, via
/// `entry_block.dart`'s original always-bold-primary logic); [company] is
/// new, applied only to the archetypes whose identity is institutional/
/// formal rather than personal-brand-forward (Classic, Government Dense).
enum EntryTitleEmphasis { role, company }

/// A named, purpose-built set of typography/spacing/color values for
/// rendering one resume template (docs/v3/01-prd.md §8/§22.2). Deliberately
/// **not** derived from or coupled to this app's Flutter `AppTheme`/
/// `AccentColors` (`lib/core/theme/`) - different rendering technology
/// (`pdf` package widgets vs. Flutter widgets, hence [PdfColor] here, never
/// `dart:ui`'s `Color`) and a different concern entirely (print/document
/// typography vs. app chrome). A `ResumeTemplateSpec` (`resume_template_spec.dart`)
/// pairs one archetype with one of these token presets; the same archetype
/// rendered with a different preset produces a different-looking but
/// structurally identical document.
class ResumeDesignTokens {
  const ResumeDesignTokens({
    required this.nameSize,
    required this.headingSize,
    required this.subheadingSize,
    required this.bodySize,
    required this.captionSize,
    required this.pageMargin,
    required this.sectionGap,
    required this.entryGap,
    required this.lineGap,
    required this.inkColor,
    required this.inkSoftColor,
    required this.accentColor,
    required this.dividerColor,
    this.headingUsesAccentColor = false,
    this.sectionHeadingStyle = SectionHeadingStyle.ruleAbove,
    this.headerCentered = false,
    this.nameUsesAccentColor = false,
    this.skillsAsChips = false,
    this.headerDivider = false,
    this.headerContactStacked = false,
    this.entryDividerDashed = false,
    this.entryHeaderStyle = EntryHeaderStyle.inline,
    this.headerStyle = HeaderStyle.plain,
    this.headerContactIcons = false,
    this.entryTitleEmphasis = EntryTitleEmphasis.role,
    this.companySize,
    this.entryRhythmStyle = EntryRhythmStyle.standard,
    this.bulletLineSpacing = 1.2,
    this.headerTaglineSize,
    this.headerRhythmGap,
    this.headerGapAfterTagline,
    this.sectionRuleUsesAccentColor = false,
    this.headerContactCompactDots = false,
    this.headerTaglineItalic = false,
    this.bulletMarkerStyle = BulletMarkerStyle.shape,
    this.sectionRuleFollowsHeadingWidth = false,
    this.skillsGroupedByCategory = false,
  }) : assert(
          bodySize >= 9,
          'Body text may never render below a 9pt-equivalent floor (docs/v3/01-prd.md §8) - '
          'a lower value would trade ATS/human readability for density.',
        );

  /// The resume owner's name - the single largest text on the page.
  final double nameSize;

  /// Section headings (e.g. "Experience").
  final double headingSize;

  /// Entry titles (e.g. "Senior Engineer - Acme Corp").
  final double subheadingSize;

  /// Bullets, paragraphs, entry meta lines - never below 9 (enforced above).
  final double bodySize;

  /// The smallest text used (e.g. a contact line) - still never below 9.
  final double captionSize;

  /// Uniform page margin on all four sides.
  final double pageMargin;

  /// Vertical space between two sections (e.g. Experience -> Education).
  final double sectionGap;

  /// Vertical space between two entries within the same section.
  final double entryGap;

  /// Vertical space between adjacent lines within one entry (e.g. a title
  /// and its meta line).
  final double lineGap;

  /// Primary text color (names, entry titles, body text).
  final PdfColor inkColor;

  /// Secondary text color (contact lines, dates/locations, captions) -
  /// always a muted variant of [inkColor], never the [accentColor].
  final PdfColor inkSoftColor;

  /// The one deliberate color accent a preset introduces - used for
  /// dividers and, when [headingUsesAccentColor] is true, section
  /// headings. Decorative only: never the sole carrier of meaning (ATS/
  /// accessibility - docs/v3/01-prd.md §20 restates this principle for the
  /// UI side, applied here to the document itself).
  final PdfColor accentColor;

  /// Divider-rule color - may equal [accentColor] or a neutral, depending
  /// on the preset's mood.
  final PdfColor dividerColor;

  /// Whether section headings render in [accentColor] (a "Modern Accent"-
  /// style preset) or [inkColor] (a plain, maximum-neutrality preset).
  final bool headingUsesAccentColor;

  /// How every section heading is visually introduced - see
  /// [SectionHeadingStyle]'s own doc comment. Defaults to [SectionHeadingStyle
  /// .ruleAbove], the exact Milestone 1-era behavior, so any preset that
  /// doesn't set this explicitly renders identically to before this field
  /// existed.
  final SectionHeadingStyle sectionHeadingStyle;

  /// Whether the header block (name/contact/links - `layout/header_block.dart`)
  /// is centered on the page rather than left-aligned. A traditional
  /// letterhead-style convention, used sparingly (one or two archetypes,
  /// never the majority) since most contemporary resumes read better
  /// left-aligned.
  final bool headerCentered;

  /// Whether the resume owner's *name* specifically renders in
  /// [accentColor] - a bolder, more personal signal than
  /// [headingUsesAccentColor] (which only colors section headings),
  /// reserved for the archetype(s) whose whole identity is "more visual
  /// personality" (docs/v3/01-prd.md §8's Creative/Visual-First archetype).
  final bool nameUsesAccentColor;

  /// Whether the Skills section renders as a wrapped row of bordered tag
  /// chips (`buildChipList`, `layout/chip_list.dart`) instead of one plain
  /// comma-joined paragraph - a scannable, contemporary treatment suited to
  /// technical/visual archetypes with long skill lists; left off for
  /// archetypes whose character is specifically restrained/unadorned.
  final bool skillsAsChips;

  /// Whether a thin, full-width rule (in [dividerColor]) appears directly
  /// under the header block (post-Milestone-5 visual-quality pass) -
  /// separates the name/contact block from the first section for
  /// archetypes that don't already draw their own accent bar there (see
  /// `archetypes/modern_accent_column.dart` and its siblings, which build
  /// a bespoke accent bar outside this token and should leave this false to
  /// avoid a doubled-up rule). Fixes the previously-abrupt header-to-body
  /// transition several archetypes had with no separation at all.
  final bool headerDivider;

  /// Whether the header's contact line (email/phone/location) renders as
  /// one line per item instead of a single `" | "`-joined line
  /// (post-Milestone-5 visual-quality pass, RV3-17 in
  /// docs/v3/implementation/04-risk-register.md). Fixes a real, visually
  /// confirmed defect: a full contact line joined inline does not fit the
  /// ~140pt sidebar column width at realistic content lengths (e.g. an
  /// Indian phone number with a country code), wrapping awkwardly
  /// mid-phone-number. Reserved for the sidebar archetypes' header, which
  /// is the only header rendered at that narrow a width; every full-width
  /// header keeps the single-line format, which is both correct at that
  /// width and matches the reference bar this pass studied.
  final bool headerContactStacked;

  /// Whether a thin dashed rule (`layout/entry_block.dart`'s
  /// `buildEntryDivider`) separates consecutive entries *within* the same
  /// section (reference-driven redesign pass) - a lighter-weight
  /// organizational cue than the solid rule used between sections,
  /// reproducing a technique observed directly in the user-supplied
  /// Enhance CV reference resumes. Reserved for archetypes with enough
  /// breathing room for it to read as structure rather than clutter
  /// (mid-density, single-column archetypes); left off the tightest
  /// profiles (Compact Technical, Government Dense), the two-column
  /// archetypes (narrow columns), and Creative Visual (already carries its
  /// own accent-bar decoration - stacking a second divider treatment would
  /// contradict this pass's own instruction not to add decorative
  /// elements for their own sake).
  final bool entryDividerDashed;

  /// How every entry's structured header composes - see [EntryHeaderStyle]
  /// itself for the two options. Defaults to [EntryHeaderStyle.inline],
  /// the space-efficient convention the majority of the catalog keeps.
  final EntryHeaderStyle entryHeaderStyle;

  /// How the header block is composed - see [HeaderStyle] itself. Defaults
  /// to [HeaderStyle.plain], the exact pre-this-pass behavior.
  final HeaderStyle headerStyle;

  /// Whether the header's contact row draws a small vector glyph
  /// (`layout/contact_icons.dart`) before each phone/email/location/link
  /// item instead of plain text alone - product visual-audit pass.
  /// Reserved for the narrower-column archetypes where a glyph carries
  /// real scanning value (sidebar/rail headers) rather than applied
  /// everywhere as decoration.
  final bool headerContactIcons;

  /// Whether an entry's role/degree or its company/institution carries
  /// the bold, ink-dark visual weight - see [EntryTitleEmphasis]. Defaults
  /// to [EntryTitleEmphasis.role], the exact pre-this-pass behavior.
  final EntryTitleEmphasis entryTitleEmphasis;

  /// **Design-execution pass.** The font size an entry's secondary line
  /// (company/institution, in [EntryHeaderStyle.stacked] mode) renders at.
  /// Null (the default, every archetype's unchanged behavior) falls back
  /// to [subheadingSize] - the same size as the role/title line, only
  /// distinguished by weight and color. A real value gives company its
  /// own, smaller step in the type scale - a genuine size hierarchy
  /// between "primary" (role) and "metadata" (date/location), not just a
  /// weight difference.
  final double? companySize;

  /// How an entry's internal spacing is computed - see [EntryRhythmStyle].
  /// Defaults to [EntryRhythmStyle.standard], the exact pre-this-pass
  /// uniform-gap behavior.
  final EntryRhythmStyle entryRhythmStyle;

  /// The `lineSpacing` a bullet's own paragraph text renders with.
  /// Defaults to `1.2`, the exact value every archetype used before this
  /// pass (hard-coded in `layout/entry_block.dart` until now) - so any
  /// archetype that doesn't set this explicitly renders identically to
  /// before.
  final double bulletLineSpacing;

  /// **Design-execution pass.** The font size the header's role-tagline
  /// line renders at, in [HeaderStyle.plain] mode. Null (the default,
  /// every archetype's unchanged behavior) falls back to [subheadingSize]
  /// - the same size as an entry title, which an independent visual
  /// review judged as competing with the name rather than reading as
  /// clearly secondary to it. A real value gives the tagline its own,
  /// smaller step between the name and the body text.
  final double? headerTaglineSize;

  /// **Design-execution pass.** The vertical gap between the header's own
  /// lines (name→tagline, tagline→contact), in [HeaderStyle.plain] mode.
  /// Null (the default, every archetype's unchanged behavior) falls back
  /// to [lineGap] - the same tight gap used everywhere else on the page.
  /// A real value gives the header deliberate breathing room, so it reads
  /// as an intentional composition rather than compressed text.
  final double? headerRhythmGap;

  /// **Approved design specification pass.** The vertical gap between the
  /// tagline and the contact line specifically, distinct from
  /// [headerRhythmGap] (used between name→tagline and contact→links).
  /// Null falls back to [headerRhythmGap]. Lets the specification's
  /// asymmetric header rhythm (a smaller gap after the name, a larger one
  /// before contact) be expressed exactly, rather than one uniform value.
  final double? headerGapAfterTagline;

  /// **Design-execution pass.** Whether a [SectionHeadingStyle.ruleBelow]
  /// heading's rule renders in [accentColor] (heavier weight) instead of
  /// the neutral [dividerColor] every archetype uses by default. A
  /// functional use of color - "a new information group starts here" -
  /// rather than merely tinting text, reserved for the one archetype this
  /// pass judged needed it, not applied as a blanket color-everything
  /// change.
  final bool sectionRuleUsesAccentColor;

  /// **Approved design specification pass.** Whether the header's contact
  /// line renders with a middle-dot (" · ") separator between items
  /// instead of the plain joined line every archetype uses by default -
  /// a typographic separator instead of a raw `" | "` character. Display
  /// only: the underlying stored contact line text is unchanged.
  final bool headerContactCompactDots;

  /// **Approved design specification pass.** Whether the header's role
  /// tagline renders in italic - a real typographic signal that it is a
  /// caption to the name, not a second headline, alongside its distinct
  /// [headerTaglineSize]. Defaults to `false`, every archetype's
  /// unchanged behavior.
  final bool headerTaglineItalic;

  /// How a bullet's marker renders - see [BulletMarkerStyle]. Defaults to
  /// [BulletMarkerStyle.shape], every archetype's unchanged behavior.
  final BulletMarkerStyle bulletMarkerStyle;

  /// **Approved design specification pass.** Whether a
  /// [SectionHeadingStyle.ruleBelow] rule "hugs" the heading text's own
  /// width instead of spanning the full available column width. Computed
  /// proportionally from the heading string's length at render time
  /// (`content_line_renderer.dart`, since this package exposes no
  /// pre-layout text-measurement API) - approximate, not pixel-exact, but
  /// a deliberate short accent mark under the heading rather than a
  /// full-width table-row-style divider. Defaults to `false`, every
  /// archetype's unchanged behavior.
  final bool sectionRuleFollowsHeadingWidth;

  /// **Approved design specification pass.** Whether the Skills section
  /// renders as flowing text grouped by [SkillEntry.category] (a small,
  /// accent-colored category label followed by a dot-joined list of that
  /// category's skill names) instead of one flat comma-joined
  /// paragraph/chip row. Real, already-collected data - never a
  /// fabricated grouping. Defaults to `false`, every archetype's
  /// unchanged behavior; when `true`, takes precedence over
  /// [skillsAsChips] for the Skills section specifically.
  final bool skillsGroupedByCategory;
}
