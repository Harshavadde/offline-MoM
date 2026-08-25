import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/resume.dart';
import '../../../../../models/resume_block_ref.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../models/resume_link.dart';
import '../../../../../models/resume_snapshot.dart';
import '../../../../../models/resume_version.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/resume/template/resume_template_catalog.dart';
import '../../delete_library_block_use_case.dart';
import 'resume_providers.dart';
import 'resume_version_providers.dart';

/// State for [ResumeEditorController] - one Resume's live, in-progress
/// composition. Sealed so every screen reading it must handle all three
/// cases explicitly, mirroring `ScannerState`'s own loading/ready/error
/// shape (lib/features/student_toolkit/presentation/providers/scanner_providers.dart).
sealed class ResumeEditorUiState {
  const ResumeEditorUiState();
}

class ResumeEditorLoading extends ResumeEditorUiState {
  const ResumeEditorLoading();
}

class ResumeEditorLoadError extends ResumeEditorUiState {
  const ResumeEditorLoadError(this.message);

  final String message;
}

class ResumeEditorReady extends ResumeEditorUiState {
  const ResumeEditorReady({
    required this.resume,
    required this.blockRefs,
    this.isSaving = false,
    this.actionError,
  });

  final Resume resume;

  /// The full live composition, already sorted by `sortOrder` (ascending) -
  /// `ResumeBlockRepository.getForResume`'s own ordering guarantee.
  final List<ResumeBlockRef> blockRefs;

  /// True while any mutation (profile edit, attach/detach/reorder, save
  /// version, preview) is in flight - screens use this to disable actions,
  /// not to show a full-screen spinner over already-loaded content.
  final bool isSaving;

  /// Set when the most recent action failed; cleared at the start of the
  /// next action. Never a raw exception - always [friendlyErrorMessage], or
  /// (for a blocked "Delete from library") [BlockInUseException]'s own
  /// already-specific message.
  final String? actionError;

  List<ResumeBlockRef> refsOf(ResumeBlockType type) =>
      blockRefs.where((r) => r.blockType == type).toList(growable: false);

  ResumeEditorReady copyWith({
    Resume? resume,
    List<ResumeBlockRef>? blockRefs,
    bool? isSaving,
    String? actionError,
    bool clearActionError = false,
  }) {
    return ResumeEditorReady(
      resume: resume ?? this.resume,
      blockRefs: blockRefs ?? this.blockRefs,
      isSaving: isSaving ?? this.isSaving,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }
}

/// Owns one Resume's live Editor session: Profile edits, block attach/
/// detach/reorder, Save Version, and Preview of the *current, unsaved*
/// draft. `family` scoped by `resumeId`, `autoDispose` so a second Editor
/// session (a different resume, or the same one reopened later) never reads
/// stale state left behind by a prior one - there is no precedent for
/// `NotifierProvider.autoDispose.family` elsewhere in this codebase, so this
/// is the first, following Riverpod 2.x's own documented shape for it.
///
/// IMPORTANT PREVIEW DECISION (frozen for Batch 5, do not reinterpret):
/// [preview] compiles [blockRefs] directly via `ResumeCompilerService`/
/// `ResumePdfExportService` - it never requires or reads a saved
/// [ResumeVersion]. Saving a version and previewing the draft are two
/// independent actions.
///
/// Undo for detach is deliberately not implemented here, despite the
/// earlier Milestone 1 design notes suggesting a `ScannerController`-style
/// undo affordance - Batch 5's own instructions explicitly rule out adding
/// undo functionality, which supersedes that earlier note.
class ResumeEditorController
    extends AutoDisposeFamilyNotifier<ResumeEditorUiState, int> {
  @override
  ResumeEditorUiState build(int resumeId) {
    _load(resumeId);
    return const ResumeEditorLoading();
  }

  Future<void> _load(int resumeId) async {
    try {
      final resume = await ref.read(resumeRepositoryProvider).getById(resumeId);
      if (resume == null) {
        state = const ResumeEditorLoadError(
          'This resume could not be found. It may have been deleted.',
        );
        return;
      }
      final blockRefs =
          await ref.read(resumeBlockRepositoryProvider).getForResume(resumeId);
      state = ResumeEditorReady(resume: resume, blockRefs: blockRefs);
    } catch (e) {
      state = ResumeEditorLoadError(friendlyErrorMessage(e));
    }
  }

  /// Re-fetches the Resume + composition from scratch - used after an
  /// external screen (a Block Editor) may have changed library data this
  /// Editor references, and by tests that want to confirm a write actually
  /// persisted rather than trusting only in-memory state.
  Future<void> reload() => _load(arg);

  Future<void> updateProfile({
    String? title,
    String? targetRole,
    String? fullName,
    String? email,
    String? phone,
    String? location,
    List<ResumeLink>? links,
  }) async {
    final current = state;
    if (current is! ResumeEditorReady || current.isSaving) return;

    state = current.copyWith(isSaving: true, clearActionError: true);
    try {
      final updated = current.resume.copyWith(
        title: title,
        targetRole: targetRole,
        fullName: fullName,
        email: email,
        phone: phone,
        location: location,
        links: links,
        updatedAt: DateTime.now(),
      );
      await ref.read(resumeRepositoryProvider).update(updated);
      state = current.copyWith(resume: updated, isSaving: false);
      ref.invalidate(resumeListProvider);
      ref.invalidate(resumeByIdProvider(arg));
    } catch (e) {
      state = current.copyWith(isSaving: false, actionError: friendlyErrorMessage(e));
    }
  }

  Future<void> attachBlock(ResumeBlockType blockType, int blockId) async {
    final current = state;
    if (current is! ResumeEditorReady || current.isSaving) return;

    state = current.copyWith(isSaving: true, clearActionError: true);
    try {
      await ref.read(resumeBlockRepositoryProvider).attach(arg, blockType, blockId);
      await _refreshComposition(current);
    } catch (e) {
      state = current.copyWith(isSaving: false, actionError: friendlyErrorMessage(e));
    }
  }

  /// Removes the block from *this resume's composition only* - the shared
  /// library block, and any other resume's reference to it, is untouched.
  /// Never deletes the library block itself; see [deleteBlockFromLibrary]
  /// for that separate action.
  Future<void> detachBlock(ResumeBlockType blockType, int blockId) async {
    final current = state;
    if (current is! ResumeEditorReady || current.isSaving) return;

    state = current.copyWith(isSaving: true, clearActionError: true);
    try {
      await ref.read(resumeBlockRepositoryProvider).detach(arg, blockType, blockId);
      await _refreshComposition(current);
    } catch (e) {
      state = current.copyWith(isSaving: false, actionError: friendlyErrorMessage(e));
    }
  }

  /// Persists a new order for every ref in [reorderedSection] (one block
  /// type's slice of [ResumeEditorReady.blockRefs], already in its new
  /// order) - mirrors `ScannerController.reorderPage`'s intent, backed here
  /// by `ResumeBlockRepository.reorder`'s single-transaction write.
  Future<void> reorderSection(List<ResumeBlockRef> reorderedSection) async {
    final current = state;
    if (current is! ResumeEditorReady || current.isSaving) return;

    state = current.copyWith(isSaving: true, clearActionError: true);
    try {
      await ref.read(resumeBlockRepositoryProvider).reorder(arg, reorderedSection);
      await _refreshComposition(current);
    } catch (e) {
      state = current.copyWith(isSaving: false, actionError: friendlyErrorMessage(e));
    }
  }

  /// Sets or clears a per-resume bullet-list override for one attached
  /// block - never touches the shared library block. Only meaningful for
  /// `experience`/`education`/`project` refs; `ResumeCompilerService` never
  /// reads `overrideJson` for `certification`/`skill` refs (see its own
  /// doc comment), so calling this for those types has no visible effect
  /// on a compiled resume, but is not itself blocked here - the same
  /// permissive shape `setOverride`'s own repository contract already has.
  /// Pass `null` to clear back to the library block's own content.
  Future<void> setBlockOverride(
    ResumeBlockType blockType,
    int blockId,
    List<String>? overrideBullets,
  ) async {
    final current = state;
    if (current is! ResumeEditorReady || current.isSaving) return;

    state = current.copyWith(isSaving: true, clearActionError: true);
    try {
      await ref.read(resumeBlockRepositoryProvider).setOverride(
            arg,
            blockType,
            blockId,
            overrideBullets == null ? null : jsonEncode(overrideBullets),
          );
      await _refreshComposition(current);
    } catch (e) {
      state = current.copyWith(isSaving: false, actionError: friendlyErrorMessage(e));
    }
  }

  Future<void> _refreshComposition(ResumeEditorReady current) async {
    final blockRefs = await ref.read(resumeBlockRepositoryProvider).getForResume(arg);
    state = current.copyWith(blockRefs: blockRefs, isSaving: false);
  }

  /// Compiles a new, permanent [ResumeVersion] from the *current* live
  /// composition via `SaveResumeVersionUseCase`, then invalidates
  /// `resumeVersionListProvider(resumeId)` so the Versions screen picks it
  /// up. Rethrows on failure (after recording [ResumeEditorReady.actionError])
  /// so a caller showing its own snackbar/dialog can react too.
  Future<ResumeVersion> saveVersion(String versionLabel) async {
    final current = state;
    if (current is! ResumeEditorReady) {
      throw StateError('Cannot save a version before the Editor has loaded.');
    }
    if (current.isSaving) {
      throw StateError('A save is already in progress.');
    }

    state = current.copyWith(isSaving: true, clearActionError: true);
    try {
      final version = await ref.read(saveResumeVersionUseCaseProvider)(
        current.resume,
        current.blockRefs,
        versionLabel: versionLabel,
      );
      state = current.copyWith(isSaving: false);
      ref.invalidate(resumeVersionListProvider(arg));
      return version;
    } catch (e) {
      state = current.copyWith(isSaving: false, actionError: friendlyErrorMessage(e));
      rethrow;
    }
  }

  /// Compiles the *current, unsaved* draft directly (never a saved
  /// [ResumeVersion]) and renders it to PDF bytes for the Preview screen -
  /// see this class's own doc comment for why that's frozen, not a design
  /// choice this method can drift from later.
  Future<Uint8List> preview() async {
    final current = state;
    if (current is! ResumeEditorReady) {
      throw StateError('Cannot preview before the Editor has loaded.');
    }
    final snapshot = await compileSnapshot();
    final templateSpec = ResumeTemplateCatalog.specById(current.resume.templateId);
    return ref.read(resumePdfExportServiceProvider).render(snapshot, templateSpec: templateSpec);
  }

  /// Compiles the current, unsaved draft into a [ResumeSnapshot] without
  /// rendering it to any output format - the same live-draft compile
  /// [preview] itself uses, exposed separately so a plain-text/Markdown
  /// export (Batch 6, `ResumeTextExportService`) can format the identical
  /// resolved data without going through the PDF renderer to get it.
  Future<ResumeSnapshot> compileSnapshot() async {
    final current = state;
    if (current is! ResumeEditorReady) {
      throw StateError('Cannot compile before the Editor has loaded.');
    }
    return ref.read(resumeCompilerServiceProvider).compile(current.resume, current.blockRefs);
  }

  /// Deletes [blockId] from its library entirely via
  /// [DeleteLibraryBlockUseCase] - never a direct repository `delete()`.
  /// Throws [BlockInUseException] (unchanged, for the caller to catch and
  /// show) if any resume, including this one, still references it; a block
  /// currently attached to *this* resume will always be reported as
  /// in-use by this resume's own title until it's detached first.
  ///
  /// On success, refreshes this Editor's composition (the block cannot have
  /// been part of it, or deletion would have failed above) so nothing
  /// stale lingers, though in practice nothing here changes when deletion
  /// succeeds.
  Future<void> deleteBlockFromLibrary(ResumeBlockType blockType, int blockId) async {
    final current = state;
    if (current is! ResumeEditorReady || current.isSaving) return;

    state = current.copyWith(isSaving: true, clearActionError: true);
    try {
      await ref.read(deleteLibraryBlockUseCaseProvider)(blockType, blockId);
      await _refreshComposition(current);
    } on BlockInUseException catch (e) {
      state = current.copyWith(isSaving: false, actionError: e.toString());
      rethrow;
    } catch (e) {
      state = current.copyWith(isSaving: false, actionError: friendlyErrorMessage(e));
      rethrow;
    }
  }
}

final resumeEditorControllerProvider = NotifierProvider.autoDispose
    .family<ResumeEditorController, ResumeEditorUiState, int>(
  ResumeEditorController.new,
);
