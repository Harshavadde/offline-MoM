import '../../../models/resume.dart';
import '../../../models/resume_block_ref.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';

/// Thrown when [CreateResumeFromProfileUseCase] is called but no "My
/// Profile" resume has been set up yet.
class NoProfileException implements Exception {
  NoProfileException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Creates a new, job-specific resume seeded from the user's "My Profile"
/// (Product Validation phase, docs/v3/implementation/03-decisions.md) -
/// "MASTER PROFILE -> CREATE RESUME -> optionally tailor for JD -> select
/// template -> export PDF."
///
/// Copies the profile's own Profile fields (name/contact/links/target
/// role) into the new resume so it doesn't start blank, then re-attaches
/// [selectedRefs] (a caller-chosen subset of the profile's own
/// `ResumeBlockRef`s, in their original relative order) to the new resume
/// via the *same* underlying library blocks - never a duplicate copy of
/// an `ExperienceBlock`/`ProjectBlock`/etc row. This is safe by
/// construction: `ResumeBlockRepository.attach` already supports pointing
/// more than one resume at the same block id (confirmed by direct
/// inspection - no ownership/uniqueness check exists), and
/// `setOverride`/`detach` are both scoped to the exact `(resumeId,
/// blockType, blockId)` triple, so anything a job-specific resume does
/// later (JD-tailoring bullet overrides, removing a block from its own
/// composition) can never reach back and mutate the profile's own
/// composition or the shared block data itself.
///
/// The caller decides which of the profile's blocks to include
/// ([selectedRefs]) - "no data should disappear" is satisfied by whatever
/// UI builds that selection defaulting to everything checked, not by this
/// use case silently including more or less than it's told to.
class CreateResumeFromProfileUseCase {
  CreateResumeFromProfileUseCase({
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
  })  : _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository;

  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;

  /// [selectedRefs] must be a subset of the profile's own
  /// `resumeBlockRepository.getForResume(profile.id)` result, already in
  /// the relative order they should appear in the new resume (the same
  /// order `getForResume` itself returns, sorted by `sortOrder`) - this
  /// use case does not re-sort or validate membership; it trusts the
  /// caller's selection screen, which reads that same list.
  Future<int> call({required String title, required List<ResumeBlockRef> selectedRefs}) async {
    final profile = await _resumeRepository.getProfile();
    if (profile == null) {
      throw NoProfileException(
        'Set up My Profile first - there is nothing to create a resume from yet.',
      );
    }

    final now = DateTime.now();
    final newResumeId = await _resumeRepository.insert(Resume(
      id: null,
      title: title,
      targetRole: profile.targetRole,
      fullName: profile.fullName,
      email: profile.email,
      phone: profile.phone,
      location: profile.location,
      links: profile.links,
      achievements: profile.achievements,
      isProfile: false,
      createdAt: now,
      updatedAt: now,
    ));

    for (final ref in selectedRefs) {
      await _resumeBlockRepository.attach(newResumeId, ref.blockType, ref.blockId);
    }

    return newResumeId;
  }
}
