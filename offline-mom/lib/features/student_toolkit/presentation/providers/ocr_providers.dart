import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/model_catalog.dart';
import '../../../../services/ai/model_lifecycle_manager.dart' show ModelKind;
import '../../../../services/ocr/searchable_pdf_builder_service.dart';
import 'toolkit_providers.dart';

/// P0-7 - the shared "make this searchable" session every entry point
/// (Scanner's "Save Searchable PDF", Images to PDF's "Generate Searchable
/// PDF", and View PDF's "Run OCR") primes with its own already-rasterized
/// pages before navigating to [OcrScreen] - mirrors `ScannerController`'s
/// "state initiated before push, screen is a pure view over it" shape,
/// already established across this Toolkit.
class OcrSessionState {
  const OcrSessionState({
    this.sourcePages = const [],
    this.documentName = '',
    this.language = 'eng',
    this.languageDisplayName = 'English',
    this.isBusy = false,
    this.modelMissing = false,
    this.pagesDone = 0,
    this.pagesTotal = 0,
    this.error,
    this.wasCancelled = false,
    this.resultBytes,
    this.savedFile,
  });

  final List<OcrSourcePage> sourcePages;
  final String documentName;
  final String language;
  final String languageDisplayName;

  /// True while OCR is actually running - drives the progress UI. Not the
  /// same thing as "a session exists": `sourcePages` stays populated after
  /// completion too (e.g. for Retry), so `isBusy` alone tells the screen
  /// whether to show the progress state right now.
  final bool isBusy;

  /// True if no OCR model is installed/active for [language] - checked
  /// *before* ever calling the native OCR plugin (which does not fail
  /// cleanly for a missing model - see `SearchablePdfBuilderService`'s own
  /// doc comment), so this is a clean, catchable state, not a crash.
  final bool modelMissing;

  final int pagesDone;
  final int pagesTotal;
  final String? error;
  final bool wasCancelled;
  final Uint8List? resultBytes;
  final ToolkitFile? savedFile;

  bool get isDone => resultBytes != null;
  double? get progressFraction => pagesTotal == 0 ? null : pagesDone / pagesTotal;

  OcrSessionState copyWith({
    List<OcrSourcePage>? sourcePages,
    String? documentName,
    String? language,
    String? languageDisplayName,
    bool? isBusy,
    bool? modelMissing,
    int? pagesDone,
    int? pagesTotal,
    String? error,
    bool clearError = false,
    bool? wasCancelled,
    Uint8List? resultBytes,
    bool clearResult = false,
    ToolkitFile? savedFile,
  }) {
    return OcrSessionState(
      sourcePages: sourcePages ?? this.sourcePages,
      documentName: documentName ?? this.documentName,
      language: language ?? this.language,
      languageDisplayName: languageDisplayName ?? this.languageDisplayName,
      isBusy: isBusy ?? this.isBusy,
      modelMissing: modelMissing ?? this.modelMissing,
      pagesDone: pagesDone ?? this.pagesDone,
      pagesTotal: pagesTotal ?? this.pagesTotal,
      error: clearError ? null : (error ?? this.error),
      wasCancelled: wasCancelled ?? this.wasCancelled,
      resultBytes: clearResult ? null : (resultBytes ?? this.resultBytes),
      savedFile: savedFile ?? this.savedFile,
    );
  }
}

class OcrSessionController extends Notifier<OcrSessionState> {
  bool _cancelRequested = false;

  @override
  OcrSessionState build() => const OcrSessionState();

  /// Primes a new session and immediately starts processing - called by
  /// every entry point right before `context.push`-ing to [OcrScreen].
  Future<void> start({
    required List<OcrSourcePage> pages,
    required String documentName,
  }) async {
    _cancelRequested = false;
    state = OcrSessionState(sourcePages: pages, documentName: documentName);
    await _run();
  }

  Future<void> retry() async {
    _cancelRequested = false;
    state = state.copyWith(clearError: true, wasCancelled: false, clearResult: true, pagesDone: 0);
    await _run();
  }

  Future<void> _run() async {
    final installed = await ref.read(installedModelRepositoryProvider).getActiveForKind(ModelKind.ocr);
    if (installed == null) {
      state = state.copyWith(modelMissing: true);
      return;
    }
    final spec = ModelCatalog.byId(installed.modelId);
    final language = spec?.version ?? 'eng';
    final languageName = spec?.displayName ?? 'English';

    state = state.copyWith(
      modelMissing: false,
      isBusy: true,
      clearError: true,
      pagesDone: 0,
      pagesTotal: state.sourcePages.length,
      language: language,
      languageDisplayName: languageName,
    );
    try {
      final bytes = await ref.read(searchablePdfBuilderServiceProvider).build(
            state.sourcePages,
            language: language,
            onProgress: (done, total) {
              state = state.copyWith(pagesDone: done, pagesTotal: total);
            },
            isCancelled: () => _cancelRequested,
          );
      state = state.copyWith(isBusy: false, resultBytes: bytes);
    } on SearchablePdfBuilderException catch (e) {
      state = state.copyWith(
        isBusy: false,
        wasCancelled: e.wasCancelled,
        error: e.wasCancelled ? null : e.message,
      );
    } catch (e) {
      state = state.copyWith(isBusy: false, error: friendlyErrorMessage(e));
    }
  }

  void cancel() {
    _cancelRequested = true;
  }

  Future<ToolkitFile?> save() async {
    final bytes = state.resultBytes;
    if (bytes == null) return null;
    if (state.savedFile != null) return state.savedFile;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.ocr, 'pdf');
    await File(outputPath).writeAsBytes(bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.ocr,
      title: state.documentName.isEmpty ? 'Searchable ${_formatTimestamp(now)}' : state.documentName,
      outputPath: outputPath,
      fileSizeBytes: bytes.length,
      originalFileSizeBytes: null,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: state.sourcePages.length,
    );
    final id = await ref.read(toolkitFileRepositoryProvider).insert(saved);
    ref.invalidate(toolkitFileListProvider);

    final withId = ToolkitFile(
      id: id,
      toolType: saved.toolType,
      title: saved.title,
      outputPath: saved.outputPath,
      fileSizeBytes: saved.fileSizeBytes,
      originalFileSizeBytes: saved.originalFileSizeBytes,
      isFavorite: saved.isFavorite,
      createdAt: saved.createdAt,
      updatedAt: saved.updatedAt,
      pageCount: saved.pageCount,
    );
    state = state.copyWith(savedFile: withId);
    return withId;
  }

  void reset() {
    _cancelRequested = false;
    state = const OcrSessionState();
  }

  String _formatTimestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}';
  }
}

final ocrSessionControllerProvider = NotifierProvider<OcrSessionController, OcrSessionState>(
  OcrSessionController.new,
);
