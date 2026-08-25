import '../../../models/certification_block.dart';
import '../../../models/custom_section_block.dart';
import '../../../models/education_block.dart';
import '../../../models/experience_block.dart';
import '../../../models/resume.dart';
import '../../../models/resume_block_type.dart';
import '../../../models/resume_link.dart';
import '../../../models/skill_entry.dart';
import '../../../repositories/certification_block_repository.dart';
import '../../../repositories/custom_section_block_repository.dart';
import '../../../repositories/education_block_repository.dart';
import '../../../repositories/experience_block_repository.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../repositories/skill_entry_repository.dart';
import '../../../services/career/beginner/role_category.dart';

/// One "Internship / part-time / volunteer / previous employment" entry the
/// user described in the Beginner Resume flow (R-10 §5) - free-form, not a
/// full block-editor form (this flow is deliberately lighter-weight than
/// the standard Experience Block Editor, which remains reachable afterward
/// via the normal Resume Editor for anyone who wants more structure).
class BeginnerExperienceEntryInput {
  const BeginnerExperienceEntryInput({
    required this.title,
    required this.organization,
    this.when = '',
    this.description = '',
  });

  /// e.g. "Marketing Intern", "Volunteer".
  final String title;

  /// e.g. "Acme Retail Pvt Ltd".
  final String organization;

  /// Free text, e.g. "Summer 2023" or "Jan-Mar 2024" - stored directly as
  /// [ExperienceBlock.startDate], which the renderer only ever displays
  /// verbatim (never parsed as a real date), so any honest, user-supplied
  /// text is safe here.
  final String when;

  /// One line per bullet - blank lines are dropped.
  final String description;

  bool get isBlank => title.trim().isEmpty && organization.trim().isEmpty;
}

/// Everything [CreateBeginnerResumeUseCase] needs, collected across the
/// Beginner Resume flow's steps - a plain input DTO, not a persisted model
/// (nothing here is written to the database until [CreateBeginnerResumeUseCase.call]
/// runs). Every field but [fullName] and [roleCategory] is genuinely
/// optional: leaving it blank means the corresponding resume section is
/// never created, not filled with a placeholder.
class BeginnerResumeInput {
  const BeginnerResumeInput({
    required this.fullName,
    this.phone,
    this.email,
    this.location,
    this.linkedIn,
    this.portfolio,
    required this.roleCategory,
    this.targetRoleLabel,
    this.degree,
    this.institution,
    this.graduationYear,
    this.experienceEntries = const [],
    this.confirmedSkills = const [],
    this.languages = const [],
    this.certifications = const [],
    this.achievements = const [],
    this.summaryOverride,
  });

  final String fullName;
  final String? phone;
  final String? email;
  final String? location;
  final String? linkedIn;
  final String? portfolio;

  /// The matched/selected role category - always set (falls back to
  /// [RoleCategoryCatalog.generalFresher], never null), since it drives the
  /// generated summary's [RoleCategory.summaryFocus] and is never itself
  /// optional in this flow (R-10 §2: the user always picks A or B).
  final RoleCategory roleCategory;

  /// The exact role text to show/store as [Resume.targetRole] - e.g. the
  /// JD's own detected title when the user pasted a real JD, or whatever
  /// they typed/picked. Falls back to [roleCategory.displayName] when null
  /// or blank.
  final String? targetRoleLabel;

  final String? degree;
  final String? institution;
  final String? graduationYear;

  final List<BeginnerExperienceEntryInput> experienceEntries;

  /// Every skill the resume should actually list - both the user's own
  /// typed skills and any role-suggested skill they explicitly kept
  /// (R-10 §6: a suggestion never becomes part of the resume on its own).
  /// The caller (the screen) is responsible for only including what the
  /// user confirmed; this use case attaches exactly this list, nothing
  /// more.
  final List<SuggestedSkill> confirmedSkills;

  final List<String> languages;
  final List<String> certifications;
  final List<String> achievements;

  /// The professional-summary text to store verbatim instead of the
  /// deterministic default from [buildBeginnerResumeSummary] - set when the
  /// user reviewed the generated draft and optionally polished it (R-10
  /// §9/§14: the *only* place AI may touch this flow, via the existing,
  /// unmodified `BulletSuggestionField` widget - see
  /// `BeginnerResumeScreen`'s review step). Null/blank means "use the
  /// deterministic default," so the flow works identically with no AI
  /// model installed at all.
  final String? summaryOverride;
}

/// The deterministic professional-summary text for [input] - a pure
/// function (no I/O), reused by both [CreateBeginnerResumeUseCase] itself
/// (as the default) and `BeginnerResumeScreen` (to seed the Review step's
/// editable/AI-polishable preview before the resume even exists yet).
///
/// Every clause is conditional on real input, never on
/// [RoleCategory.suggestedSkills] or any other unconfirmed role guidance
/// (R-10 §9: "do not claim years of experience, achievements,
/// certifications, tools, or responsibilities that the user never
/// provided"). [RoleCategory.summaryFocus] is the one piece of catalog data
/// used here, and it only ever describes the *target role*, never the
/// person's own ability.
String buildBeginnerResumeSummary(BeginnerResumeInput input) {
  final degree = _blankToNullTop(input.degree);
  final opening = degree != null ? 'Motivated $degree graduate' : 'Motivated candidate';
  final buffer = StringBuffer(
    '$opening seeking to build a career in ${input.roleCategory.summaryFocus}.',
  );

  final skillNames =
      input.confirmedSkills.map((s) => s.name.trim()).where((n) => n.isNotEmpty).toSet().toList();
  if (skillNames.isNotEmpty) {
    buffer.write(' Skilled in ${_joinWithAndTop(skillNames.take(6).toList())}.');
  }

  final hasRealExperience = input.experienceEntries.any((e) => !e.isBlank);
  if (hasRealExperience) {
    buffer.write(' Has practical experience through internship, part-time, or volunteer work.');
  }

  return buffer.toString();
}

String _joinWithAndTop(List<String> items) {
  if (items.length == 1) return items.first;
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

String? _blankToNullTop(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Creates a real [Resume] (plus attached blocks) from the Beginner Resume
/// flow's collected input (R-10, docs/v3/implementation/03-decisions.md) -
/// reuses every existing resume repository/model exactly the way
/// [CreateResumeFromProfileUseCase]/[CreateResumeFromJdUseCase] already do;
/// no parallel resume model or persistence path exists here.
///
/// **The single rule every branch below follows**: a section is only ever
/// created from what [BeginnerResumeInput] actually carries. Nothing is
/// invented to fill a section, and no section is padded with placeholder
/// content - if the user left projects/experience/certifications/languages
/// blank, no corresponding block is created at all, exactly the way R-6/R-7's
/// own "no fabrication" resume flows already work.
class CreateBeginnerResumeUseCase {
  CreateBeginnerResumeUseCase({
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required EducationBlockRepository educationBlockRepository,
    required ExperienceBlockRepository experienceBlockRepository,
    required CertificationBlockRepository certificationBlockRepository,
    required SkillEntryRepository skillEntryRepository,
    required CustomSectionBlockRepository customSectionBlockRepository,
  })  : _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _educationBlockRepository = educationBlockRepository,
        _experienceBlockRepository = experienceBlockRepository,
        _certificationBlockRepository = certificationBlockRepository,
        _skillEntryRepository = skillEntryRepository,
        _customSectionBlockRepository = customSectionBlockRepository;

  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final EducationBlockRepository _educationBlockRepository;
  final ExperienceBlockRepository _experienceBlockRepository;
  final CertificationBlockRepository _certificationBlockRepository;
  final SkillEntryRepository _skillEntryRepository;
  final CustomSectionBlockRepository _customSectionBlockRepository;

  Future<int> call(BeginnerResumeInput input) async {
    final now = DateTime.now();
    final roleLabel = _blankToNull(input.targetRoleLabel) ?? input.roleCategory.displayName;

    final links = <ResumeLink>[
      if (_blankToNull(input.linkedIn) case final url?) ResumeLink(label: 'LinkedIn', url: url),
      if (_blankToNull(input.portfolio) case final url?) ResumeLink(label: 'Portfolio', url: url),
    ];

    final resumeId = await _resumeRepository.insert(
      Resume(
        id: null,
        title: '$roleLabel Resume',
        targetRole: roleLabel,
        fullName: input.fullName.trim(),
        email: _blankToNull(input.email),
        phone: _blankToNull(input.phone),
        location: _blankToNull(input.location),
        links: links,
        achievements: input.achievements.map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Professional summary - always created (R-10 §16: even the minimum
    // input of name + role should still look intentional). Uses the
    // user-reviewed/optionally-AI-polished text if the screen provided one,
    // otherwise the deterministic default - see buildBeginnerResumeSummary.
    final summaryText = _blankToNull(input.summaryOverride) ?? buildBeginnerResumeSummary(input);
    final summaryId = await _customSectionBlockRepository.insert(
      CustomSectionBlock(
        id: null,
        title: 'Professional Summary',
        entries: [summaryText],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _resumeBlockRepository.attach(resumeId, ResumeBlockType.customSection, summaryId);

    // Education - only if a degree was actually given.
    final degree = _blankToNull(input.degree);
    if (degree != null) {
      final gradYear = _blankToNull(input.graduationYear);
      // A plain display string, never parsed as a real date by the
      // renderer (resume_content_plan_builder.dart interpolates
      // start/end date verbatim) - "YYYY-06" is just a readable
      // placeholder for "graduated this year", not a claimed exact month.
      final dateLabel = gradYear == null ? '' : '$gradYear-06';
      final educationId = await _educationBlockRepository.insert(
        EducationBlock(
          id: null,
          // Never invented - left blank if the user didn't give one; the
          // full Resume Editor (reached right after this flow) is where
          // it can be filled in.
          institution: _blankToNull(input.institution) ?? '',
          degree: degree,
          startDate: dateLabel,
          endDate: dateLabel.isEmpty ? null : dateLabel,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.education, educationId);
    }

    // Experience (internship/part-time/volunteer/previous employment) -
    // only entries the user actually described; a blank entry (both title
    // and organization empty) is silently skipped rather than stored.
    for (final entry in input.experienceEntries) {
      if (entry.isBlank) continue;
      final bullets = entry.description
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final experienceId = await _experienceBlockRepository.insert(
        ExperienceBlock(
          id: null,
          role: entry.title.trim(),
          company: entry.organization.trim(),
          startDate: entry.when.trim(),
          bullets: bullets,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
    }

    // Skills - reuses an existing library entry by case-insensitive name
    // instead of creating a duplicate row every time a common suggestion
    // (e.g. "Communication") is accepted across different resumes.
    if (input.confirmedSkills.isNotEmpty) {
      final existingSkills = await _skillEntryRepository.getAll();
      for (final skill in input.confirmedSkills) {
        final name = skill.name.trim();
        if (name.isEmpty) continue;
        final match = _findByNameIgnoreCase(existingSkills, name);
        final skillId = match?.id ??
            await _skillEntryRepository.insert(
              SkillEntry(id: null, name: name, category: skill.category, createdAt: now),
            );
        await _resumeBlockRepository.attach(resumeId, ResumeBlockType.skill, skillId);
      }
    }

    // Certifications - name only; issuer is never invented when the user
    // only gave a name (CertificationBlock.issuer is non-nullable, so an
    // honest empty string is stored rather than a guessed organization).
    for (final rawName in input.certifications) {
      final name = rawName.trim();
      if (name.isEmpty) continue;
      final certificationId = await _certificationBlockRepository.insert(
        CertificationBlock(id: null, name: name, issuer: '', createdAt: now, updatedAt: now),
      );
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.certification, certificationId);
    }

    // Languages - no dedicated block type exists for this (see
    // CustomSectionBlock's own doc comment, which names "Languages" as
    // exactly this kind of case), so it reuses that generic mechanism
    // rather than inventing a new one.
    final languages = input.languages.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (languages.isNotEmpty) {
      final languagesId = await _customSectionBlockRepository.insert(
        CustomSectionBlock(id: null, title: 'Languages', entries: languages, createdAt: now, updatedAt: now),
      );
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.customSection, languagesId);
    }

    return resumeId;
  }

  SkillEntry? _findByNameIgnoreCase(List<SkillEntry> entries, String name) {
    for (final entry in entries) {
      if (entry.name.toLowerCase() == name.toLowerCase()) return entry;
    }
    return null;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
