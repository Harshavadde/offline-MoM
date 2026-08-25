import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../repositories/resume_version_repository.dart';

/// Deletes a Resume and everything that belongs only to it - mirrors
/// [DeleteMeetingUseCase]/[DeleteDocumentUseCase]'s shape (orchestrate
/// repositories, no business logic the repositories themselves should
/// own). Library blocks referenced by this resume are untouched: they may
/// still be used by other resumes, so only this resume's *references* to
/// them (its `resume_blocks` rows) are removed, never the blocks
/// themselves.
///
/// Order matters here only in that every step must run: detach the live
/// composition, then remove every saved version (and, via
/// [ResumeVersionRepository.deleteAllForResume], its exported PDF file),
/// then remove the Resume row itself. [ResumeVersionRepository]
/// deliberately owns exported-file cleanup - this use case calls
/// `deleteAllForResume` exactly once and never issues a bulk delete of
/// its own against `resume_versions`, which would silently bypass that
/// cleanup.
class DeleteResumeUseCase {
  DeleteResumeUseCase({
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required ResumeVersionRepository resumeVersionRepository,
  })  : _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _resumeVersionRepository = resumeVersionRepository;

  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final ResumeVersionRepository _resumeVersionRepository;

  Future<void> call(int resumeId) async {
    final blockRefs = await _resumeBlockRepository.getForResume(resumeId);
    for (final ref in blockRefs) {
      await _resumeBlockRepository.detach(resumeId, ref.blockType, ref.blockId);
    }

    await _resumeVersionRepository.deleteAllForResume(resumeId);

    await _resumeRepository.delete(resumeId);
  }
}
