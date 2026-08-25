import 'package:pdf/pdf.dart';

import 'resume_design_tokens.dart';
import 'resume_template_spec.dart';

/// Archetype id constants - each matches one file under
/// `template/archetypes/` and is what [ResumeTemplateRenderer]
/// (`../resume_template_renderer.dart`) dispatches on. Declared once here
/// (not duplicated as a string literal in every archetype file) so a typo
/// in one place cannot silently produce two "different" ids for what was
/// meant to be the same archetype.
abstract final class ResumeArchetypeIds {
  static const classicSingleColumn = 'classic-single-column';
  static const modernAccentColumn = 'modern-accent-column';
  static const twoColumnSidebar = 'two-column-sidebar';
  static const compactTechnical = 'compact-technical';
  static const executiveSummaryLed = 'executive-summary-led';
  static const creativeVisual = 'creative-visual';
  static const entryLevelStudent = 'entry-level-student';
  static const minimalistMonochrome = 'minimalist-monochrome';
  static const governmentDense = 'government-dense';
  static const twoColumnRight = 'two-column-right';
}

/// Token preset id constants - a color/typographic mood, applied on top of
/// each archetype's own baseline size/spacing profile (see [_tokens]).
/// **Beta scope decision (post-Milestone 4, docs/v3/implementation/03-decisions.md):**
/// still used internally by [_tokens] (the mechanism is real and worth
/// keeping for future re-expansion), but the beta catalog no longer
/// multiplies every archetype by both presets - each archetype ships with
/// exactly the one mood judged to suit its character (see [_presetFor]).
/// A warm/cool color swap alone was never a *second template*, only a
/// second coat of paint on the same one - counting it as a distinct
/// catalog entry was the "20 templates, some merely token variations"
/// problem this beta decision explicitly rejects.
abstract final class ResumeTokenPresetIds {
  static const warm = 'warm';
  static const cool = 'cool';
}

/// The static catalog of every selectable template - docs/v3/01-prd.md §8:
/// "archetypes × design-token presets, not 20 independently coded
/// documents." **Beta scope (post-Milestone 4):** 10 genuinely distinct
/// archetypes, one curated preset each - not 10 × 2 presets. Every
/// archetype in this catalog was verified structurally distinct from
/// every other one - different column layout, different content order,
/// different header treatment, or different heading rhythm, never
/// density/color alone (docs/v3/implementation/03-decisions.md records the
/// full per-archetype rationale). Mirrors [ModelCatalog]'s own "static,
/// hand-authored specs, not fetched from a remote catalog server" shape
/// (`lib/services/ai/model_catalog.dart`) - there is no server, by design.
abstract final class ResumeTemplateCatalog {
  static final List<ResumeTemplateSpec> all = [
    for (final archetype in _archetypes) _specFor(archetype),
  ];

  /// The template every pre-Milestone-1 resume/version (with a `null`
  /// `template_id`) renders with, and the fallback for an unrecognized id -
  /// docs/v3/01-prd.md §25: "default archetype = Classic Single-Column for
  /// any version saved before this milestone."
  static ResumeTemplateSpec get defaultSpec => _specFor(ResumeArchetypeIds.classicSingleColumn);

  /// Looks up a template by [ResumeTemplateSpec.id] (`'archetypeId-tokenPresetId'`).
  /// Never throws and never returns null - an unknown or missing id
  /// (including a `null` [id], the pre-Milestone-1 case, *or* a
  /// pre-beta-scope id like `'...-cool'` for an archetype whose beta
  /// preset is now `'warm'`) resolves to [defaultSpec], the same "always
  /// something sensible, never a crash" discipline `ModelCatalog.defaultFor`
  /// already applies - a resume saved against a since-retired preset
  /// combination re-renders with the default template rather than failing.
  static ResumeTemplateSpec specById(String? id) {
    if (id == null) return defaultSpec;
    for (final spec in all) {
      if (spec.id == id) return spec;
    }
    return defaultSpec;
  }

  static const _archetypes = [
    ResumeArchetypeIds.classicSingleColumn,
    ResumeArchetypeIds.modernAccentColumn,
    ResumeArchetypeIds.twoColumnSidebar,
    ResumeArchetypeIds.compactTechnical,
    ResumeArchetypeIds.executiveSummaryLed,
    ResumeArchetypeIds.creativeVisual,
    ResumeArchetypeIds.entryLevelStudent,
    ResumeArchetypeIds.minimalistMonochrome,
    ResumeArchetypeIds.governmentDense,
    ResumeArchetypeIds.twoColumnRight,
  ];

  /// The one curated mood each archetype ships with in the beta catalog -
  /// a deliberate per-archetype choice (formal/technical archetypes lean
  /// cool-slate; traditional/warm-personality archetypes lean warm-brown),
  /// not a blanket default - see docs/v3/implementation/03-decisions.md
  /// for the reasoning behind each pick.
  static String _presetFor(String archetypeId) {
    switch (archetypeId) {
      case ResumeArchetypeIds.modernAccentColumn:
      case ResumeArchetypeIds.twoColumnSidebar:
      case ResumeArchetypeIds.compactTechnical:
      case ResumeArchetypeIds.minimalistMonochrome:
      case ResumeArchetypeIds.governmentDense:
        return ResumeTokenPresetIds.cool;
      default:
        return ResumeTokenPresetIds.warm;
    }
  }

  /// The 5 archetypes exposed in the beta template selection UI (user
  /// decision, docs/v3/implementation/03-decisions.md): the strongest,
  /// most mature templates, spanning single-column and two-column, formal
  /// and contemporary. The other 5 stay fully implemented and documented
  /// (never deleted) but are hidden from selection until a future
  /// non-beta catalog expansion re-enables them.
  static const _betaEnabledArchetypes = {
    ResumeArchetypeIds.classicSingleColumn,
    ResumeArchetypeIds.modernAccentColumn,
    ResumeArchetypeIds.executiveSummaryLed,
    ResumeArchetypeIds.minimalistMonochrome,
    ResumeArchetypeIds.twoColumnRight,
  };

  /// Every template exposed in the beta template selection UI - what
  /// `ResumeTemplateGalleryScreen` should list instead of [all]. [all],
  /// [specById], and [defaultSpec] deliberately stay unfiltered so a
  /// resume/version already persisted against a disabled template (or a
  /// null/unrecognized id) keeps resolving and rendering correctly.
  static List<ResumeTemplateSpec> get enabled =>
      all.where((t) => t.isEnabledInBeta).toList(growable: false);

  static ResumeTemplateSpec _specFor(String archetypeId) {
    final presetId = _presetFor(archetypeId);
    final isEnabledInBeta = _betaEnabledArchetypes.contains(archetypeId);

    switch (archetypeId) {
      case ResumeArchetypeIds.classicSingleColumn:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Classic',
          atsConfidence: AtsConfidence.maximum,
          density: TemplateDensity.low,
          isEnabledInBeta: isEnabledInBeta,
          candidateType:
              'Conservative industries (finance, legal, government, academia) and any heavily ATS-gated pipeline.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.classic,
            headerDivider: true,
            entryDividerDashed: true,
            // Product visual-audit pass: the two full-detail Enhance CV
            // references disagree on role-vs-company emphasis (see
            // EntryTitleEmphasis's own doc comment) - Classic's own
            // identity ("conservative industries... heavily ATS-gated")
            // reads more institutionally when the employer name carries
            // the bold weight, matching how a traditional formal resume
            // foregrounds the organization.
            entryTitleEmphasis: EntryTitleEmphasis.company,
          ),
        );
      case ResumeArchetypeIds.modernAccentColumn:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Modern Accent',
          atsConfidence: AtsConfidence.maximum,
          density: TemplateDensity.low,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'General corporate/professional roles wanting polish without visual risk.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.modernAccent,
            headingUsesAccentColor: true,
            sectionHeadingStyle: SectionHeadingStyle.ruleBelow,
            entryDividerDashed: true,
            // Product visual-audit pass, P0 finding: this was the
            // archetype's whole "modern/accent" identity reduced to a
            // single thin rule under the header - the audit's studied
            // references use a genuine solid color block as their
            // strongest visual anchor. Upgraded to a real color-band
            // header (see archetypes/modern_accent_column.dart, which
            // drops its own now-redundant thin accent bar when this is
            // set) plus icon-prefixed contact items, which read cleanly
            // against the filled band.
            headerStyle: HeaderStyle.colorBand,
            headerContactIcons: true,
            // Product Phase 3: skills as scannable accent chips instead of
            // a comma-joined line - a real display-architecture difference
            // from Classic's plain list, not just the color-band header.
            skillsAsChips: true,
          ),
        );
      case ResumeArchetypeIds.twoColumnSidebar:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Two-Column Sidebar',
          atsConfidence: AtsConfidence.high,
          density: TemplateDensity.medium,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Tech, marketing, and design-adjacent roles wanting a contemporary look.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.twoColumn,
            sectionHeadingStyle: SectionHeadingStyle.ruleBelow,
            skillsAsChips: true,
            headerContactStacked: true,
            // Product visual-audit pass: a stacked, narrow-column contact
            // block is exactly where a small glyph earns its keep -
            // scanning a one-item-per-line list is faster with a leading
            // icon than parsing plain text alone.
            headerContactIcons: true,
          ),
        );
      case ResumeArchetypeIds.compactTechnical:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Compact Technical',
          atsConfidence: AtsConfidence.maximum,
          density: TemplateDensity.high,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Technical/engineering roles with long project and skill lists.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.compactTechnical,
            sectionHeadingStyle: SectionHeadingStyle.label,
            skillsAsChips: true,
            headerDivider: true,
          ),
        );
      case ResumeArchetypeIds.executiveSummaryLed:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Executive Summary-Led',
          atsConfidence: AtsConfidence.maximum,
          density: TemplateDensity.low,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Senior/leadership candidates who want core skills read before the '
              'chronological history.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.classic,
            headingUsesAccentColor: true,
            sectionHeadingStyle: SectionHeadingStyle.centeredFlanked,
            headerCentered: true,
            entryDividerDashed: true,
            entryHeaderStyle: EntryHeaderStyle.stacked,
            // Product visual-audit pass: the pill treatment (role tagline
            // in a filled accent badge under the centered name) matches
            // this archetype's already-formal, letterhead-style
            // presentation - a considered accent, not a full color block,
            // since the rest of this archetype stays deliberately
            // restrained (docs/v3/01-prd.md's "senior/leadership
            // candidate" character).
            headerStyle: HeaderStyle.pill,
            // Product-quality remediation pass, Part C (D-M9-02): the
            // content-plan builder's own groupSkillsByCategory flag (set
            // in executive_summary_led.dart) only decides which lines get
            // built - this token is what content_line_renderer.dart's
            // paragraph case actually checks to render them as labeled
            // category groups (buildSkillCategoryGroup) instead of one
            // flat comma-joined line. Both halves are required; missing
            // this token was confirmed, by direct visual PDF inspection,
            // to leave the Skills section completely unchanged despite
            // the content-plan-side flag being set.
            skillsGroupedByCategory: true,
          ),
        );
      case ResumeArchetypeIds.creativeVisual:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Creative Visual',
          atsConfidence: AtsConfidence.high,
          density: TemplateDensity.low,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Design/creative/marketing roles wanting more visual personality.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.modernAccent,
            headingUsesAccentColor: true,
            sectionHeadingStyle: SectionHeadingStyle.label,
            nameUsesAccentColor: true,
            skillsAsChips: true,
            // Product visual-audit pass: this archetype's whole reason to
            // exist is "more visual personality" - the color-band header
            // is its second, distinct masthead treatment (a different
            // accent hue than Modern Accent's, since this archetype's
            // preset is warm/terracotta against Modern Accent's cool/
            // steel-blue), so the two color-block archetypes never read
            // as duplicates of each other.
            headerStyle: HeaderStyle.colorBand,
          ),
        );
      case ResumeArchetypeIds.entryLevelStudent:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Entry-Level / Student',
          atsConfidence: AtsConfidence.maximum,
          density: TemplateDensity.low,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Students and recent graduates whose education is more relevant than a '
              'thin work history.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.classic,
            sectionHeadingStyle: SectionHeadingStyle.ruleBelow,
            headerDivider: true,
            entryDividerDashed: true,
          ),
        );
      case ResumeArchetypeIds.minimalistMonochrome:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Minimalist Monochrome',
          atsConfidence: AtsConfidence.maximum,
          density: TemplateDensity.low,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Any candidate wanting the most restrained, understated presentation.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.minimalist,
            sectionHeadingStyle: SectionHeadingStyle.label,
            headerDivider: true,
            entryDividerDashed: true,
          ),
        );
      case ResumeArchetypeIds.governmentDense:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Government / Public-Sector Dense',
          atsConfidence: AtsConfidence.maximum,
          density: TemplateDensity.high,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Government/public-sector applications expecting a long, detailed, '
              'formally-structured history.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.governmentDense,
            sectionHeadingStyle: SectionHeadingStyle.centeredFlanked,
            headerCentered: true,
            entryHeaderStyle: EntryHeaderStyle.stacked,
            // Product visual-audit pass: same institutional reasoning as
            // Classic - a government/public-sector application reads more
            // formally correct with the employing agency/organization
            // carrying the bold weight over the individual's own title.
            entryTitleEmphasis: EntryTitleEmphasis.company,
          ),
        );
      case ResumeArchetypeIds.twoColumnRight:
        return ResumeTemplateSpec(
          archetypeId: archetypeId,
          tokenPresetId: presetId,
          displayName: 'Balanced Two-Column',
          atsConfidence: AtsConfidence.high,
          density: TemplateDensity.medium,
          isEnabledInBeta: isEnabledInBeta,
          candidateType: 'Candidates with a full credential set (education, certifications, skills) '
              'wanting a dense reference rail beside their chronological history.',
          tokens: _tokens(
            preset: presetId,
            base: _DensityProfiles.balancedTwoColumn,
            sectionHeadingStyle: SectionHeadingStyle.ruleBelow,
            // Approved design specification pass: bordered skill chips
            // named explicitly in the independent review as reading
            // "like default UI controls" - replaced entirely by
            // skillsGroupedByCategory's flowing, labeled text below.
            skillsAsChips: false,
            headingUsesAccentColor: true,
            headerContactStacked: false,
            // Approved design specification: role+date share one row,
            // company+location share a quiet second row - see
            // EntryHeaderStyle.editorial's own doc comment.
            entryHeaderStyle: EntryHeaderStyle.editorial,
            // Removed per the approved specification: icon glyphs
            // competed with the name for "first thing you notice" on the
            // header's one dominant line. headerContactCompactDots below
            // replaces them with a quiet typographic separator instead.
            headerContactIcons: false,
            headerContactCompactDots: true,
            // Role title (12.5, subheadingSize) vs. company (10) vs.
            // date/location (9, captionSize) - the specification's exact
            // 3-level hierarchy.
            companySize: 10,
            entryRhythmStyle: EntryRhythmStyle.editorial,
            // Final visual-polish pass, point #3: nudged 1.45→1.5 - long
            // bullets still felt slightly dense per the review. A small,
            // deliberate increase, not a page-inflating one (worth ~1-2pt
            // per multi-line bullet).
            bulletLineSpacing: 1.5,
            // Literal "–" dash marker (entry_block.dart's hand-composed
            // bullet), never the default filled-shape marker, and never
            // justified text - see buildEntryBlock's own doc comment for
            // why justified text in a narrow column was judged a likely
            // root cause of "feels machine-generated."
            bulletMarkerStyle: BulletMarkerStyle.dash,
            // Tagline's own step in the scale (12.5, between name and
            // body), italic - a caption to the name, not a second
            // headline.
            headerTaglineSize: 12.5,
            headerTaglineItalic: true,
            // The specification's asymmetric header rhythm: a smaller
            // gap after the name (6pt), a larger one before contact
            // (8pt) - two distinct bands, not one uniform gap.
            headerRhythmGap: 6,
            headerGapAfterTagline: 8,
            // A short, heading-width accent rule - "a new group starts
            // here," not a full-width table-row-style divider.
            sectionRuleUsesAccentColor: true,
            sectionRuleFollowsHeadingWidth: true,
            // Real, already-collected SkillEntry.category data, surfaced
            // as a labeled flowing-text group instead of one flat list -
            // never a fabricated grouping.
            skillsGroupedByCategory: true,
          ),
        );
      default:
        throw ArgumentError('Unknown archetype id: $archetypeId');
    }
  }

  static ResumeDesignTokens _tokens({
    required String preset,
    required _DensityProfile base,
    bool headingUsesAccentColor = false,
    SectionHeadingStyle sectionHeadingStyle = SectionHeadingStyle.ruleAbove,
    bool headerCentered = false,
    bool nameUsesAccentColor = false,
    bool skillsAsChips = false,
    bool headerDivider = false,
    bool headerContactStacked = false,
    bool entryDividerDashed = false,
    EntryHeaderStyle entryHeaderStyle = EntryHeaderStyle.inline,
    HeaderStyle headerStyle = HeaderStyle.plain,
    bool headerContactIcons = false,
    EntryTitleEmphasis entryTitleEmphasis = EntryTitleEmphasis.role,
    double? companySize,
    EntryRhythmStyle entryRhythmStyle = EntryRhythmStyle.standard,
    double bulletLineSpacing = 1.2,
    double? headerTaglineSize,
    double? headerRhythmGap,
    bool sectionRuleUsesAccentColor = false,
    bool headerContactCompactDots = false,
    bool headerTaglineItalic = false,
    double? headerGapAfterTagline,
    bool sectionRuleFollowsHeadingWidth = false,
    BulletMarkerStyle bulletMarkerStyle = BulletMarkerStyle.shape,
    bool skillsGroupedByCategory = false,
  }) {
    final isWarm = preset == ResumeTokenPresetIds.warm;
    return ResumeDesignTokens(
      nameSize: base.nameSize,
      headingSize: base.headingSize,
      subheadingSize: base.subheadingSize,
      bodySize: base.bodySize,
      captionSize: base.captionSize,
      pageMargin: base.pageMargin,
      sectionGap: base.sectionGap,
      entryGap: base.entryGap,
      lineGap: base.lineGap,
      inkColor: isWarm ? _WarmPalette.ink : _CoolPalette.ink,
      inkSoftColor: isWarm ? _WarmPalette.inkSoft : _CoolPalette.inkSoft,
      accentColor: isWarm ? _WarmPalette.accent : _CoolPalette.accent,
      dividerColor: isWarm ? _WarmPalette.divider : _CoolPalette.divider,
      headingUsesAccentColor: headingUsesAccentColor,
      sectionHeadingStyle: sectionHeadingStyle,
      headerCentered: headerCentered,
      nameUsesAccentColor: nameUsesAccentColor,
      skillsAsChips: skillsAsChips,
      headerDivider: headerDivider,
      headerContactStacked: headerContactStacked,
      entryDividerDashed: entryDividerDashed,
      entryHeaderStyle: entryHeaderStyle,
      headerStyle: headerStyle,
      headerContactIcons: headerContactIcons,
      entryTitleEmphasis: entryTitleEmphasis,
      companySize: companySize,
      entryRhythmStyle: entryRhythmStyle,
      bulletLineSpacing: bulletLineSpacing,
      headerTaglineSize: headerTaglineSize,
      headerRhythmGap: headerRhythmGap,
      sectionRuleUsesAccentColor: sectionRuleUsesAccentColor,
      headerContactCompactDots: headerContactCompactDots,
      headerTaglineItalic: headerTaglineItalic,
      headerGapAfterTagline: headerGapAfterTagline,
      sectionRuleFollowsHeadingWidth: sectionRuleFollowsHeadingWidth,
      bulletMarkerStyle: bulletMarkerStyle,
      skillsGroupedByCategory: skillsGroupedByCategory,
    );
  }
}

/// Per-archetype baseline size/spacing profile - what actually makes
/// "Compact Technical" denser than "Classic," independent of which color
/// preset is applied on top of it.
class _DensityProfile {
  const _DensityProfile({
    required this.nameSize,
    required this.headingSize,
    required this.subheadingSize,
    required this.bodySize,
    required this.captionSize,
    required this.pageMargin,
    required this.sectionGap,
    required this.entryGap,
    required this.lineGap,
  });

  final double nameSize;
  final double headingSize;
  final double subheadingSize;
  final double bodySize;
  final double captionSize;
  final double pageMargin;
  final double sectionGap;
  final double entryGap;
  final double lineGap;
}

abstract final class _DensityProfiles {
  // Post-Milestone-5 visual-quality pass: every profile's rhythm values
  // (sectionGap/entryGap/lineGap) were increased moderately across the
  // board - a genuine code-level fix for the "large, accidental-looking
  // empty area at the bottom of a moderate-length resume" finding
  // (RV3-10, docs/v3/implementation/04-risk-register.md), not a cosmetic
  // tweak: the same content breathes more deliberately and fills more of
  // the page, reading as an intentional, considered layout instead of
  // sparse/unfinished. Relative density ordering between profiles
  // (compactTechnical/governmentDense tightest, minimalist most generous)
  // is preserved throughout - only the absolute values moved.
  static const classic = _DensityProfile(
    nameSize: 25,
    headingSize: 14,
    subheadingSize: 11,
    bodySize: 10,
    captionSize: 9,
    pageMargin: 34,
    sectionGap: 18,
    entryGap: 13,
    lineGap: 4,
  );

  static const modernAccent = _DensityProfile(
    nameSize: 27,
    headingSize: 13,
    subheadingSize: 11,
    bodySize: 10,
    captionSize: 9,
    pageMargin: 34,
    sectionGap: 18,
    entryGap: 13,
    lineGap: 4,
  );

  static const twoColumn = _DensityProfile(
    nameSize: 22,
    headingSize: 12,
    subheadingSize: 10.5,
    bodySize: 9.5,
    captionSize: 9,
    pageMargin: 24,
    sectionGap: 14,
    entryGap: 10,
    lineGap: 3,
  );

  /// Balanced Two-Column's own profile - **approved design specification
  /// pass**. Deliberately NOT the same object as [twoColumn] (still used,
  /// unchanged, by Two-Column Sidebar). Every value here is taken
  /// directly from the approved visual design specification's hierarchy
  /// table (name/heading/subheading/body/caption sizes, page margin,
  /// section/entry gap) - not tuned incrementally from the prior round,
  /// but replaced with the spec's own literal numbers. `subheadingSize`
  /// (12.5) is the spec's ROLE TITLE size; `companySize` (set separately
  /// in this archetype's catalog entry, 10) is the spec's COMPANY size;
  /// `captionSize` (9) is the spec's DATE/LOCATION/CONTACT size - a real
  /// 3-step hierarchy, not two sizes differentiated by weight alone.
  /// [entryGap] nudged 16→18 in the final visual-polish pass, per
  /// point #1 ("each experience must immediately read as an individual
  /// career milestone... use whitespace and typography hierarchy rather
  /// than divider lines") - a small, deliberate increase to job-to-job
  /// separation specifically, not a blanket spacing increase (every
  /// other tier - micro/small/medium/section - is unchanged from the
  /// approved specification).
  static const balancedTwoColumn = _DensityProfile(
    nameSize: 32,
    headingSize: 12,
    subheadingSize: 12.5,
    bodySize: 10,
    captionSize: 9,
    pageMargin: 28,
    sectionGap: 24,
    entryGap: 18,
    // Nudged 4→5 in the final visual-polish pass, point #4 - a touch more
    // presence in the gap between a section heading's text and its own
    // rule (content_line_renderer.dart's ruleBelow case), refining the
    // heading's spacing rather than its size.
    lineGap: 5,
  );

  static const compactTechnical = _DensityProfile(
    nameSize: 20,
    headingSize: 12,
    subheadingSize: 10,
    bodySize: 9,
    captionSize: 9,
    pageMargin: 28,
    sectionGap: 11,
    entryGap: 7,
    lineGap: 2.5,
  );

  /// The most generous whitespace of any profile, matching Minimalist
  /// Monochrome's "most restrained" character.
  static const minimalist = _DensityProfile(
    nameSize: 23,
    headingSize: 13,
    subheadingSize: 10.5,
    bodySize: 10,
    captionSize: 9,
    pageMargin: 38,
    sectionGap: 20,
    entryGap: 15,
    lineGap: 4.5,
  );

  /// Denser than Compact Technical, the tightest profile in the catalog,
  /// built to hold a long formal chronological history.
  static const governmentDense = _DensityProfile(
    nameSize: 19,
    headingSize: 11,
    subheadingSize: 9.5,
    bodySize: 9,
    captionSize: 9,
    pageMargin: 26,
    sectionGap: 9,
    entryGap: 6,
    lineGap: 2.2,
  );
}

/// Warm color mood: dark warm-brown ink, terracotta accent.
abstract final class _WarmPalette {
  static const ink = PdfColor.fromInt(0xFF2A2620);
  static const inkSoft = PdfColor.fromInt(0xFF6B6156);
  static const accent = PdfColor.fromInt(0xFFB5562E);
  static const divider = PdfColor.fromInt(0xFFD8CFC2);
}

/// Cool color mood: dark slate ink, steel-blue accent.
abstract final class _CoolPalette {
  static const ink = PdfColor.fromInt(0xFF1E2530);
  static const inkSoft = PdfColor.fromInt(0xFF5B6675);
  static const accent = PdfColor.fromInt(0xFF2E6F8E);
  static const divider = PdfColor.fromInt(0xFFC9D3DC);
}
