import '../../../models/resume_block_type.dart';
import '../../../repositories/certification_block_repository.dart';
import '../../../repositories/custom_section_block_repository.dart';
import '../../../repositories/education_block_repository.dart';
import '../../../repositories/experience_block_repository.dart';
import '../../../repositories/project_block_repository.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../repositories/skill_entry_repository.dart';

/// Thrown by [DeleteLibraryBlockUseCase] when the block is still referenced
/// by one or more resumes - the block is never deleted in this case.
/// [resumeTitles] names them, for a message specific enough to act on
/// ("used in 2 resumes: Backend-Focused, Full-Stack"), not a generic
/// refusal.
class BlockInUseException implements Exception {
  const BlockInUseException(this.resumeTitles);

  final List<String> resumeTitles;

  @override
  String toString() =>
      'This block is used in ${resumeTitles.length} resume(s): ${resumeTitles.join(', ')}.';
}

/// Enforces the orphan-block policy: a library block (Experience/
/// Education/Project/Certification/Skill) can only be deleted once no
/// resume references it. This is the *only* place that check runs - none
/// of the five library repositories depend on [ResumeBlockRepository] or
/// on each other, so the cross-repository orchestration this check
/// requires lives here, one layer up, exactly as frozen for M1.
class DeleteLibraryBlockUseCase {
  DeleteLibraryBlockUseCase({
    required ResumeBlockRepository resumeBlockRepository,
    required ResumeRepository resumeRepository,
    required ExperienceBlockRepository experienceBlockRepository,
    required EducationBlockRepository educationBlockRepository,
    required ProjectBlockRepository projectBlockRepository,
    required CertificationBlockRepository certificationBlockRepository,
    required SkillEntryRepository skillEntryRepository,
    required CustomSectionBlockRepository customSectionBlockRepository,
  })  : _resumeBlockRepository = resumeBlockRepository,
        _resumeRepository = resumeRepository,
        _experienceBlockRepository = experienceBlockRepository,
        _educationBlockRepository = educationBlockRepository,
        _projectBlockRepository = projectBlockRepository,
        _certificationBlockRepository = certificationBlockRepository,
        _skillEntryRepository = skillEntryRepository,
        _customSectionBlockRepository = customSectionBlockRepository;

  final ResumeBlockRepository _resumeBlockRepository;
  final ResumeRepository _resumeRepository;
  final ExperienceBlockRepository _experienceBlockRepository;
  final EducationBlockRepository _educationBlockRepository;
  final ProjectBlockRepository _projectBlockRepository;
  final CertificationBlockRepository _certificationBlockRepository;
  final SkillEntryRepository _skillEntryRepository;
  final CustomSectionBlockRepository _customSectionBlockRepository;

  /// Deletes the [blockType]/[blockId] library block, or throws
  /// [BlockInUseException] if any resume still references it. [blockType]
  /// is a closed enum (experience/education/project/certification/skill/
  /// customSection), so every case is handled below by construction -
  /// there is no "unknown block type" this method can ever be called with.
  Future<void> call(ResumeBlockType blockType, int blockId) async {
    final referencingResumeIds = await _resumeBlockRepository.getReferencingResumeIds(
      blockType,
      blockId,
    );

    if (referencingResumeIds.isNotEmpty) {
      final titles = <String>[];
      for (final resumeId in referencingResumeIds) {
        final resume = await _resumeRepository.getById(resumeId);
        if (resume != null) titles.add(resume.title);
      }
      throw BlockInUseException(titles);
    }

    switch (blockType) {
      case ResumeBlockType.experience:
        await _experienceBlockRepository.delete(blockId);
      case ResumeBlockType.education:
        await _educationBlockRepository.delete(blockId);
      case ResumeBlockType.project:
        await _projectBlockRepository.delete(blockId);
      case ResumeBlockType.certification:
        await _certificationBlockRepository.delete(blockId);
      case ResumeBlockType.skill:
        await _skillEntryRepository.delete(blockId);
      case ResumeBlockType.customSection:
        await _customSectionBlockRepository.delete(blockId);
    }
  }
}
