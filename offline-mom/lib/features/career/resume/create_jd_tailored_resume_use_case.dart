import '../../../models/custom_section_block.dart';
import '../../../models/education_block.dart';
import '../../../models/experience_block.dart';
import '../../../models/project_block.dart';
import '../../../models/resume.dart';
import '../../../models/resume_block_type.dart';
import '../../../models/resume_link.dart';
import '../../../models/skill_entry.dart';
import '../../../repositories/custom_section_block_repository.dart';
import '../../../repositories/education_block_repository.dart';
import '../../../repositories/experience_block_repository.dart';
import '../../../repositories/project_block_repository.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../repositories/skill_entry_repository.dart';
import '../../../services/career/beginner/role_category.dart' show SuggestedSkill;

/// One "Internship / part-time / volunteer / previous employment" entry
/// collected in the JD-tailored resume wizard - deliberately the exact
/// same free-form shape as `BeginnerExperienceEntryInput`
/// (create_beginner_resume_use_case.dart), not a parallel model.
class JdTailoredExperienceEntryInput {
  const JdTailoredExperienceEntryInput({
    required this.title,
    required this.organization,
    this.when = '',
    this.description = '',
  });

  final String title;
  final String organization;
  final String when;

  /// One line per bullet - blank lines are dropped.
  final String description;

  bool get isBlank => title.trim().isEmpty && organization.trim().isEmpty;
}

/// One project entry the review screen is ready to attach - either a real
/// project the user typed themselves, or an AI-suggested idea the user has
/// already edited into real bullet text and explicitly confirmed via one
/// of the review screen's two actions ("Add as Planned Project" / "I've
/// Actually Completed This"). [status] is always set explicitly by the
/// caller (never left null) - unlike a project added through the normal
/// Project Block Editor, every project this feature creates has a known
/// planned/completed status, since the whole point of this input shape is
/// to record which of the two review-screen actions the user actually
/// took.
class JdTailoredProjectEntryInput {
  const JdTailoredProjectEntryInput({
    required this.name,
    this.link,
    this.bullets = const [],
    required this.status,
  });

  final String name;
  final String? link;
  final List<String> bullets;
  final ProjectBlockStatus status;

  bool get isBlank => name.trim().isEmpty;
}

/// Everything [CreateJdTailoredResumeUseCase] needs, collected across the
/// JD-tailored resume wizard's steps - a plain input DTO, not a persisted
/// model. Every field but [fullName] and [targetRoleLabel] is genuinely
/// optional: leaving it blank means the corresponding resume section is
/// never created, matching `CreateBeginnerResumeUseCase`'s own "no
/// fabrication by omission" rule exactly.
class JdTailoredResumeInput {
  const JdTailoredResumeInput({
    required this.fullName,
    this.phone,
    this.email,
    this.location,
    this.linkedIn,
    this.portfolio,
    required this.targetRoleLabel,
    this.degree,
    this.institution,
    this.graduationYear,
    this.experienceEntries = const [],
    this.projectEntries = const [],
    this.confirmedSkills = const [],
    required this.summaryText,
  });

  final String fullName;
  final String? phone;
  final String? email;
  final String? location;
  final String? linkedIn;
  final String? portfolio;

  /// The JD's own detected title, or whatever the user typed/edited it to
  /// in the wizard.
  final String targetRoleLabel;

  final String? degree;
  final String? institution;
  final String? graduationYear;

  final List<JdTailoredExperienceEntryInput> experienceEntries;

  /// Every project the resume should list - the user's own real projects
  /// (status: completed) plus whichever AI-suggested ideas the user
  /// explicitly confirmed (status: planned or completed, per which
  /// review-screen action they took). An idea the user never acted on is
  /// simply absent here - it was never part of this list to begin with.
  final List<JdTailoredProjectEntryInput> projectEntries;

  /// The user's own typed skills plus whichever JD-recommended skills the
  /// user explicitly accepted at the review screen - never more. A
  /// recommendation the user left unaccepted is simply absent here (see
  /// `GenerateJdTailoredDraftUseCase.recommendedSkills`'s own doc comment
  /// for the "never becomes part of the resume on its own" rule this
  /// mirrors).
  final List<SuggestedSkill> confirmedSkills;

  /// The professional-summary text as the user left it after reviewing
  /// (and optionally editing) `JdTailoredDraft.summaryText` - always
  /// required here since the review screen always shows *some* summary
  /// (AI-generated or the deterministic fallback), never blank.
  final String summaryText;
}

/// Creates a real [Resume] (plus attached blocks) from the JD-tailored
/// resume wizard's reviewed-and-confirmed input - reuses every existing
/// resume repository/model exactly the way `CreateBeginnerResumeUseCase`
/// already does; no parallel resume model or persistence path exists here.
///
/// **The single rule every branch below follows, identical to
/// `CreateBeginnerResumeUseCase`'s own**: a section is only ever created
/// from what [JdTailoredResumeInput] actually carries. Nothing is invented
/// to fill a section. In particular: [JdTailoredResumeInput.confirmedSkills]
/// and [JdTailoredResumeInput.projectEntries] already reflect only what the
/// user explicitly accepted at the review screen - this use case has no
/// separate "which AI suggestions to include" logic of its own, it simply
/// persists exactly what it's given.
class CreateJdTailoredResumeUseCase {
  CreateJdTailoredResumeUseCase({
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required EducationBlockRepository educationBlockRepository,
    required ExperienceBlockRepository experienceBlockRepository,
    required ProjectBlockRepository projectBlockRepository,
    required SkillEntryRepository skillEntryRepository,
    required CustomSectionBlockRepository customSectionBlockRepository,
  })  : _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _educationBlockRepository = educationBlockRepository,
        _experienceBlockRepository = experienceBlockRepository,
        _projectBlockRepository = projectBlockRepository,
        _skillEntryRepository = skillEntryRepository,
        _customSectionBlockRepository = customSectionBlockRepository;

  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final EducationBlockRepository _educationBlockRepository;
  final ExperienceBlockRepository _experienceBlockRepository;
  final ProjectBlockRepository _projectBlockRepository;
  final SkillEntryRepository _skillEntryRepository;
  final CustomSectionBlockRepository _customSectionBlockRepository;

  Future<int> call(JdTailoredResumeInput input) async {
    final now = DateTime.now();
    final roleLabel = _blankToNull(input.targetRoleLabel) ?? 'Tailored';

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
        achievements: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Professional summary - always created, exactly the same mechanism
    // CreateBeginnerResumeUseCase already uses (Resume has no dedicated
    // summary field).
    final summaryId = await _customSectionBlockRepository.insert(
      CustomSectionBlock(
        id: null,
        title: 'Professional Summary',
        entries: [input.summaryText.trim()],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _resumeBlockRepository.attach(resumeId, ResumeBlockType.customSection, summaryId);

    // Education - only if a degree was actually given.
    final degree = _blankToNull(input.degree);
    if (degree != null) {
      final gradYear = _blankToNull(input.graduationYear);
      final dateLabel = gradYear == null ? '' : '$gradYear-06';
      final educationId = await _educationBlockRepository.insert(
        EducationBlock(
          id: null,
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

    // Experience - only entries the user actually described.
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

    // Projects - both the user's own real projects and whichever
    // AI-suggested ideas were explicitly confirmed, each already carrying
    // an explicit status (see JdTailoredProjectEntryInput's own doc
    // comment) - never inferred here.
    for (final entry in input.projectEntries) {
      if (entry.isBlank) continue;
      final projectId = await _projectBlockRepository.insert(
        ProjectBlock(
          id: null,
          name: entry.name.trim(),
          link: _blankToNull(entry.link),
          bullets: entry.bullets.map((b) => b.trim()).where((b) => b.isNotEmpty).toList(),
          status: entry.status,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.project, projectId);
    }

    // Skills - reuses an existing library entry by case-insensitive name,
    // exactly like CreateBeginnerResumeUseCase.
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
