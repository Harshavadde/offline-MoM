import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/document_title.dart';
import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../models/installed_model.dart';
import '../../../../services/ai/model_catalog.dart';
import '../../../../services/ai/model_lifecycle_manager.dart' show ModelKind;
import '../../../../services/ocr/ocr_text_extraction_service.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart';
import '../../../../services/toolkit/pdf_redaction.dart';
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'toolkit_providers.dart';

/// Productivity Toolkit productization pass (P0-4, ADR-042) - Permanent PDF
/// Redaction, built on `PdfRedactionService` (pixel-burn, `pdf_redaction.dart`
/// / `pdf_redaction_service.dart`), a deliberately separate mechanism from
/// P0-2/P0-3's overlay infrastructure - see ADR-040/ADR-041/ADR-042 for why
/// redaction cannot reuse `PdfOverlayService`.

/// One rasterized page held in memory for a redaction session - its own
/// small type (not `pdf_edit_providers.dart`'s `PdfEditPage`, and not
/// `PdfSplitProviders.PdfPageThumbnail`), matching P0-3's own precedent for
/// why: this feature needs the same shape (`pageIndex`/`jpegBytes`/`width`/
/// `height`) but is otherwise independent of the Edit PDF feature, so
/// coupling the two controllers to one shared struct would only make them
/// harder to evolve separately for a 4-field value type that costs nothing
/// to keep distinct.
class PdfRedactPage {
  const PdfRedactPage({required this.pageIndex, required this.jpegBytes, required this.width, required this.height});
  final int pageIndex;
  final Uint8List jpegBytes;
  final int width;
  final int height;
}

/// One placed redaction region in an editor session - a thin wrapper
/// around [RedactionRegion] (the actual security-relevant value the final
/// PDF is built from) plus the two pieces of bookkeeping only the *editor*
/// needs: [id] (for select/move/resize/delete) and [pageIndex] (which page
/// it belongs to - [RedactionRegion] itself carries no page reference,
/// since [PdfRedactionService] takes that separately, per-page, mirroring
/// `PdfEditAnnotation`'s exact same reasoning in `pdf_edit_providers.dart`).
class PdfRedactMark {
  const PdfRedactMark({required this.id, required this.pageIndex, required this.region});

  final String id;
  final int pageIndex;
  final RedactionRegion region;

  PdfRedactMark copyWith({RedactionRegion? region}) {
    return PdfRedactMark(id: id, pageIndex: pageIndex, region: region ?? this.region);
  }
}

const double _kPdfRedactDpi = kPdfOutputDpi;

class PdfRedactState {
  const PdfRedactState({
    this.source,
    this.pages = const [],
    this.marksByPage = const {},
    this.isBusy = false,
    this.error,
    this.savedFile,
    this.history = const [],
  });

  final PickedToolkitFile? source;
  final List<PdfRedactPage> pages;
  final Map<int, List<PdfRedactMark>> marksByPage;
  final bool isBusy;
  final String? error;
  final ToolkitFile? savedFile;

  /// Snapshots of [marksByPage] pushed before every mutating action -
  /// mirrors `PdfEditState.history`'s exact same simplest-correct
  /// full-map-snapshot approach (this editor's real scale is a handful of
  /// regions across a few pages).
  final List<Map<int, List<PdfRedactMark>>> history;

  bool get isEmpty => source == null;
  bool get canUndo => history.isNotEmpty;
  int get totalRegionCount => marksByPage.values.fold(0, (sum, list) => sum + list.length);

  PdfRedactState copyWith({
    PickedToolkitFile? source,
    List<PdfRedactPage>? pages,
    Map<int, List<PdfRedactMark>>? marksByPage,
    bool? isBusy,
    String? error,
    bool clearError = false,
    ToolkitFile? savedFile,
    List<Map<int, List<PdfRedactMark>>>? history,
  }) {
    return PdfRedactState(
      source: source ?? this.source,
      pages: pages ?? this.pages,
      marksByPage: marksByPage ?? this.marksByPage,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      savedFile: savedFile ?? this.savedFile,
      history: history ?? this.history,
    );
  }
}

class PdfRedactController extends Notifier<PdfRedactState> {
  int _idCounter = 0;

  @override
  PdfRedactState build() => const PdfRedactState();

  String _newId() => 'redaction_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;
    state = PdfRedactState(source: picked, isBusy: true);
    final tempPaths = <String>[];
    try {
      final pages = <PdfRedactPage>[];
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(
            picked.bytes,
            dpi: _kPdfRedactDpi,
            // Must match `applyRedactions`'s own `cropToContent: true` call
            // exactly (same DPI too) - see that method's doc comment on
            // why a mismatch here would misalign redaction coordinates.
            cropToContent: true,
          )) {
        tempPaths.add(page.tempFilePath);
        final bytes = await File(page.tempFilePath).readAsBytes();
        pages.add(PdfRedactPage(pageIndex: page.pageIndex, jpegBytes: bytes, width: page.width, height: page.height));
      }
      pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
      state = state.copyWith(pages: pages, isBusy: false);
    } on PdfRenderingException catch (e) {
      state = PdfRedactState(source: picked, error: e.message);
    } catch (_) {
      state = PdfRedactState(source: picked, error: 'Could not read this PDF\'s pages.');
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  void _pushHistory() {
    state = state.copyWith(
      history: [
        ...state.history,
        {for (final e in state.marksByPage.entries) e.key: List.of(e.value)},
      ],
    );
  }

  void undo() {
    if (state.history.isEmpty) return;
    final previous = state.history.last;
    state = state.copyWith(
      marksByPage: previous,
      history: state.history.sublist(0, state.history.length - 1),
    );
  }

  /// Adds one redaction region to [pageIndex]. Returns the new mark's id
  /// (the canvas selects it immediately afterward for drag/resize).
  String addRegion(int pageIndex, RedactionRegion region) {
    _pushHistory();
    final id = _newId();
    final updated = {...state.marksByPage};
    updated[pageIndex] = [...(updated[pageIndex] ?? const []), PdfRedactMark(id: id, pageIndex: pageIndex, region: region)];
    state = state.copyWith(marksByPage: updated);
    return id;
  }

  void updateRegion(String id, RedactionRegion region) {
    final updated = {
      for (final entry in state.marksByPage.entries)
        entry.key: [
          for (final m in entry.value)
            if (m.id == id) m.copyWith(region: region) else m,
        ],
    };
    state = state.copyWith(marksByPage: updated);
  }

  void deleteRegion(String id) {
    _pushHistory();
    final updated = {
      for (final entry in state.marksByPage.entries) entry.key: entry.value.where((m) => m.id != id).toList(),
    };
    state = state.copyWith(marksByPage: updated);
  }

  /// Builds the final, permanently-redacted PDF bytes - via
  /// `PdfRedactionService`, never `PdfOverlayService`. Does **not** save
  /// anything - the caller (the screen's Preview step) decides whether to
  /// commit to disk, per this pass's own "Preview -> Confirm -> Execute"
  /// requirement. Calling this repeatedly (e.g. re-opening the Preview
  /// dialog) never touches [state.source] - the original picked bytes are
  /// only ever read, never written to or replaced.
  /// B3 (release readiness, R-49) - `textPreserver` is always passed (safe
  /// on every page with **no** redaction region, see
  /// `PdfRedactionService`'s own doc comment for why redaction never reuses
  /// it on a page that *does* have one). `ocrService` is only passed when a
  /// real OCR model is genuinely installed and active - mirrors
  /// `OcrSessionController._run()`'s exact same check - never forcing an
  /// OCR model download just to attempt (optional, best-effort) word-level
  /// text preservation on a redacted page; when no model is installed,
  /// `PdfRedactionService` safely falls back to dropping that page's text
  /// layer entirely rather than guessing.
  Future<Uint8List> buildResultBytes() async {
    final source = state.source;
    if (source == null) throw StateError('No PDF loaded.');
    // Checking whether an OCR model is installed is itself a best-effort
    // opportunistic lookup, never something that should be able to fail
    // Permanent Redaction's actual job (producing a real, safely-redacted
    // PDF) - any failure here (e.g. the AI Model Manager's own database
    // genuinely unavailable) degrades to the same safe "no model" default
    // `PdfRedactionService` already falls back to.
    InstalledModel? installed;
    try {
      installed = await ref.read(installedModelRepositoryProvider).getActiveForKind(ModelKind.ocr);
    } catch (_) {
      installed = null;
    }
    final OcrTextExtractionService? ocrService =
        installed == null ? null : ref.read(ocrTextExtractionServiceProvider);
    final ocrLanguage = installed == null ? 'eng' : (ModelCatalog.byId(installed.modelId)?.version ?? 'eng');
    return ref.read(pdfRedactionServiceProvider).applyRedactions(
          source.bytes,
          renderingService: ref.read(pdfPageRenderingServiceProvider),
          regionsByPage: {
            for (final entry in state.marksByPage.entries) entry.key: entry.value.map((m) => m.region).toList(),
          },
          dpi: _kPdfRedactDpi,
          textPreserver: ref.read(pdfSearchableTextPreserverProvider),
          ocrService: ocrService,
          ocrLanguage: ocrLanguage,
          overlayTextFontFallback: await loadOverlayTextFontFallback(ref),
          // Must match pickPdf's own `cropToContent: true` call above -
          // see PdfRedactionService.applyRedactions's doc comment.
          cropToContent: true,
        );
  }

  Future<ToolkitFile?> save() async {
    final source = state.source;
    if (source == null) return null;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final bytes = await buildResultBytes();
      final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfRedact, 'pdf');
      await File(outputPath).writeAsBytes(bytes);

      final now = DateTime.now();
      final saved = ToolkitFile(
        id: null,
        toolType: ToolkitToolType.pdfRedact,
        title: deriveDocumentTitle(source.fileName),
        outputPath: outputPath,
        fileSizeBytes: bytes.lengthInBytes,
        originalFileSizeBytes: source.sizeBytes,
        isFavorite: false,
        createdAt: now,
        updatedAt: now,
        pageCount: state.pages.length,
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
      state = state.copyWith(isBusy: false, savedFile: withId);
      return withId;
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not save the redacted PDF. Please try again.');
      return null;
    }
  }

  /// Cancel - discards every pending region and the loaded session without
  /// writing anything. Same shape as `PdfEditController.reset()`.
  void reset() {
    state = const PdfRedactState();
  }
}

final pdfRedactControllerProvider = NotifierProvider<PdfRedactController, PdfRedactState>(
  PdfRedactController.new,
);
