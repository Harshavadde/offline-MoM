import '../../models/certification_block.dart';
import '../../models/custom_section_block.dart';
import '../../models/education_block.dart';
import '../../models/experience_block.dart';
import '../../models/project_block.dart';
import '../../models/resume_link.dart';
import '../../models/skill_entry.dart';
import 'resume_import_completeness.dart';

/// The result of [ResumeImportParser.parse] - a purely in-memory, unsaved
/// draft. Deliberately built from the *existing* library block models
/// (`ExperienceBlock`, `EducationBlock`, `ProjectBlock`, `CertificationBlock`,
/// `SkillEntry`, each with `id: null`) rather than a parallel set of DTOs -
/// per Batch 7's own structural rule ("adapt imported content into the
/// existing Resume system"), the parser's job is only to decide *which*
/// existing model each detected block belongs in, never to define a new
/// shape for imported data to live in.
///
/// Every field here is either directly present in the source document or
/// left null/absent - nothing is fabricated. [unclassifiedText] is the
/// "safe review area" Batch 7 requires: content the parser found but could
/// not confidently turn into a structured field lands here, always visible
/// to the user, never silently dropped and never forced into a required
/// field with an invented placeholder value.
class ParsedResumeDraft {
  const ParsedResumeDraft({
    this.fullName,
    this.email,
    this.phone,
    this.location,
    this.links = const [],
    this.experience = const [],
    this.education = const [],
    this.projects = const [],
    this.certifications = const [],
    this.skills = const [],
    this.customSections = const [],
    this.unclassifiedText = const [],
    this.warnings = const [],
    this.completeness = ResumeImportCompletenessReport.empty,
  });

  final String? fullName;
  final String? email;
  final String? phone;
  final String? location;
  final List<ResumeLink> links;
  final List<ExperienceBlock> experience;
  final List<EducationBlock> education;
  final List<ProjectBlock> projects;
  final List<CertificationBlock> certifications;
  final List<SkillEntry> skills;

  /// Sections the parser found a genuine header for (see
  /// [ResumeImportParser]'s own doc comment on generic-header detection)
  /// but that don't fit any of the five typed slots above - Awards,
  /// Publications, Volunteer Experience, Languages, etc. Beta data-fidelity
  /// requirement (docs/v3/implementation/03-decisions.md): preserved as a
  /// real, titled section rather than merged into whatever section came
  /// before it or silently dropped. Title text is exactly what was found -
  /// never invented, never normalized against a fixed list of known names.
  final List<CustomSectionBlock> customSections;

  /// Raw text the parser found but could not confidently classify -
  /// including whole entries whose required fields (e.g. an Experience
  /// entry's role/company/start date) could not all be determined, and
  /// sections this app has no structured field for at all (e.g. a
  /// Summary/Objective paragraph - `Resume`/`ResumeSnapshot` have no
  /// free-text summary field, see this batch's own final report for why
  /// that isn't added here).
  final List<String> unclassifiedText;

  /// Human-readable notes about what the parser did or couldn't do (e.g.
  /// "No resume sections were detected" or "The Experience section was
  /// found but its entries could not be automatically structured") - shown
  /// on the review screen, never silently swallowed.
  final List<String> warnings;

  /// Machine-checkable evidence that this draft accounts for everything
  /// [ResumeImportParser.parse] found in the source document - see
  /// [ResumeImportCompletenessReport]'s own doc comment. Defaults to
  /// [ResumeImportCompletenessReport.empty] (vacuously complete) so every
  /// existing direct `ParsedResumeDraft(...)` test fixture that predates
  /// this field keeps compiling unchanged; a draft actually produced by
  /// [ResumeImportParser.parse] always carries a real, populated report.
  final ResumeImportCompletenessReport completeness;

  /// Milestone 4 (docs/v3/01-prd.md §10/§25) - lets the import review
  /// screen correct or remove an individual misclassified entry before
  /// commit, replacing just one list at a time, without needing to
  /// reconstruct every other field. Every list here replaces wholesale
  /// (never merges) when supplied - the same convention every other
  /// `copyWith` in this codebase already follows.
  ParsedResumeDraft copyWith({
    List<ExperienceBlock>? experience,
    List<EducationBlock>? education,
    List<ProjectBlock>? projects,
    List<CertificationBlock>? certifications,
    List<SkillEntry>? skills,
    List<CustomSectionBlock>? customSections,
    List<String>? unclassifiedText,
  }) {
    return ParsedResumeDraft(
      fullName: fullName,
      email: email,
      phone: phone,
      location: location,
      links: links,
      experience: experience ?? this.experience,
      education: education ?? this.education,
      projects: projects ?? this.projects,
      certifications: certifications ?? this.certifications,
      skills: skills ?? this.skills,
      customSections: customSections ?? this.customSections,
      unclassifiedText: unclassifiedText ?? this.unclassifiedText,
      warnings: warnings,
      completeness: completeness,
    );
  }

  bool get hasAnyStructuredContent =>
      fullName != null ||
      email != null ||
      phone != null ||
      location != null ||
      links.isNotEmpty ||
      experience.isNotEmpty ||
      education.isNotEmpty ||
      projects.isNotEmpty ||
      certifications.isNotEmpty ||
      skills.isNotEmpty ||
      customSections.isNotEmpty;
}

enum _SectionKind { summary, experience, education, projects, certifications, skills }

final Map<_SectionKind, Set<String>> _sectionKeywords = {
  _SectionKind.summary: {
    'summary',
    'profile',
    'objective',
    'about',
    'about me',
    'professional summary',
    'career objective',
    'career summary',
  },
  _SectionKind.experience: {
    'experience',
    'work experience',
    'employment',
    'employment history',
    'professional experience',
    'work history',
    'relevant experience',
  },
  _SectionKind.education: {
    'education',
    'academic background',
    'academic history',
    'educational background',
  },
  _SectionKind.projects: {
    'projects',
    'personal projects',
    'key projects',
    'academic projects',
  },
  _SectionKind.certifications: {
    'certifications',
    'certificates',
    'licenses',
    'licenses and certifications',
    'licenses & certifications',
    'certifications and licenses',
  },
  _SectionKind.skills: {
    'skills',
    'technical skills',
    'core competencies',
    'competencies',
    'key skills',
    'skills and interests',
    // Real-device beta fix: "SKILLS SUMMARY" (found on a real resume) was
    // previously unrecognized, so it fell through to a generic custom
    // section - individual skills preserved as raw text, but not as real
    // Skills entries the JD-tailoring pipeline's deterministic matcher
    // actually reads. "Skills Summary" and "Summary of Skills" are common
    // enough header phrasings to add deliberately, not guessed broadly.
    'skills summary',
    'summary of skills',
  },
};

final _bulletPattern = RegExp(r'^[-*•▪●‣>]\s+|^\d+[.)]\s+');
final _emailPattern = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

/// Deliberately shaped like an actual phone number (a 3-3-4 or similar
/// digit grouping, optionally parenthesized/hyphenated/dotted, optionally
/// with a country-code prefix) rather than "any digit-heavy run" - a loose
/// pattern like that would also match a plain year range such as
/// "2020 - 2021" inside an Experience entry, misreading a date as contact
/// information. This shape requires at least 10 digits split 3-3-4 (or
/// close), which a 4-4-digit year range can never satisfy.
final _phonePattern =
    RegExp(r'(\+\d{1,3}[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b');
/// Real-device beta fix: a real resume's header contact line included a
/// bare "github.com/Harshavadde" with no "http(s)://" or "www." prefix -
/// a common real-world resume convention that this pattern previously
/// never matched at all, so the link was silently absent from the
/// imported/rendered resume even though LinkedIn (which did carry a
/// "www." prefix on the same line) was preserved. Deliberately scoped to
/// a fixed set of professional-profile domains this file recognizes by
/// name in [_labelForUrl] - never a generic bare-domain match, which
/// would risk matching ordinary prose ("see our company.com page") as a
/// link. Reliability-overhaul pass: extended beyond the original GitHub/
/// GitLab/LinkedIn/Twitter set to the other profile-hosting domains
/// resumes commonly cite bare (no "http(s)://"/"www." prefix) - Stack
/// Overflow, LeetCode, Medium, HackerRank, Behance, Dribbble - the same
/// "a real, common resume convention, not a guess" bar the original
/// GitHub fix used.
final _urlPattern = RegExp(
  r'(https?://[^\s,;()]+|www\.[^\s,;()]+|'
  r'(?:github|gitlab|linkedin|twitter|x|stackoverflow|leetcode|medium|'
  r'hackerrank|behance|dribbble)\.com/[^\s,;()]+)',
  caseSensitive: false,
);
final _namePattern = RegExp(r"^[A-Z][A-Za-z.'-]+(\s+[A-Z][A-Za-z.'-]+){1,3}$");

/// Optional leading month name/abbreviation on either side of a date range
/// ("December 2025", "Aug." 2020") - real-device beta fix: the original
/// [_dateRangePattern] only ever recognized a bare "YYYY" year, so any
/// resume using "Month YYYY" (a very common format, including the one that
/// exposed this bug) never matched at all, which is what let an entire
/// Experience/Education entry fall through to [ParsedResumeDraft.unclassifiedText]
/// - see [_findDateRangeInBlock]'s own doc comment for the full chain.
const _monthNamePrefix =
    r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+';

/// Group 1 = start year (bare digits, any leading month name excluded from
/// the group). Group 2 = "present"/"current"/"now" if that's how the range
/// ends, otherwise null. Group 3 = end year (bare digits) if a year ended
/// the range instead. Kept as three separate groups - rather than one
/// combined "present|current|now|month+year" group - specifically so the
/// end year is never accidentally captured *with* its month name attached
/// (a real bug caught by this fix's own regression tests: "June 2024"
/// captured whole would have been stored as the literal endDate string
/// instead of "2024").
final _dateRangePattern = RegExp(
  '\\b(?:$_monthNamePrefix)?((?:19|20)\\d{2})\\b\\s*(?:[-–—]{1,2}|to)\\s*'
  '(?:(present|current|now)|(?:$_monthNamePrefix)?((?:19|20)\\d{2}))\\b',
  caseSensitive: false,
);

/// Physical-Mobile-First Validation phase: [ParsedResumeDraft.location]
/// previously had no producer logic anywhere in this file - a candidate's
/// "City, ST" line fell straight into [ParsedResumeDraft.unclassifiedText]
/// like any other unrecognized preamble content. Deliberately narrow, the
/// same "never guess" bar every other pattern in this file holds itself
/// to: "City Name, XX" (a comma followed by exactly two uppercase
/// letters - the near-universal US resume convention, matching this
/// codebase's own test fixtures throughout), with an optional trailing
/// ZIP code.
final _locationPattern = RegExp(r"^[A-Z][A-Za-z.'’\- ]*,\s*[A-Z]{2}(\s+\d{5}(-\d{4})?)?$");

/// Real-device beta fix: a real resume's "Hyderabad, Telangana" location
/// line matched neither [_locationPattern] (no 2-letter code - India has
/// no equivalent convention) nor anything else, and was silently absent
/// from the imported resume. [_locationPattern] intentionally stays
/// narrow (a bare 2-letter code after a comma is unambiguous), so a
/// second, equally deliberate pattern recognizes "City, State[, Country]"
/// against a **curated, closed list** of India's states/union territories
/// plus a small set of countries commonly written directly after a city
/// on a resume header - never a generic "any capitalized word after a
/// comma" match, which would risk misreading something like "Bachelor of
/// Science, Electrical Engineering" as a location. Extending this list to
/// every country/region in the world is a real, disclosed limitation, not
/// silently pretended solved - anything outside this list still falls
/// through to [ParsedResumeDraft.unclassifiedText] for manual review,
/// exactly as before.
const _indianStatesAndUnionTerritories = [
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat',
  'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh',
  'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan',
  'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
  'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Puducherry', 'Chandigarh',
];
const _commonResumeCountryNames = [
  'India', 'United States', 'USA', 'United Kingdom', 'UK', 'Canada', 'Australia', 'Singapore',
  'United Arab Emirates', 'UAE',
];

final _locationNamedRegionPattern = RegExp(
  '^[A-Z][A-Za-z.\'’\\- ]*,\\s*'
  '(?:${[..._indianStatesAndUnionTerritories, ..._commonResumeCountryNames].join('|')})'
  '(?:,\\s*(?:${_commonResumeCountryNames.join('|')}))?\$',
);

/// The result of [ResumeImportParser._splitIntoSubProjects] - a role's own
/// top-level bullets, separated from any distinct named sub-projects
/// nested under it.
class _SplitExperienceContent {
  const _SplitExperienceContent({required this.mainBullets, required this.subProjects});
  final List<String> mainBullets;
  final List<ExperienceSubProject> subProjects;
}

/// A date range found within one line of an Experience/Education block,
/// plus exactly where in that line it was found - see
/// [ResumeImportParser._findDateRangeInBlock].
class _BlockDateMatch {
  const _BlockDateMatch({
    required this.line,
    required this.matchStart,
    required this.matchEnd,
    required this.startDate,
    required this.endDate,
  });

  final String line;
  final int matchStart;
  final int matchEnd;
  final String startDate;
  final String? endDate;
}

/// Turns raw, already-extracted plain text (from any of the four supported
/// formats - the format itself doesn't matter past this point, since every
/// `DocumentTextExtractionService` implementation already normalizes its
/// format down to plain text) into a [ParsedResumeDraft].
///
/// Pure and offline by construction: a single-pass, deterministic,
/// keyword/regex-based heuristic over a `String` - no I/O, no AI model, no
/// network call of any kind. It cannot "hallucinate" a fact the way an LLM
/// could; the only failure mode it has is mis-classifying real text into
/// the wrong bucket, which [ParsedResumeDraft.unclassifiedText] and
/// [ParsedResumeDraft.warnings] exist to make visible and reviewable
/// rather than silent.
class ResumeImportParser {
  const ResumeImportParser();

  ParsedResumeDraft parse(String rawText) {
    final lines = rawText.split(RegExp(r'\r\n|\r|\n'));

    final preamble = <String>[];
    final sectionLines = <_SectionKind, List<String>>{};
    // First-seen order of custom (unrecognized-but-header-shaped) section
    // titles, plus the raw lines found under each - see this method's own
    // "generic-header detection" comment below for why this only starts
    // once the first *known* header has already been found, never inside
    // the preamble.
    final customSectionOrder = <String>[];
    final customSectionLines = <String, List<String>>{};
    _SectionKind? currentKnown;
    String? currentCustom;
    var anyHeaderFound = false;
    var pastFirstKnownHeader = false;

    for (final rawLine in lines) {
      final kind = _matchHeader(rawLine);
      if (kind != null) {
        currentKnown = kind;
        currentCustom = null;
        anyHeaderFound = true;
        pastFirstKnownHeader = true;
        continue;
      }

      // Generic-header detection (beta data-fidelity requirement,
      // docs/v3/implementation/03-decisions.md): a line that looks exactly
      // like a section header (short, title-case or all-caps, no sentence
      // punctuation - see [_looksLikeGenericSectionHeader]) but doesn't
      // match any known keyword starts a *new*, real, titled section
      // instead of being silently absorbed into whatever section came
      // before it. Deliberately gated on [pastFirstKnownHeader] - applying
      // this heuristic to the preamble would misread the candidate's own
      // name (also short and title-case) as a bogus section header before
      // [_detectName] ever gets a chance to see it. Every real resume this
      // parser has been built against opens with a *known* section
      // (Summary/Experience/Education/Skills), so an unrecognized section
      // appearing before any known one is not a case this heuristic needs
      // to cover to fix the reported bug (unknown sections *between* or
      // *after* known ones being merged/lost).
      final trimmed = rawLine.trim();
      if (pastFirstKnownHeader && _looksLikeGenericSectionHeader(trimmed)) {
        currentKnown = null;
        currentCustom = trimmed;
        anyHeaderFound = true;
        if (!customSectionLines.containsKey(trimmed)) {
          customSectionOrder.add(trimmed);
          customSectionLines[trimmed] = [];
        }
        continue;
      }

      if (currentCustom != null) {
        customSectionLines[currentCustom]!.add(rawLine);
      } else if (currentKnown == null) {
        preamble.add(rawLine);
      } else {
        sectionLines.putIfAbsent(currentKnown, () => []).add(rawLine);
      }
    }

    final email = _emailPattern.firstMatch(rawText)?.group(0);
    // Phone detection is deliberately scoped to the preamble (before the
    // first recognized section header, where contact info actually lives)
    // rather than the whole document - the phone pattern's digit grouping
    // is specific enough to avoid matching a date range, but scoping it
    // narrowly is still a cheap extra safeguard against a coincidental
    // 10-digit run appearing somewhere in Experience/Education content.
    final phone = _phonePattern.firstMatch(preamble.join('\n'))?.group(0)?.trim();
    // Real-device beta fix: previously scanned the *whole* document, so a
    // project's own repo link ("GitHub: github.com/x/y" under a Projects
    // entry - already captured separately as that project's own `link`
    // field by `_parseProjects`) was *also* added here and rendered a
    // second time in the header as if it were a personal profile link -
    // confirmed by direct visual PDF inspection of a real resume showing
    // "GitHub: ..." twice. Scoped to the preamble only, the same
    // reasoning [phone] above already uses: personal profile links
    // (LinkedIn/GitHub/portfolio) live in the header, not inside a
    // project or certification's own body text.
    final links = _extractLinks(preamble.join('\n'));

    final fullName = _detectName(preamble, email, phone);
    final location = _detectLocation(preamble, fullName, email, phone);

    final unclassified = <String>[];
    final warnings = <String>[];

    // Part I (import completeness stress-testing pass): a segment is
    // "accounted for" if it's the whole line's name/email/phone/location,
    // or a bare link - the exact same exact-match rules the loop below
    // already applies to a whole line, reused per-"|"-segment.
    bool segmentAccountedFor(String segment) {
      final candidate = segment.trim();
      if (candidate.isEmpty) return true;
      if (candidate == fullName) return true;
      if (email != null && candidate == email) return true;
      if (phone != null && candidate == phone.trim()) return true;
      if (candidate == location) return true;
      if (_urlPattern.hasMatch(candidate) && _urlPattern.stringMatch(candidate) == candidate) return true;
      return false;
    }

    for (final line in preamble) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == fullName) continue;
      if (email != null && trimmed == email) continue;
      if (phone != null && trimmed == phone.trim()) continue;
      if (trimmed == location) continue;
      if (_urlPattern.hasMatch(trimmed) && _urlPattern.stringMatch(trimmed) == trimmed) continue;
      // Real-device finding (Part I stress-testing, confirmed reproducible
      // with this codebase's own existing Harshavardhan header fixture): a
      // single "|"-joined contact line ("City, ST | email | phone |
      // link") - this app's own documented common real-resume layout, see
      // _detectLocation's own comment - has every one of its parts
      // individually extracted above, but none of the whole-line checks
      // above ever match a *combined* line, so the entire already-fully-
      // captured line was previously flagged as still needing manual
      // review a second time. Only skip it when EVERY "|"-segment was
      // independently accounted for - a line with a genuinely unrecognized
      // segment alongside recognized ones still falls through to
      // unclassifiedText below, unchanged.
      if (trimmed.contains('|') && trimmed.split('|').every(segmentAccountedFor)) continue;
      unclassified.add(trimmed);
    }

    final experience = _parseExperience(sectionLines[_SectionKind.experience], unclassified, warnings);
    final education = _parseEducation(sectionLines[_SectionKind.education], unclassified, warnings);
    final projects = _parseProjects(sectionLines[_SectionKind.projects], unclassified, warnings);
    final certifications =
        _parseCertifications(sectionLines[_SectionKind.certifications], unclassified, warnings);
    final skillsResult = _parseSkills(sectionLines[_SectionKind.skills], unclassified);
    final skills = skillsResult.skills;
    final customSections = _parseCustomSections(customSectionOrder, customSectionLines);

    // Physical-Mobile-First Validation phase: a Summary/Objective section
    // previously had no dedicated field, so its text was placed in
    // unclassifiedText with a warning telling the user to copy it in
    // manually - confirmImport never persists unclassifiedText, so in
    // practice the summary was silently lost on import unless the user
    // did that copy step themselves. Reusing the existing custom-section
    // mechanism (the same one AWARDS/PUBLICATIONS/etc. already go
    // through) instead of adding a new dedicated Resume field - no new
    // architecture, and the summary now survives confirmImport for real,
    // renders in every template exactly like any other custom section.
    // "Summary" and "Objective" already collapse into the same
    // _SectionKind here (see that enum's own header-keyword table), so a
    // single fixed title is used rather than trying to recover which
    // literal heading the document used - never a fabricated title.
    // Inserted first so it renders before any *other* custom section that
    // came later in the original document.
    final summaryLines = _nonBlank(sectionLines[_SectionKind.summary] ?? const []);
    if (summaryLines.isNotEmpty) {
      final now = DateTime.now();
      // Real-device beta fix: a Summary/Objective paragraph word-wraps
      // across several lines in the extracted source text, and each of
      // those was previously kept as its own separate entry - which
      // rendered as several disconnected one-line bullet fragments
      // instead of one flowing paragraph (confirmed on a real exported
      // PDF: a single sentence split mid-word across ~6 bullet points).
      // Joined into one paragraph entry instead, *unless* the source
      // genuinely used its own bullet markers (a "Key strengths:" list
      // under Summary is a real, if less common, format) - those are
      // preserved as separate entries exactly as before.
      final entries = summaryLines.any(_isBullet)
          ? summaryLines.map((l) => _isBullet(l) ? _stripBullet(l) : l).toList()
          : [summaryLines.join(' ')];
      customSections.insert(
        0,
        CustomSectionBlock(id: null, title: 'Summary', entries: entries, createdAt: now, updatedAt: now),
      );
    }

    if (!anyHeaderFound) {
      warnings.add(
        'No resume sections could be automatically detected in this file. '
        'Review the content below and build your resume using the Editor.',
      );
    }

    // Phase 2 (link handling): a link mentioned inside a custom section
    // (e.g. a dedicated "LINKS"/"PORTFOLIO" section, or a labeled line
    // like "Stack Overflow: stackoverflow.com/users/123" under an
    // unrecognized heading) or left in unclassifiedText previously stayed
    // as plain text - never silently dropped, but never rendered as a
    // real, clickable resume link either, since only the header/preamble
    // was ever scanned into [links]. Promoted here into the same
    // structural list every other profile link goes through.
    final allLinks = [
      ...links,
      ..._promoteLinksFoundElsewhere(
        existingLinks: links,
        projects: projects,
        certifications: certifications,
        customSections: customSections,
        unclassifiedText: unclassified,
      ),
    ];

    final completeness = _buildCompletenessReport(
      sectionLines: sectionLines,
      experienceImported: experience.length,
      educationImported: education.length,
      projectsImported: projects.length,
      certificationsImported: certifications.length,
      skillsSourceCount: skillsResult.sourceCount,
      skillsImported: skillsResult.skills.length,
      skillsFlagged: skillsResult.flaggedForReviewCount,
      customSectionOrder: customSectionOrder,
      customSectionLines: customSectionLines,
      hasSummary: summaryLines.isNotEmpty,
      rawText: rawText,
      profileLinks: allLinks,
      projects: projects,
      certifications: certifications,
    );

    return ParsedResumeDraft(
      fullName: fullName,
      email: email,
      phone: phone,
      location: location,
      links: allLinks,
      experience: experience,
      education: education,
      projects: projects,
      certifications: certifications,
      skills: skills,
      customSections: customSections,
      unclassifiedText: unclassified,
      warnings: warnings,
      completeness: completeness,
    );
  }

  /// A conservative "does this line look like a section header?" heuristic
  /// for lines that didn't match any known keyword in [_sectionKeywords] -
  /// see [parse]'s own "generic-header detection" comment for the full
  /// reasoning and the [pastFirstKnownHeader] gating that keeps this away
  /// from the preamble/name-detection step entirely.
  ///
  /// Deliberately requires every word be **fully uppercase** (plus a
  /// short connector set - "and", "of", "the", "in", "for", "&" - always
  /// allowed lowercase). An earlier version of this heuristic also
  /// accepted plain Title Case, which turned out to be unsafe: an entry
  /// title line inside an already-open *known* section - "Engineer - Acme
  /// Corp", "Offline Notes App", "AWS Certified Developer" - is
  /// structurally identical to a Title Case section header (short, a
  /// handful of capitalized words), and there is no way to tell them
  /// apart by shape alone. Real resumes overwhelmingly render an actual
  /// section header in full caps or a matching heading style, while an
  /// all-caps *entry* title/project name is rare - so requiring all-caps
  /// is the conservative bar that catches genuine unknown headers
  /// ("AWARDS", "PUBLICATIONS", "VOLUNTEER EXPERIENCE") without
  /// mistaking ordinary entry content for one. Also never a bullet/email/
  /// URL/date-range line, never ending in sentence punctuation, and short
  /// (matches [_matchHeader]'s own 40-character bound / 6-word cap).
  bool _looksLikeGenericSectionHeader(String trimmed) {
    if (trimmed.isEmpty || trimmed.length > 40) return false;
    if (_bulletPattern.hasMatch(trimmed)) return false;
    if (_emailPattern.hasMatch(trimmed)) return false;
    if (_urlPattern.hasMatch(trimmed)) return false;
    if (_dateRangePattern.hasMatch(trimmed)) return false;
    if (RegExp(r'[.,;:]$').hasMatch(trimmed)) return false;
    if (!RegExp(r'^[A-Za-z][A-Za-z &/\-]*$').hasMatch(trimmed)) return false;

    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > 6) return false;

    const connectors = {'and', 'of', 'the', 'in', 'for', '&'};
    var hasRealWord = false;
    for (final word in words) {
      if (connectors.contains(word.toLowerCase())) continue;
      final stripped = word.replaceAll(RegExp(r'[&/\-]'), '');
      if (stripped.isEmpty) continue;
      final isAllCaps = stripped == stripped.toUpperCase() && stripped != stripped.toLowerCase();
      if (!isAllCaps) return false;
      hasRealWord = true;
    }
    return hasRealWord;
  }

  /// Turns each custom section's raw lines into a flat, ordered list of
  /// plain-text entries - one per non-blank line, bullet markers stripped
  /// the same way every other typed section already does. A header found
  /// with nothing but blank lines under it (or immediately followed by the
  /// next header) contributes nothing - never a placeholder entry for
  /// content that was never actually there.
  List<CustomSectionBlock> _parseCustomSections(
    List<String> order,
    Map<String, List<String>> linesByTitle,
  ) {
    final now = DateTime.now();
    final result = <CustomSectionBlock>[];
    for (final title in order) {
      final entries = _joinWrappedContinuationLines(linesByTitle[title] ?? const []);
      if (entries.isEmpty) continue;
      result.add(CustomSectionBlock(id: null, title: title, entries: entries, createdAt: now, updatedAt: now));
    }
    return result;
  }

  _SectionKind? _matchHeader(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.length > 40) return null;
    if (_bulletPattern.hasMatch(trimmed)) return null;
    final normalized =
        trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    for (final entry in _sectionKeywords.entries) {
      if (entry.value.contains(normalized)) return entry.key;
    }
    return null;
  }

  /// Real-device beta fix: previously returned (matched or not) on the
  /// very first eligible preamble line, so a header whose first line
  /// merely wasn't a bare "First Last" (e.g. carrying a trailing role
  /// tagline) permanently lost the name - even though a real one might
  /// still appear on the very next line. Now tries every eligible
  /// preamble line and also tolerates a trailing parenthetical role
  /// tagline on the name's own line ("VADDE HARSHAVARDHAN (Python
  /// Developer)") by testing the text before the parenthesis too - the
  /// tagline itself is not captured here (no dedicated field exists yet
  /// for it on [ParsedResumeDraft]; it still surfaces via
  /// [ParsedResumeDraft.unclassifiedText] since the full original line no
  /// longer equals the detected name, so nothing is silently dropped).
  String? _detectName(List<String> preamble, String? email, String? phone) {
    for (final line in preamble) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (email != null && trimmed.contains(email)) continue;
      if (phone != null && trimmed.contains(phone.trim())) continue;
      if (_urlPattern.hasMatch(trimmed)) continue;
      if (_namePattern.hasMatch(trimmed)) return trimmed;
      final withoutParenthetical = trimmed.replaceFirst(RegExp(r'\s*\([^()]*\)\s*$'), '').trim();
      if (withoutParenthetical != trimmed && _namePattern.hasMatch(withoutParenthetical)) {
        return withoutParenthetical;
      }
    }
    return null;
  }

  /// Scans every preamble line (unlike [_detectName], which only ever
  /// looks at the first non-excluded one - a location line's position
  /// relative to the name/contact lines varies more than the name's own,
  /// which is virtually always first) for one matching [_locationPattern]
  /// or [_locationNamedRegionPattern].
  ///
  /// Real-device beta fix: a real resume's location wasn't on its own
  /// line at all - the whole header was one "|"-joined contact line
  /// ("Hyderabad, Telangana | email | phone | links"), so neither pattern
  /// (both anchored `^...$`, matching a *whole* line) ever matched it.
  /// Every preamble line is now also split on "|" (this app's own
  /// contact-line convention - see this function's sibling
  /// `contact.join(' | ')` in resume_content_plan_builder.dart) and each
  /// trimmed segment tried too - still exact-match, never a substring
  /// search, so the same "never guess" discipline applies to each segment
  /// individually.
  String? _detectLocation(List<String> preamble, String? fullName, String? email, String? phone) {
    bool isLocation(String candidate) =>
        _locationPattern.hasMatch(candidate) || _locationNamedRegionPattern.hasMatch(candidate);

    for (final line in preamble) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == fullName) continue;
      if (email != null && trimmed == email) continue;
      if (phone != null && trimmed == phone.trim()) continue;
      if (_urlPattern.hasMatch(trimmed) && _urlPattern.stringMatch(trimmed) == trimmed) continue;
      if (isLocation(trimmed)) return trimmed;
      if (trimmed.contains('|')) {
        for (final segment in trimmed.split('|')) {
          final candidate = segment.trim();
          if (candidate.isNotEmpty && isLocation(candidate)) return candidate;
        }
      }
    }
    return null;
  }

  List<ResumeLink> _extractLinks(String rawText) {
    final seen = <String>{};
    final links = <ResumeLink>[];
    for (final match in _urlPattern.allMatches(rawText)) {
      final url = match.group(0)!;
      if (!seen.add(url.toLowerCase())) continue;
      links.add(ResumeLink(label: _labelForUrl(url), url: url));
    }
    return links;
  }

  String _labelForUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('linkedin.com')) return 'LinkedIn';
    if (lower.contains('github.com')) return 'GitHub';
    if (lower.contains('gitlab.com')) return 'GitLab';
    if (lower.contains('twitter.com') || lower.contains('x.com')) return 'Twitter';
    if (lower.contains('stackoverflow.com')) return 'Stack Overflow';
    if (lower.contains('leetcode.com')) return 'LeetCode';
    if (lower.contains('medium.com')) return 'Medium';
    if (lower.contains('hackerrank.com')) return 'HackerRank';
    if (lower.contains('behance.net') || lower.contains('behance.com')) return 'Behance';
    if (lower.contains('dribbble.com')) return 'Dribbble';
    final host = url.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    return host.isEmpty ? 'Link' : host;
  }

  /// Phase 2 (link handling): scans every custom-section entry and every
  /// unclassified line for a URL not already captured by a profile link,
  /// a project's own link, or a certification's credential URL, and
  /// promotes it into the same structural [ResumeLink] shape every other
  /// profile link uses. Deliberately does **not** scan Experience/
  /// Education bullets - a URL inline in a bullet's own sentence is
  /// usually incidental supporting reference, not a standalone "profile
  /// link" the way a dedicated custom "LINKS"/"PORTFOLIO" section (or a
  /// stray line the parser couldn't otherwise classify) is.
  List<ResumeLink> _promoteLinksFoundElsewhere({
    required List<ResumeLink> existingLinks,
    required List<ProjectBlock> projects,
    required List<CertificationBlock> certifications,
    required List<CustomSectionBlock> customSections,
    required List<String> unclassifiedText,
  }) {
    final known = <String>{
      for (final link in existingLinks) link.url.toLowerCase(),
      for (final project in projects)
        if (project.link != null) project.link!.toLowerCase(),
      for (final cert in certifications)
        if (cert.credentialUrl != null) cert.credentialUrl!.toLowerCase(),
    };
    final promoted = <ResumeLink>[];
    void scan(String text) {
      for (final match in _urlPattern.allMatches(text)) {
        final url = match.group(0)!;
        if (!known.add(url.toLowerCase())) continue;
        promoted.add(ResumeLink(label: _labelForUrl(url), url: url));
      }
    }

    for (final section in customSections) {
      for (final entry in section.entries) {
        scan(entry);
      }
    }
    for (final line in unclassifiedText) {
      scan(line);
    }
    return promoted;
  }

  List<String> _nonBlank(List<String> lines) =>
      lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  /// Splits [lines] into entry blocks separated by one or more blank lines.
  List<List<String>> _splitIntoBlocks(List<String>? lines) {
    if (lines == null) return const [];
    final blocks = <List<String>>[];
    var current = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        if (current.isNotEmpty) {
          blocks.add(current);
          current = [];
        }
      } else {
        current.add(line.trim());
      }
    }
    if (current.isNotEmpty) blocks.add(current);
    return blocks;
  }

  bool _isBullet(String line) => _bulletPattern.hasMatch(line);

  String _stripBullet(String line) => line.replaceFirst(_bulletPattern, '').trim();

  static final _terminalPunctuation = RegExp(r'[.!?:;]$');

  /// Turns a raw sequence of lines (bullet-marked or not, in original
  /// document order) into one entry per logical bullet/detail, rejoining
  /// a wrapped continuation line back onto the item it continues instead
  /// of treating every physical line as its own separate item.
  ///
  /// Real-device beta bug: a long bullet sentence word-wraps across two
  /// or more physical lines in the extracted PDF text, and only the
  /// *first* of those lines carries the bullet marker. A prior fix made
  /// every non-bullet line survive (rather than being silently dropped,
  /// the original defect) by keeping each one as its own standalone item
  /// - which fixed the data loss but introduced a new, related defect:
  /// a single real bullet like "Developed and maintained Python-based
  /// data pipelines to extract, validate, and deploy multilingual
  /// educational content to / AWS S3, reducing manual QA effort by ~70%"
  /// (wrapped mid-sentence, no trailing punctuation on the first physical
  /// line) was rendered as *two* disconnected bullet fragments instead of
  /// one - confirmed on a real resume, where this also inflated one
  /// Experience entry to 29 "bullets" total, which separately triggered a
  /// pw.Partitions pagination failure on the Balanced Two-Column
  /// archetype (`PdfTooBigPageException`).
  ///
  /// A non-bullet line is joined onto the immediately preceding item only
  /// when BOTH (a) that preceding item was itself opened by an actual
  /// bullet marker - never a standalone line - and (b) it does not
  /// already end in terminal punctuation (`. ! ? : ;`), the same "is this
  /// sentence actually finished" signal a human would use.
  ///
  /// Condition (a) is what keeps this safe for a section that uses no
  /// bullet markers at all - a real regression this fix's own first
  /// version caused: a custom section (e.g. "AWARDS") written as one
  /// unmarked item per line ("Employee of the Year, 2021" / "Top
  /// Performer Award, 2020", neither line ending in punctuation) was
  /// wrongly merged into a single run-on entry, since nothing there is
  /// actually a wrapped continuation of anything. Only lines that follow
  /// a genuine bullet-marked item are ever candidates for joining. A
  /// standalone line that happens to follow a properly-terminated bullet
  /// (e.g. an italic sub-project header - "SciLab (Web & Android) —
  /// Godot, GDScript, AWS S3, Google Play Console") is correctly left as
  /// its own item either way, since the bullet before it ends with a
  /// period.
  List<String> _joinWrappedContinuationLines(Iterable<String> rawLines) {
    final result = <String>[];
    var lastWasBulletOpened = false;
    for (final raw in rawLines) {
      final isBulletLine = _isBullet(raw);
      final text = isBulletLine ? _stripBullet(raw) : raw.trim();
      if (text.isEmpty) continue;
      if (!isBulletLine &&
          result.isNotEmpty &&
          lastWasBulletOpened &&
          !_terminalPunctuation.hasMatch(result.last)) {
        result[result.length - 1] = '${result.last} $text';
      } else {
        result.add(text);
        lastWasBulletOpened = isBulletLine;
      }
    }
    return result;
  }

  /// Real-device data-model fix (sub-project nesting): walks a block's
  /// remaining lines (title/date lines already excluded by the caller) in
  /// original document order, separating the role's own top-level bullets
  /// from any distinct, named sub-projects nested under it.
  ///
  /// The signal that a non-bullet line starts a *new sub-project* (rather
  /// than being a wrapped continuation of the previous bullet - see
  /// [_joinWrappedContinuationLines]'s identical reasoning) is exactly the
  /// same one that function already uses: a continuation only ever
  /// follows a line that was itself opened by a real bullet marker and
  /// doesn't already end in terminal punctuation. Every other non-bullet
  /// line - the far more common case for a genuine sub-project header
  /// ("SciLab (Web & Android) — Godot, GDScript...") - starts a new named
  /// sub-project instead; every bullet that follows belongs to it, until
  /// either the next such header or the end of the block. Bullets found
  /// before the first sub-project header (or when there is no sub-project
  /// header at all, the overwhelmingly common case) are the role's own
  /// top-level [_SplitExperienceContent.mainBullets], unchanged from this
  /// method's predecessor.
  _SplitExperienceContent _splitIntoSubProjects(Iterable<String> rawLines) {
    final mainBullets = <String>[];
    final subProjects = <ExperienceSubProject>[];
    String? currentSubProjectName;
    var currentSubProjectBullets = <String>[];
    var lastWasBulletOpened = false;

    void flushSubProject() {
      final name = currentSubProjectName;
      if (name != null) {
        subProjects.add(ExperienceSubProject(name: name, bullets: List.of(currentSubProjectBullets)));
      }
      currentSubProjectName = null;
      currentSubProjectBullets = [];
    }

    for (final raw in rawLines) {
      final isBulletLine = _isBullet(raw);
      final text = isBulletLine ? _stripBullet(raw) : raw.trim();
      if (text.isEmpty) continue;
      final target = currentSubProjectName != null ? currentSubProjectBullets : mainBullets;

      if (!isBulletLine) {
        if (target.isNotEmpty && lastWasBulletOpened && !_terminalPunctuation.hasMatch(target.last)) {
          // A genuine wrapped continuation of the immediately preceding
          // bullet, in whichever bucket (main or current sub-project) is
          // active right now - joined onto it exactly as
          // _joinWrappedContinuationLines already does.
          target[target.length - 1] = '${target.last} $text';
          continue;
        }
        // A new sub-project header.
        flushSubProject();
        currentSubProjectName = text;
        lastWasBulletOpened = false;
        continue;
      }

      target.add(text);
      lastWasBulletOpened = true;
    }
    flushSubProject();
    return _SplitExperienceContent(mainBullets: mainBullets, subProjects: subProjects);
  }

  /// Scans every non-bullet line in [block] for a date range and returns
  /// where it was found plus its (startDate, endDate) - endDate is null
  /// for an open-ended "Present"/"Current" range. Returns null if no
  /// confident date range is found anywhere in the block, so the caller
  /// never has to invent one.
  ///
  /// Real-device beta fix: the previous version required the date match
  /// to cover at least half of its line's length, on the theory that a
  /// shorter match was more likely a stray year mentioned in a sentence.
  /// That heuristic broke on an extremely common real resume layout -
  /// role/company and a right-aligned date+location all on *one* line
  /// ("Software Engineer | Acme Corp    Dec 2025 - Present | City, ST") -
  /// where the date substring is legitimately a small fraction of a long
  /// combined line. The 50%-of-line-length check silently rejected the
  /// date on every entry using that layout, `dateRange` came back null
  /// for the whole block, and the entire entry (title, company, every
  /// bullet) was discarded to [ParsedResumeDraft.unclassifiedText] -
  /// confirmed the actual cause of a real user's Experience/Education
  /// sections disappearing entirely on a physical-device test. Since only
  /// non-bullet lines are ever scanned (unchanged), a stray year inside
  /// an actual bullet sentence was never a risk this threshold needed to
  /// guard against in the first place.
  _BlockDateMatch? _findDateRangeInBlock(List<String> block) {
    for (final line in block) {
      if (_isBullet(line)) continue;
      final match = _dateRangePattern.firstMatch(line);
      if (match == null) continue;
      final start = match.group(1)!;
      final end = match.group(2) != null ? null : match.group(3);
      return _BlockDateMatch(
        line: line,
        matchStart: match.start,
        matchEnd: match.end,
        startDate: start,
        endDate: end,
      );
    }
    return null;
  }

  /// Strips a leading separator ("|", "-", ",", an em/en dash) and
  /// surrounding whitespace from text found trailing a date range on a
  /// combined title+date(+location) line - e.g. turns
  /// "| Hyderabad, India" into "Hyderabad, India". Returns null (never an
  /// empty string) if nothing meaningful remains.
  String? _cleanTrailingText(String text) {
    final cleaned = text.trim().replaceFirst(RegExp(r'^[|,\-–—]\s*'), '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Splits a title line like "Software Engineer - Acme Corp" into two
  /// confident, non-empty parts using this app's own preferred separator
  /// ("Role - Company", matching `PwResumePdfExportService`'s own render
  /// order) then progressively looser fallbacks. Returns null - never a
  /// guessed single-part split - if nothing yields exactly two non-empty
  /// parts.
  (String, String)? _splitTitleLine(String line) {
    for (final separator in [' - ', ' – ', ' — ', ' | ', ' at ', ',']) {
      final index = line.indexOf(separator);
      if (index <= 0) continue;
      final first = line.substring(0, index).trim();
      final second = line.substring(index + separator.length).trim();
      if (first.isNotEmpty && second.isNotEmpty) return (first, second);
    }
    return null;
  }

  List<ExperienceBlock> _parseExperience(
    List<String>? lines,
    List<String> unclassified,
    List<String> warnings,
  ) {
    final blocks = _splitIntoBlocks(lines);
    if (blocks.isEmpty) return const [];

    final result = <ExperienceBlock>[];
    var anyUnstructured = false;
    final now = DateTime.now();

    for (final block in blocks) {
      final dateMatch = _findDateRangeInBlock(block);
      final rawTitleLine = block.firstWhere((l) => !_isBullet(l), orElse: () => '');

      // Real-device beta fix: when the date range was found on the same
      // line as the title (a combined "Role | Company    Dec 2025 -
      // Present | City" layout), strip the matched date span - and
      // anything trailing it - out of the title line before splitting it
      // into role/company, and treat the trailing remainder as a
      // location. When the date instead lives on its own separate line
      // (the layout this parser originally supported), titleLine is
      // untouched, exactly as before.
      var titleLine = rawTitleLine;
      String? location;
      if (dateMatch != null && dateMatch.line == rawTitleLine) {
        titleLine = rawTitleLine.substring(0, dateMatch.matchStart).trim();
        location = _cleanTrailingText(rawTitleLine.substring(dateMatch.matchEnd));
      }

      final split = titleLine.isEmpty ? null : _splitTitleLine(titleLine);

      if (split != null && dateMatch != null) {
        // Real-device data-model fix: a resume entry commonly nests
        // several distinct, named sub-projects under one role ("SciLab",
        // "ByHeart", "Crossword" under one "Software Engineer" entry),
        // each with its own bullets. Previously every remaining line in
        // the block (bulleted or not) was kept as a *flat* bullet -
        // real data preservation (nothing lost), but a sub-project's own
        // name and bullets were indistinguishable from the role's own
        // accomplishments. `_splitIntoSubProjects` now structures this:
        // a non-bullet line that isn't a wrapped continuation of the
        // previous bullet starts a new named sub-project; every bullet
        // after it belongs to that sub-project until the next one.
        final parsed = _splitIntoSubProjects(
          block.where((l) => l != rawTitleLine && l != dateMatch.line),
        );
        result.add(ExperienceBlock(
          id: null,
          role: split.$1,
          company: split.$2,
          location: location,
          startDate: dateMatch.startDate,
          endDate: dateMatch.endDate,
          bullets: parsed.mainBullets,
          subProjects: parsed.subProjects,
          createdAt: now,
          updatedAt: now,
        ));
      } else {
        anyUnstructured = true;
        unclassified.add(block.join('\n'));
      }
    }

    if (anyUnstructured) {
      warnings.add(
        'Some entries in the Experience section could not be confidently '
        'structured (a role, company, and date range are all required) - '
        'they were left for manual review below.',
      );
    }
    return result;
  }

  List<EducationBlock> _parseEducation(
    List<String>? lines,
    List<String> unclassified,
    List<String> warnings,
  ) {
    final blocks = _splitIntoBlocks(lines);
    if (blocks.isEmpty) return const [];

    final result = <EducationBlock>[];
    var anyUnstructured = false;
    final now = DateTime.now();

    for (final block in blocks) {
      final dateMatch = _findDateRangeInBlock(block);
      final rawTitleLine = block.firstWhere((l) => !_isBullet(l), orElse: () => '');

      // See the identical fix in [_parseExperience] - an institution/date
      // combined on one line ("Sri Venkateshwara College of Engineering
      // Aug 2020 - June 2024 | Tirupathi, India") previously made the
      // whole entry unstructurable.
      var titleLine = rawTitleLine;
      String? trailingLocation;
      if (dateMatch != null && dateMatch.line == rawTitleLine) {
        titleLine = rawTitleLine.substring(0, dateMatch.matchStart).trim();
        trailingLocation = _cleanTrailingText(rawTitleLine.substring(dateMatch.matchEnd));
      }

      var split = titleLine.isEmpty ? null : _splitTitleLine(titleLine);

      // Real-device beta fix: a real resume put the institution (plus its
      // date range) on one line and the degree on its own, entirely
      // separate line - no "Degree - Institution" combined line exists at
      // all. [_splitTitleLine] can't find a separator on `titleLine` in
      // that shape (it's just the bare institution name), so previously
      // the whole entry fell through to unclassified even though a
      // confident structure exists: `titleLine` itself is the institution,
      // and the next non-bullet, non-date line is the degree.
      String? degreeLine;
      if (split == null && titleLine.isNotEmpty && dateMatch != null) {
        final otherLine = block.firstWhere(
          (l) => !_isBullet(l) && l != rawTitleLine && l != dateMatch.line,
          orElse: () => '',
        );
        if (otherLine.isNotEmpty) {
          degreeLine = otherLine;
          split = (otherLine, titleLine);
        }
      }

      if (split != null && dateMatch != null) {
        var degree = split.$1;
        String? fieldOfStudy;
        final inMatch = RegExp(r'^(.*)\bin\s+(.+)$', caseSensitive: false).firstMatch(degree);
        if (inMatch != null) {
          degree = inMatch.group(1)!.trim();
          fieldOfStudy = inMatch.group(2)!.trim();
        }
        final details = [
          ..._joinWrappedContinuationLines(
            block.where((l) => l != rawTitleLine && l != degreeLine && !_dateRangePattern.hasMatch(l)),
          ),
          // [EducationBlock] has no dedicated location field (unlike
          // [ExperienceBlock]) - preserved as a detail line instead of
          // discarded, since a trailing "City, ST" fragment stripped off
          // a combined title+date line is still real content from the
          // source document.
          if (trailingLocation != null) trailingLocation,
        ];
        result.add(EducationBlock(
          id: null,
          institution: split.$2,
          degree: degree,
          fieldOfStudy: fieldOfStudy,
          startDate: dateMatch.startDate,
          endDate: dateMatch.endDate,
          details: details,
          createdAt: now,
          updatedAt: now,
        ));
      } else {
        anyUnstructured = true;
        unclassified.add(block.join('\n'));
      }
    }

    if (anyUnstructured) {
      warnings.add(
        'Some entries in the Education section could not be confidently '
        'structured (a degree, institution, and date range are all '
        'required) - they were left for manual review below.',
      );
    }
    return result;
  }

  List<ProjectBlock> _parseProjects(
    List<String>? lines,
    List<String> unclassified,
    List<String> warnings,
  ) {
    final blocks = _splitIntoBlocks(lines);
    if (blocks.isEmpty) return const [];

    final result = <ProjectBlock>[];
    var anyUnstructured = false;
    final now = DateTime.now();

    for (final block in blocks) {
      final nameLine = block.firstWhere((l) => !_isBullet(l), orElse: () => '');
      if (nameLine.isEmpty) {
        anyUnstructured = true;
        unclassified.add(block.join('\n'));
        continue;
      }

      final linkMatch = _urlPattern.firstMatch(block.join(' '));
      // Real-device beta fix: a line like "GitHub: github.com/x/y" (a
      // common real-resume convention, not just the bare URL) previously
      // survived into `bullets` too, since it was never exactly equal to
      // the bare matched URL - rendering the project's own link twice
      // (once as its dedicated link field, once again as a plain bullet).
      // `l.contains(...)` (rather than requiring an exact match) catches
      // the label-prefixed form as well.
      final bullets = _joinWrappedContinuationLines(
        block.where((l) => l != nameLine && !(linkMatch != null && l.trim().contains(linkMatch.group(0)!))),
      );

      result.add(ProjectBlock(
        id: null,
        name: nameLine,
        link: linkMatch?.group(0),
        bullets: bullets,
        createdAt: now,
        updatedAt: now,
      ));
    }

    if (anyUnstructured) {
      warnings.add(
        'Some entries in the Projects section had no clear project name '
        'and were left for manual review below.',
      );
    }
    return result;
  }

  List<CertificationBlock> _parseCertifications(
    List<String>? lines,
    List<String> unclassified,
    List<String> warnings,
  ) {
    final blocks = _splitIntoBlocks(lines);
    if (blocks.isEmpty) return const [];

    final result = <CertificationBlock>[];
    var anyUnstructured = false;
    final now = DateTime.now();

    for (final block in blocks) {
      final titleLine = block.first;
      final split = _splitTitleLine(titleLine);
      if (split == null) {
        anyUnstructured = true;
        unclassified.add(block.join('\n'));
        continue;
      }

      final dateMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(block.join(' '));
      final linkMatch = _urlPattern.firstMatch(block.join(' '));

      result.add(CertificationBlock(
        id: null,
        name: split.$1,
        issuer: split.$2,
        issuedDate: dateMatch?.group(0),
        credentialUrl: linkMatch?.group(0),
        createdAt: now,
        updatedAt: now,
      ));
    }

    if (anyUnstructured) {
      warnings.add(
        'Some entries in the Certifications section could not be '
        'confidently structured (a name and issuer are both required) - '
        'they were left for manual review below.',
      );
    }
    return result;
  }

  /// Returns the parsed skills alongside the exact counts
  /// [ResumeImportCompletenessReport] needs - computed inline, from the
  /// same single pass that already decides each token's fate, rather than
  /// a second pass a future edit here could let drift out of sync.
  /// [sourceCount] counts each *distinct* (case-insensitive) token once,
  /// matching this method's own existing deduplication - a repeated skill
  /// mention is intentionally merged, never double-counted as "found
  /// twice, imported once".
  ({List<SkillEntry> skills, int sourceCount, int flaggedForReviewCount}) _parseSkills(
    List<String>? lines,
    List<String> unclassified,
  ) {
    if (lines == null || lines.isEmpty) {
      return (skills: const <SkillEntry>[], sourceCount: 0, flaggedForReviewCount: 0);
    }
    final now = DateTime.now();

    final joined = lines.map(_stripBullet).join('\n');
    final tokens = joined.split(RegExp(r'[,\n]')).map((t) => t.trim()).where((t) => t.isNotEmpty);

    final seen = <String>{};
    final sourceSeen = <String>{};
    final result = <SkillEntry>[];
    var flaggedForReview = 0;
    for (final token in tokens) {
      final key = token.toLowerCase();
      final isNewSourceItem = sourceSeen.add(key);
      if (token.length > 60) {
        // Too long to be a single skill name with confidence - likely an
        // un-delimited paragraph rather than a real skill list; kept for
        // manual review rather than inserted as a fabricated-looking
        // "skill" that's actually a sentence.
        unclassified.add(token);
        if (isNewSourceItem) flaggedForReview++;
        continue;
      }
      if (!seen.add(key)) continue;
      result.add(SkillEntry(id: null, name: token, category: SkillCategory.technical, createdAt: now));
    }
    return (skills: result, sourceCount: sourceSeen.length, flaggedForReviewCount: flaggedForReview);
  }

  /// Builds the completeness evidence attached to every real
  /// [ParsedResumeDraft] this parser produces - see
  /// [ResumeImportCompletenessReport]'s own doc comment for what each
  /// section's numbers mean. Reuses [_splitIntoBlocks] (the exact same
  /// block-splitting [_parseExperience]/[_parseEducation]/[_parseProjects]/
  /// [_parseCertifications] already ran) rather than a second, potentially
  /// drifting count - every block those methods saw becomes either a
  /// structured entry or an `unclassifiedText` item, never neither, which
  /// this report exists to keep proving true rather than merely assuming.
  ResumeImportCompletenessReport _buildCompletenessReport({
    required Map<_SectionKind, List<String>> sectionLines,
    required int experienceImported,
    required int educationImported,
    required int projectsImported,
    required int certificationsImported,
    required int skillsSourceCount,
    required int skillsImported,
    required int skillsFlagged,
    required List<String> customSectionOrder,
    required Map<String, List<String>> customSectionLines,
    required bool hasSummary,
    required String rawText,
    required List<ResumeLink> profileLinks,
    required List<ProjectBlock> projects,
    required List<CertificationBlock> certifications,
  }) {
    SectionCompleteness blockSection(String label, _SectionKind kind, int imported) {
      final total = _splitIntoBlocks(sectionLines[kind]).length;
      return SectionCompleteness(
        label: label,
        sourceCount: total,
        importedCount: imported,
        flaggedForReviewCount: total - imported,
      );
    }

    final customSectionsFound = customSectionOrder
        .where((title) => _joinWrappedContinuationLines(customSectionLines[title] ?? const []).isNotEmpty)
        .length;

    // Independent cross-check for links (unlike the sections above, this
    // doesn't reuse a parser-internal count - it re-scans the *whole* raw
    // document for every URL-shaped match and confirms each one landed
    // somewhere real: the header/profile links list, a project's own
    // link, or a certification's credential URL). A link mentioned only
    // inside a bullet or an unclassified line (never assigned to any
    // structured field) surfaces here as genuinely missing, which is
    // exactly the Phase 2 "store links structurally" requirement this
    // report exists to hold the parser to.
    final allUrls = <String>{};
    for (final match in _urlPattern.allMatches(rawText)) {
      allUrls.add(match.group(0)!.toLowerCase());
    }
    final preservedUrls = <String>{
      for (final link in profileLinks) link.url.toLowerCase(),
      for (final project in projects)
        if (project.link != null) project.link!.toLowerCase(),
      for (final cert in certifications)
        if (cert.credentialUrl != null) cert.credentialUrl!.toLowerCase(),
    };
    final preservedUrlCount = allUrls.where(preservedUrls.contains).length;

    return ResumeImportCompletenessReport(
      sections: [
        blockSection('Experience', _SectionKind.experience, experienceImported),
        blockSection('Education', _SectionKind.education, educationImported),
        blockSection('Projects', _SectionKind.projects, projectsImported),
        blockSection('Certifications', _SectionKind.certifications, certificationsImported),
        SectionCompleteness(
          label: 'Skills',
          sourceCount: skillsSourceCount,
          importedCount: skillsImported,
          flaggedForReviewCount: skillsFlagged,
        ),
        SectionCompleteness(
          label: 'Custom sections',
          sourceCount: customSectionOrder.length,
          importedCount: customSectionsFound,
          flaggedForReviewCount: customSectionOrder.length - customSectionsFound,
        ),
        SectionCompleteness(
          label: 'Summary',
          sourceCount: hasSummary ? 1 : 0,
          importedCount: hasSummary ? 1 : 0,
        ),
        SectionCompleteness(
          label: 'Links',
          sourceCount: allUrls.length,
          importedCount: preservedUrlCount,
        ),
      ],
    );
  }
}
