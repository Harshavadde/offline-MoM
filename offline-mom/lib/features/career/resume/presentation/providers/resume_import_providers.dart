import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/documents/parsers/docx_parser.dart';
import '../../../../../services/documents/parsers/pdf_parser.dart';
import '../../../../../services/resume/resume_import_file_picker_service.dart';
import '../../../../../services/resume/resume_import_parser.dart';
import '../../import_resume_use_case.dart';
import 'resume_providers.dart';

/// Mirrors `DocumentImportUiState`'s exact sealed shape
/// (lib/features/documents/presentation/providers/document_providers.dart),
/// extended with a [ResumeImportReviewing] state for the review step Batch
/// 7 explicitly requires between extraction and persisting anything -
/// `DocumentImportController`'s simpler pick-then-insert flow has no
/// equivalent step, since a `Document` row is created immediately and
/// filled in by a background pipeline instead.
sealed class ResumeImportUiState {
  const ResumeImportUiState();
}

class ResumeImportIdle extends ResumeImportUiState {
  const ResumeImportIdle();
}

class ResumeImportProcessing extends ResumeImportUiState {
  const ResumeImportProcessing();
}

/// The imported file has been extracted and structured, but nothing has
/// been written to the database yet - [draft] is purely in-memory. [title]
/// is the resume title the user will confirm/edit before import completes,
/// pre-filled from the source filename.
class ResumeImportReviewing extends ResumeImportUiState {
  const ResumeImportReviewing({
    required this.draft,
    required this.title,
    this.isConfirming = false,
    this.isRunningSecondPass = false,
    this.error,
  });

  final ParsedResumeDraft draft;
  final String title;
  final bool isConfirming;

  /// Milestone 4 (docs/v3/01-prd.md §10) - true while the optional
  /// LLM-assisted import second pass is running, so the review screen can
  /// disable its trigger button and show progress the same way
  /// [isConfirming] already does for the persist step.
  final bool isRunningSecondPass;
  final String? error;

  ResumeImportReviewing copyWith({
    String? title,
    bool? isConfirming,
    bool? isRunningSecondPass,
    String? error,
    bool clearError = false,
  }) {
    return ResumeImportReviewing(
      draft: draft,
      title: title ?? this.title,
      isConfirming: isConfirming ?? this.isConfirming,
      isRunningSecondPass: isRunningSecondPass ?? this.isRunningSecondPass,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ResumeImportSucceeded extends ResumeImportUiState {
  const ResumeImportSucceeded(this.resumeId);
  final int resumeId;
}

class ResumeImportFailed extends ResumeImportUiState {
  const ResumeImportFailed(this.message);
  final String message;
}

/// Orchestrates the Resume Import screen's flow: pick a file, extract +
/// structure it (via [ImportResumeUseCase]), let the user review/confirm,
/// then persist. Mirrors `DocumentImportController`'s shape (plain
/// `Notifier`, not `.autoDispose` - matching that exact precedent, the
/// closest existing import flow in this codebase) rather than inventing a
/// different provider lifetime for what is architecturally the same kind
/// of screen.
class ResumeImportController extends Notifier<ResumeImportUiState> {
  @override
  ResumeImportUiState build() => const ResumeImportIdle();

  /// Opens the file picker, extracts and structures the picked file. Does
  /// not persist anything - see [confirmImport] for that step. Every
  /// failure mode this batch's own error-handling list names (unsupported
  /// type, unreadable/empty file, PDF with no extractable text, malformed
  /// DOCX, unexpected file-system failure) surfaces as a single
  /// [ResumeImportFailed] with an already-friendly message - never a raw
  /// stack trace.
  Future<void> pickAndParse() async {
    if (state is ResumeImportProcessing) return;
    state = const ResumeImportProcessing();

    try {
      final picked = await ref.read(resumeImportFilePickerServiceProvider).pickFile();
      if (picked == null) {
        state = const ResumeImportIdle();
        return;
      }

      final draft = await ref
          .read(importResumeUseCaseProvider)
          .extractAndParse(picked.filePath, picked.sourceType);

      final defaultTitle = p.basenameWithoutExtension(picked.originalFilename);
      state = ResumeImportReviewing(
        draft: draft,
        title: defaultTitle.isEmpty ? 'Imported Resume' : defaultTitle,
      );
    } on ResumeImportPickException catch (e) {
      state = ResumeImportFailed(e.message);
    } on ResumeImportExtractionException catch (e) {
      state = ResumeImportFailed(e.message);
    } on PdfReadException catch (e) {
      state = ResumeImportFailed(e.message);
    } on DocxReadException catch (e) {
      state = ResumeImportFailed(e.message);
    } catch (e) {
      state = ResumeImportFailed(friendlyErrorMessage(e));
    }
  }

  void updateTitle(String title) {
    final current = state;
    if (current is! ResumeImportReviewing) return;
    state = current.copyWith(title: title);
  }

  /// Applies [transform] to the current draft (Milestone 4,
  /// docs/v3/01-prd.md §10: "the import review screen becomes per-entry
  /// editable... the user must be able to correct a misclassified line
  /// before import commits") - one generic entry point for every
  /// per-entry edit/remove action the review screen offers, rather than a
  /// separate controller method per entry type/field. Still purely
  /// in-memory: nothing is persisted until [confirmImport].
  void updateDraft(ParsedResumeDraft Function(ParsedResumeDraft draft) transform) {
    final current = state;
    if (current is! ResumeImportReviewing || current.isConfirming) return;
    state = ResumeImportReviewing(
      draft: transform(current.draft),
      title: current.title,
      isConfirming: current.isConfirming,
      isRunningSecondPass: current.isRunningSecondPass,
      error: current.error,
    );
  }

  /// Runs the optional LLM-assisted import second pass (Milestone 4,
  /// docs/v3/01-prd.md §10) over the current draft's still-unclassified
  /// text and merges any newly-structured entries into the draft - purely
  /// in-memory, same as [updateDraft]. User-triggered only (never
  /// automatic): the review screen decides when to show the trigger via
  /// `shouldOfferImportSecondPass`, but running it is always an explicit
  /// action. A model failure or a no-op result both leave the draft
  /// unchanged - see [GenerateImportSecondPassUseCase]'s own doc comment.
  Future<void> runImportSecondPass() async {
    final current = state;
    if (current is! ResumeImportReviewing || current.isConfirming || current.isRunningSecondPass) {
      return;
    }
    state = current.copyWith(isRunningSecondPass: true, clearError: true);

    final merged = await ref.read(generateImportSecondPassUseCaseProvider)(current.draft);

    final afterState = state;
    if (afterState is! ResumeImportReviewing) return;
    state = ResumeImportReviewing(
      draft: merged,
      title: afterState.title,
      isConfirming: afterState.isConfirming,
      isRunningSecondPass: false,
    );
  }

  /// Persists the current draft as a new resume. Stays on
  /// [ResumeImportReviewing] (with [ResumeImportReviewing.error] set) on
  /// failure, rather than discarding the reviewed draft the user already
  /// looked at - the same "don't lose the user's work on a transient
  /// failure" reasoning `ResumeEditorController`'s `actionError` already
  /// follows.
  Future<void> confirmImport() async {
    final current = state;
    if (current is! ResumeImportReviewing || current.isConfirming) return;

    final title = current.title.trim();
    state = current.copyWith(isConfirming: true, clearError: true);

    try {
      final resumeId = await ref
          .read(importResumeUseCaseProvider)
          .confirmImport(current.draft, title: title.isEmpty ? 'Imported Resume' : title);
      ref.invalidate(resumeListProvider);
      state = ResumeImportSucceeded(resumeId);
    } catch (e) {
      state = current.copyWith(isConfirming: false, error: friendlyErrorMessage(e));
    }
  }

  void reset() => state = const ResumeImportIdle();
}

final resumeImportControllerProvider =
    NotifierProvider<ResumeImportController, ResumeImportUiState>(
  ResumeImportController.new,
);
