import 'dart:convert';

import '../../../models/resume_block_type.dart';
import '../../../models/resume_snapshot.dart';
import '../../../models/suggested_edit.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../repositories/suggested_edit_repository.dart';
import '../../../services/resume/resume_compiler_service.dart';

/// Thrown when the referenced [SuggestedEdit] id doesn't exist.
class SuggestedEditNotFoundException implements Exception {
  SuggestedEditNotFoundException(this.id);
  final int id;

  @override
  String toString() => 'No suggested edit found with id $id.';
}

/// Thrown when an action requires [SuggestedEdit.status] to still be
/// [SuggestedEditStatus.pending] but it no longer is - the duplicate-
/// action guard: a suggestion can only ever be resolved once through
/// [AcceptSuggestedEditUseCase] or [RejectSuggestedEditUseCase].
class SuggestedEditNotPendingException implements Exception {
  SuggestedEditNotPendingException(this.currentStatus);
  final SuggestedEditStatus currentStatus;

  @override
  String toString() =>
      'This suggestion was already resolved (${currentStatus.name}) and cannot be acted on again.';
}

/// Thrown when a pending [SuggestedEdit] can no longer be safely applied to
/// the live resume - its target section was removed, or the section's
/// content has changed since the suggestion was generated. The user must
/// regenerate suggestions rather than silently overwrite newer content
/// with a stale rewrite.
class SuggestedEditNoLongerApplicableException implements Exception {
  SuggestedEditNoLongerApplicableException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when accepting a suggested edit would mutate "My Profile"
/// (Product Validation phase, docs/v3/implementation/03-decisions.md).
/// This is the actual, permanent-mutation gate the master-profile
/// protection depends on: even if [GenerateResumeSuggestionsUseCase]'s
/// own profile guard were ever bypassed (e.g. a `SuggestedEdit` row left
/// over from before a resume was promoted to "My Profile" - not possible
/// through the app's own UI today, but this use case must not trust that
/// invariant to hold elsewhere), this check is what actually stops
/// [ResumeBlockRepository.setOverride] from ever being called against a
/// profile-flagged resume.
class CannotTailorProfileException implements Exception {
  CannotTailorProfileException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Applies one pending [SuggestedEdit] to the live resume draft
/// (docs/v3/01-prd.md §25 Milestone 3, FR3-10, §22.3) - the *only* code
/// path, anywhere in the app, that ever merges AI-generated text into a
/// resume block (AC3-02). Merges through
/// [ResumeBlockRepository.setOverride], the exact same per-resume-override
/// mechanism `ResumeEditorController.setBlockOverride` already uses for a
/// manual edit - "accepting a suggestion updates the live draft the same
/// way a manual edit would" (FR3-10) is architecturally true here, not
/// merely described that way.
///
/// Re-validates before applying, since acceptance is the last gate before
/// anything reaches live content and must never trust that generation-time
/// state still holds:
/// 1. The suggestion must still exist and still be [SuggestedEditStatus.pending]
///    ([SuggestedEditNotFoundException]/[SuggestedEditNotPendingException] -
///    duplicate-acceptance protection).
/// 2. Its target block must still be attached to this resume
///    ([SuggestedEditNoLongerApplicableException]).
/// 3. The field's *current*, fully-resolved content (via the real
///    [ResumeCompilerService] - never a second resolution implementation)
///    must still match [SuggestedEdit.originalValue] exactly -
///    [SuggestedEditNoLongerApplicableException] if the user (or another
///    accepted suggestion) changed it since generation, rather than
///    silently clobbering a newer edit with a stale one.
///
/// The deterministic `SuggestionFabricationGuard` check is deliberately
/// *not* re-run here: per AC3-03/D-08 it only ever flags for the user's own
/// scrutiny at review time, it never blocks an action - an already-flagged
/// suggestion the user chose to accept anyway is accepted exactly as
/// chosen, never silently blocked as a second opinion.
class AcceptSuggestedEditUseCase {
  AcceptSuggestedEditUseCase({
    required SuggestedEditRepository suggestedEditRepository,
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required ResumeCompilerService compilerService,
  })  : _suggestedEditRepository = suggestedEditRepository,
        _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _compilerService = compilerService;

  final SuggestedEditRepository _suggestedEditRepository;
  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final ResumeCompilerService _compilerService;

  Future<SuggestedEdit> call(int suggestedEditId) async {
    final edit = await _suggestedEditRepository.getById(suggestedEditId);
    if (edit == null) throw SuggestedEditNotFoundException(suggestedEditId);
    if (edit.status != SuggestedEditStatus.pending) {
      throw SuggestedEditNotPendingException(edit.status);
    }

    final blockType = edit.targetBlockType;
    final blockId = edit.targetBlockId;
    if (blockType == null || blockId == null) {
      throw SuggestedEditNoLongerApplicableException(
        'This suggestion has no specific resume section to apply to.',
      );
    }

    final resume = await _resumeRepository.getById(edit.resumeId);
    if (resume == null) {
      throw SuggestedEditNoLongerApplicableException('This resume could not be found.');
    }
    if (resume.isProfile) {
      throw CannotTailorProfileException(
        'My Profile cannot be tailored for a job description - create a resume '
        'from it first, then tailor that resume.',
      );
    }

    final blockRefs = await _resumeBlockRepository.getForResume(edit.resumeId);
    final stillAttached = blockRefs.any((r) => r.blockType == blockType && r.blockId == blockId);
    if (!stillAttached) {
      throw SuggestedEditNoLongerApplicableException(
        'This suggestion no longer applies - that section was removed from the resume.',
      );
    }

    final snapshot = await _compilerService.compile(resume, blockRefs);
    final currentText = _currentFieldText(snapshot, blockType, blockId);
    if (currentText == null) {
      throw SuggestedEditNoLongerApplicableException(
        'This suggestion no longer applies - the content it targeted could not be found.',
      );
    }
    if (currentText != edit.originalValue) {
      throw SuggestedEditNoLongerApplicableException(
        'This section has changed since this suggestion was generated - please regenerate suggestions.',
      );
    }

    final newLines = edit.suggestedValue.split('\n').where((l) => l.trim().isNotEmpty).toList(
          growable: false,
        );
    await _resumeBlockRepository.setOverride(edit.resumeId, blockType, blockId, jsonEncode(newLines));

    final resolvedAt = DateTime.now();
    await _suggestedEditRepository.resolve(suggestedEditId, SuggestedEditStatus.accepted, resolvedAt);

    return edit.copyWith(status: SuggestedEditStatus.accepted, resolvedAt: resolvedAt);
  }

  /// The current, fully-resolved (base block + any existing override)
  /// text of the one field [AcceptSuggestedEditUseCase] ever merges into -
  /// `bullets` for experience/project, `details` for education. Null for
  /// any block not found in [snapshot], or for a block type this
  /// milestone doesn't generate suggestions for (certification/skill have
  /// no override-capable field - see `ResumeCompilerService`'s own doc
  /// comment).
  String? _currentFieldText(ResumeSnapshot snapshot, ResumeBlockType blockType, int blockId) {
    switch (blockType) {
      case ResumeBlockType.experience:
        for (final entry in snapshot.experience) {
          if (entry.sourceBlockId == blockId) return entry.bullets.join('\n');
        }
        return null;
      case ResumeBlockType.education:
        for (final entry in snapshot.education) {
          if (entry.sourceBlockId == blockId) return entry.details.join('\n');
        }
        return null;
      case ResumeBlockType.project:
        for (final entry in snapshot.projects) {
          if (entry.sourceBlockId == blockId) return entry.bullets.join('\n');
        }
        return null;
      case ResumeBlockType.certification:
      case ResumeBlockType.skill:
      case ResumeBlockType.customSection:
        return null;
    }
  }
}
