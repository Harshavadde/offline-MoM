import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/resume.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../models/resume_version.dart';
import '../../../../../providers/app_providers.dart';

/// Every saved version of one Resume, most recent first - mirrors
/// `notesForMeetingProvider`'s exact family-list shape
/// (lib/features/meetings/presentation/providers/notes_providers.dart).
/// `autoDispose` for the same reason `meetingByIdProvider` uses it (see its
/// doc comment): the only consumer will be the Resume Versions screen,
/// watching one resume's versions for as long as that screen is open and no
/// longer. Mutations (save/rename/delete, Batch 5) live on
/// [ResumeVersionController]/`ResumeEditorController`, which call
/// `ref.invalidate(resumeVersionListProvider(resumeId))` to refresh this.
final resumeVersionListProvider =
    FutureProvider.autoDispose.family<List<ResumeVersion>, int>((ref, resumeId) {
  return ref.watch(resumeVersionRepositoryProvider).getForResume(resumeId);
});

/// State for [ResumeVersionController] - a thin busy/error wrapper, not a
/// data cache: the Versions screen's actual list always comes from
/// [resumeVersionListProvider], never from here.
class ResumeVersionControllerState {
  const ResumeVersionControllerState({this.isBusy = false, this.error});

  final bool isBusy;
  final String? error;

  ResumeVersionControllerState copyWith({
    bool? isBusy,
    String? error,
    bool clearError = false,
  }) {
    return ResumeVersionControllerState(
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Manages one Resume's already-saved versions: rename and delete, via the
/// existing [ResumeVersionRepository] directly (there is no
/// "RenameResumeVersionUseCase" - a single-repository metadata update needs
/// no use-case orchestration, the same reasoning `NotesController`'s rename
/// applies to a `Note`). `family` scoped by `resumeId`, `autoDispose` so a
/// second Versions screen (a different resume, or this one reopened later)
/// never reads stale busy/error state left behind by a prior one.
///
/// Saving a *new* version is deliberately not duplicated here - that action
/// belongs to `ResumeEditorController.saveVersion`, the only place that
/// holds the live draft (`Resume` + its `ResumeBlockRef` composition) a new
/// version is compiled from; this controller only ever acts on versions
/// that already exist.
class ResumeVersionController
    extends AutoDisposeFamilyNotifier<ResumeVersionControllerState, int> {
  @override
  ResumeVersionControllerState build(int resumeId) {
    return const ResumeVersionControllerState();
  }

  Future<void> rename(int versionId, String newLabel) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await ref.read(resumeVersionRepositoryProvider).renameLabel(versionId, newLabel);
      state = state.copyWith(isBusy: false);
      ref.invalidate(resumeVersionListProvider(arg));
    } catch (e) {
      state = state.copyWith(isBusy: false, error: friendlyErrorMessage(e));
    }
  }

  Future<void> delete(int versionId) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await ref.read(resumeVersionRepositoryProvider).delete(versionId);
      state = state.copyWith(isBusy: false);
      ref.invalidate(resumeVersionListProvider(arg));
    } catch (e) {
      state = state.copyWith(isBusy: false, error: friendlyErrorMessage(e));
    }
  }

  /// Restores one saved [ResumeVersion]'s frozen content back into this
  /// Resume's *live, editable* composition (docs/v3/01-prd.md §16 - closes
  /// the previously-confirmed "versions are view/export/delete only" gap).
  ///
  /// Deliberately narrow in what it restores, disclosed here rather than
  /// silently assumed:
  /// - **Profile fields** (name/email/phone/location/links) are overwritten
  ///   from the snapshot outright - built via [Resume]'s constructor
  ///   directly, not [Resume.copyWith], since `copyWith`'s `?? this.field`
  ///   semantics can never *clear* a field back to null the way a genuine
  ///   restore needs to if the snapshot's value is null. `title`,
  ///   `targetRole`, and `achievements` are untouched: none of the three
  ///   are captured in a [ResumeSnapshot] today, so there is nothing to
  ///   restore them *from*.
  /// - **Library block references** are rebuilt from each resolved entry's
  ///   `sourceBlockId`, re-attached in the snapshot's own order (so
  ///   `ResumeBlockRepository.attach`'s own "appended at the end"
  ///   sequencing reproduces the original ordering). A `sourceBlockId` that
  ///   no longer exists in its library table (the block was deleted since
  ///   this version was saved) is silently skipped - the same
  ///   dangling-reference-tolerant behavior `ResumeCompilerService.compile`
  ///   already has, applied here to the inverse direction.
  /// - **Per-resume overrides are not reconstructed.** [ResumeSnapshot]
  ///   only ever stores the *already-resolved* bullets/details, with no
  ///   record of whether an override produced them or what the override
  ///   itself contained - restoring re-attaches the original, current
  ///   shared block as-is.
  /// - The resume's current composition is fully replaced, not merged: every
  ///   existing reference is detached first, then the version's own
  ///   references are re-attached - restoring is "go back to exactly this,"
  ///   not "layer this on top of what's here now."
  Future<void> restoreToDraft(int versionId) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final version = await ref.read(resumeVersionRepositoryProvider).getById(versionId);
      if (version == null) {
        state = state.copyWith(
          isBusy: false,
          error: 'This version could not be found. It may have been deleted.',
        );
        return;
      }

      final resumeRepository = ref.read(resumeRepositoryProvider);
      final resume = await resumeRepository.getById(arg);
      if (resume == null) {
        state = state.copyWith(
          isBusy: false,
          error: 'This resume could not be found. It may have been deleted.',
        );
        return;
      }

      final snapshot = version.compiledSnapshot;
      final restoredResume = Resume(
        id: resume.id,
        title: resume.title,
        targetRole: resume.targetRole,
        fullName: snapshot.profile.fullName,
        email: snapshot.profile.email,
        phone: snapshot.profile.phone,
        location: snapshot.profile.location,
        links: snapshot.profile.links,
        achievements: resume.achievements,
        templateId: version.templateId ?? resume.templateId,
        createdAt: resume.createdAt,
        updatedAt: DateTime.now(),
      );
      await resumeRepository.update(restoredResume);

      final blockRepository = ref.read(resumeBlockRepositoryProvider);
      final currentRefs = await blockRepository.getForResume(arg);
      for (final currentRef in currentRefs) {
        await blockRepository.detach(arg, currentRef.blockType, currentRef.blockId);
      }

      final experienceBlockRepository = ref.read(experienceBlockRepositoryProvider);
      for (final entry in snapshot.experience) {
        if (await experienceBlockRepository.getById(entry.sourceBlockId) != null) {
          await blockRepository.attach(arg, ResumeBlockType.experience, entry.sourceBlockId);
        }
      }

      final educationBlockRepository = ref.read(educationBlockRepositoryProvider);
      for (final entry in snapshot.education) {
        if (await educationBlockRepository.getById(entry.sourceBlockId) != null) {
          await blockRepository.attach(arg, ResumeBlockType.education, entry.sourceBlockId);
        }
      }

      final projectBlockRepository = ref.read(projectBlockRepositoryProvider);
      for (final entry in snapshot.projects) {
        if (await projectBlockRepository.getById(entry.sourceBlockId) != null) {
          await blockRepository.attach(arg, ResumeBlockType.project, entry.sourceBlockId);
        }
      }

      final certificationBlockRepository = ref.read(certificationBlockRepositoryProvider);
      for (final entry in snapshot.certifications) {
        if (await certificationBlockRepository.getById(entry.sourceBlockId) != null) {
          await blockRepository.attach(arg, ResumeBlockType.certification, entry.sourceBlockId);
        }
      }

      // SkillEntryRepository has no getById (insert/delete/getAll only,
      // same limitation ResumeCompilerService already works around) - one
      // getAll() snapshot of the library resolves every skill reference,
      // rather than a per-entry query.
      if (snapshot.skills.isNotEmpty) {
        final existingSkillIds = (await ref.read(skillEntryRepositoryProvider).getAll())
            .map((s) => s.id)
            .whereType<int>()
            .toSet();
        for (final entry in snapshot.skills) {
          if (existingSkillIds.contains(entry.sourceBlockId)) {
            await blockRepository.attach(arg, ResumeBlockType.skill, entry.sourceBlockId);
          }
        }
      }

      state = state.copyWith(isBusy: false);
      ref.invalidate(resumeVersionListProvider(arg));
    } catch (e) {
      state = state.copyWith(isBusy: false, error: friendlyErrorMessage(e));
    }
  }
}

final resumeVersionControllerProvider = NotifierProvider.autoDispose
    .family<ResumeVersionController, ResumeVersionControllerState, int>(
  ResumeVersionController.new,
);
