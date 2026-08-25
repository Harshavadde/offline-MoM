import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/job_description.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/documents/parsers/docx_parser.dart';
import '../../../../../services/documents/parsers/pdf_parser.dart';
import '../../../../../services/career/jd_import_file_picker_service.dart';
import '../../import_jd_use_case.dart';

/// Mirrors `ResumeImportUiState`'s exact sealed shape and reasoning
/// (lib/features/career/resume/presentation/providers/resume_import_providers.dart),
/// with a [JdImportConfirmed] terminal state instead of a persisted-and-
/// succeeded one - there is no database row to create for a JD (see the
/// Batch 8 report for why), so "confirm" only means "this draft is ready
/// to be handed to the analysis screen," not "this was saved."
sealed class JdImportUiState {
  const JdImportUiState();
}

class JdImportIdle extends JdImportUiState {
  const JdImportIdle();
}

class JdImportProcessing extends JdImportUiState {
  const JdImportProcessing();
}

class JdImportReviewing extends JdImportUiState {
  const JdImportReviewing(this.draft);
  final ParsedJobDescription draft;
}

class JdImportConfirmed extends JdImportUiState {
  const JdImportConfirmed(this.draft);
  final ParsedJobDescription draft;
}

class JdImportFailed extends JdImportUiState {
  const JdImportFailed(this.message);
  final String message;
}

/// Orchestrates the JD Import screen's flow: pick a file, extract +
/// structure it (via [ImportJdUseCase]), let the user review/confirm.
/// Mirrors `ResumeImportController`'s shape (plain `Notifier`, matching
/// `DocumentImportController`'s established precedent for a one-shot
/// import flow) exactly, minus the persistence step.
class JdImportController extends Notifier<JdImportUiState> {
  @override
  JdImportUiState build() => const JdImportIdle();

  Future<void> pickAndParse() async {
    if (state is JdImportProcessing) return;
    state = const JdImportProcessing();

    try {
      final picked = await ref.read(jdImportFilePickerServiceProvider).pickFile();
      if (picked == null) {
        state = const JdImportIdle();
        return;
      }

      final draft =
          await ref.read(importJdUseCaseProvider).extractAndParse(picked.filePath, picked.sourceType);
      state = JdImportReviewing(draft);
    } on JdImportPickException catch (e) {
      state = JdImportFailed(e.message);
    } on JdImportExtractionException catch (e) {
      state = JdImportFailed(e.message);
    } on PdfReadException catch (e) {
      state = JdImportFailed(e.message);
    } on DocxReadException catch (e) {
      state = JdImportFailed(e.message);
    } catch (e) {
      state = JdImportFailed(friendlyErrorMessage(e));
    }
  }

  /// R-7 §3: parses pasted JD text directly, with no file/extraction step -
  /// reuses [JdParser] (the same parser [pickAndParse] feeds extracted text
  /// into) so a pasted JD is structured identically to an imported one.
  void parseText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    state = JdImportReviewing(ref.read(jdParserProvider).parse(trimmed));
  }

  void confirm() {
    final current = state;
    if (current is! JdImportReviewing) return;
    state = JdImportConfirmed(current.draft);
  }

  void reset() => state = const JdImportIdle();
}

final jdImportControllerProvider = NotifierProvider<JdImportController, JdImportUiState>(
  JdImportController.new,
);
