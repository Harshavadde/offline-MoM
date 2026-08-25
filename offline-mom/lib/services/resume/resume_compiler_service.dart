import 'dart:convert';

import '../../models/resume.dart';
import '../../models/resume_block_ref.dart';
import '../../models/resume_block_type.dart';
import '../../models/resume_snapshot.dart';
import '../../models/skill_entry.dart';
import '../../repositories/certification_block_repository.dart';
import '../../repositories/custom_section_block_repository.dart';
import '../../repositories/education_block_repository.dart';
import '../../repositories/experience_block_repository.dart';
import '../../repositories/project_block_repository.dart';
import '../../repositories/skill_entry_repository.dart';

/// Resolves a [Resume]'s live composition into a frozen [ResumeSnapshot] -
/// the single most logic-dense piece of Milestone 1. A stateless, pure
/// service: takes an already-fetched [Resume] and its already-fetched
/// [ResumeBlockRef] composition as plain parameters (not repository calls
/// it makes itself), and resolves each reference against the library
/// repositories injected here. Never persists anything, never renders a
/// PDF, and has no Riverpod/UI dependency - mirrors [ChatExportService]'s
/// shape (a plain class, not an abstract interface, since its own
/// testability comes entirely from the repository interfaces already
/// injected into it, the same reason [ChatExportService] doesn't need one
/// either).
class ResumeCompilerService {
  ResumeCompilerService({
    required ExperienceBlockRepository experienceBlockRepository,
    required EducationBlockRepository educationBlockRepository,
    required ProjectBlockRepository projectBlockRepository,
    required CertificationBlockRepository certificationBlockRepository,
    required SkillEntryRepository skillEntryRepository,
    required CustomSectionBlockRepository customSectionBlockRepository,
  })  : _experienceBlockRepository = experienceBlockRepository,
        _educationBlockRepository = educationBlockRepository,
        _projectBlockRepository = projectBlockRepository,
        _certificationBlockRepository = certificationBlockRepository,
        _skillEntryRepository = skillEntryRepository,
        _customSectionBlockRepository = customSectionBlockRepository;

  final ExperienceBlockRepository _experienceBlockRepository;
  final EducationBlockRepository _educationBlockRepository;
  final ProjectBlockRepository _projectBlockRepository;
  final CertificationBlockRepository _certificationBlockRepository;
  final SkillEntryRepository _skillEntryRepository;
  final CustomSectionBlockRepository _customSectionBlockRepository;

  /// Resolves [blockRefs] (a resume's live composition, any order) against
  /// the library repositories and returns a frozen [ResumeSnapshot].
  ///
  /// Ordering: [blockRefs] is sorted by [ResumeBlockRef.sortOrder] before
  /// resolution, then each ref is dispatched into its own type's resolved
  /// list in that same order - so within each section (Experience,
  /// Education, ...) the resulting list order always matches the
  /// resume's actual composition order, regardless of what order
  /// [blockRefs] arrived in or whether `sort_order` happens to be a
  /// resume-wide or section-scoped sequence at the storage layer.
  ///
  /// A ref whose referenced library block no longer exists (a dangling
  /// reference - not expected once `DeleteLibraryBlockUseCase`'s
  /// orphan-block guard exists, but not structurally impossible before
  /// then) is skipped rather than treated as a fatal error: a resume with
  /// one stale reference should still compile the rest of its content
  /// correctly, not fail entirely. A genuine repository failure (an
  /// exception, not simply "not found") is not caught here and propagates
  /// to the caller unchanged.
  Future<ResumeSnapshot> compile(Resume resume, List<ResumeBlockRef> blockRefs) async {
    final sortedRefs = [...blockRefs]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final experience = <ResolvedExperienceEntry>[];
    final education = <ResolvedEducationEntry>[];
    final projects = <ResolvedProjectEntry>[];
    final certifications = <ResolvedCertificationEntry>[];
    final skills = <ResolvedSkillEntry>[];
    final customSections = <ResolvedCustomSectionEntry>[];

    // SkillEntryRepository has no getById (see §02 of the plan - insert/
    // delete/getAll only), so skill refs are resolved against one
    // getAll() snapshot of the library, fetched at most once per
    // compile() call, rather than re-fetching the whole library per ref.
    Map<int, SkillEntry>? skillsById;

    for (final ref in sortedRefs) {
      switch (ref.blockType) {
        case ResumeBlockType.experience:
          final block = await _experienceBlockRepository.getById(ref.blockId);
          if (block == null) continue;
          experience.add(ResolvedExperienceEntry(
            sourceBlockId: block.id!,
            role: block.role,
            company: block.company,
            location: block.location,
            startDate: block.startDate,
            endDate: block.endDate,
            bullets: _resolveStringListOverride(block.bullets, ref.overrideJson),
            // Sub-projects are not part of the existing bullet-override
            // mechanism (matching ResolvedCertificationEntry's own "no
            // orderable/trimmable sub-content for an override to act on"
            // reasoning) - passed through verbatim from the library
            // block.
            subProjects: block.subProjects,
          ));

        case ResumeBlockType.education:
          final block = await _educationBlockRepository.getById(ref.blockId);
          if (block == null) continue;
          education.add(ResolvedEducationEntry(
            sourceBlockId: block.id!,
            institution: block.institution,
            degree: block.degree,
            fieldOfStudy: block.fieldOfStudy,
            startDate: block.startDate,
            endDate: block.endDate,
            details: _resolveStringListOverride(block.details, ref.overrideJson),
          ));

        case ResumeBlockType.project:
          final block = await _projectBlockRepository.getById(ref.blockId);
          if (block == null) continue;
          projects.add(ResolvedProjectEntry(
            sourceBlockId: block.id!,
            name: block.name,
            link: block.link,
            bullets: _resolveStringListOverride(block.bullets, ref.overrideJson),
          ));

        case ResumeBlockType.certification:
          final block = await _certificationBlockRepository.getById(ref.blockId);
          if (block == null) continue;
          // override_json is never read here - certifications have no
          // orderable/trimmable content for an override to act on, and
          // ResolvedCertificationEntry has no field to put one in even if
          // ref.overrideJson were somehow set.
          certifications.add(ResolvedCertificationEntry(
            sourceBlockId: block.id!,
            name: block.name,
            issuer: block.issuer,
            issuedDate: block.issuedDate,
            credentialUrl: block.credentialUrl,
          ));

        case ResumeBlockType.skill:
          skillsById ??= {
            for (final s in await _skillEntryRepository.getAll())
              if (s.id != null) s.id!: s,
          };
          final block = skillsById[ref.blockId];
          if (block == null) continue;
          // override_json is never read here either - a skill has
          // nothing to trim.
          skills.add(ResolvedSkillEntry(
            sourceBlockId: block.id!,
            name: block.name,
            category: block.category,
          ));

        case ResumeBlockType.customSection:
          final block = await _customSectionBlockRepository.getById(ref.blockId);
          if (block == null) continue;
          // override_json is never read here either - a generic section
          // has nothing to trim, same reasoning as certification/skill.
          customSections.add(ResolvedCustomSectionEntry(
            sourceBlockId: block.id!,
            title: block.title,
            entries: block.entries,
          ));
      }
    }

    return ResumeSnapshot(
      resumeId: resume.id!,
      compiledAt: DateTime.now(),
      profile: ResumeSnapshotProfile(
        fullName: resume.fullName,
        email: resume.email,
        phone: resume.phone,
        location: resume.location,
        links: resume.links,
        roleTagline: resume.targetRole,
      ),
      experience: experience,
      education: education,
      projects: projects,
      certifications: certifications,
      skills: skills,
      customSections: customSections,
    );
  }

  /// Applies [overrideJson] (a JSON-encoded array of strings) to
  /// [original] if present and well-formed. Not specified explicitly by
  /// the frozen plan for the malformed case, so this follows the plan's
  /// own broader production-safety principle - never let a data-shape
  /// problem corrupt or crash the compiler - by falling back to
  /// [original], exactly as if no override were present, rather than
  /// throwing or producing a nonsensical result.
  List<String> _resolveStringListOverride(List<String> original, String? overrideJson) {
    if (overrideJson == null) return original;
    try {
      final decoded = jsonDecode(overrideJson);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Malformed JSON - fall through to the safe fallback below.
    }
    return original;
  }
}
