import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../../../core/utils/document_title.dart';
import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/pdf_overlay.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart';
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'toolkit_providers.dart';

/// Productivity Toolkit productization pass (P0-3, ADR-041) - Add Text,
/// Signatures, Annotations, and Watermark, all built on the shared
/// `PdfOverlayElement`/`PdfOverlayService` foundation (P0-2, ADR-040) -
/// never a separate rendering/editing mechanism per tool.
enum PdfEditTool { none, text, signature, highlight, underline, strikethrough, freehand, rectangle, arrow }

/// One rasterized page, kept in memory for the life of an editing session.
/// Deliberately its own type rather than reusing `PdfSplitProviders`'
/// `PdfPageThumbnail` - that struct only carries `pageIndex`/`jpegBytes`
/// (enough for a thumbnail *grid*, where every tile is laid out by the grid
/// itself), but the editor's canvas needs the page's own pixel dimensions
/// to fit a *single* page into its available box and convert screen-space
/// drags to normalized coordinates ([RasterizedPdfPage] already carries
/// them - this type just keeps them instead of discarding them like
/// `PdfSplitController.pickPdf` does).
class PdfEditPage {
  const PdfEditPage({required this.pageIndex, required this.jpegBytes, required this.width, required this.height});
  final int pageIndex;
  final Uint8List jpegBytes;
  final int width;
  final int height;
}

/// One placed annotation in an editor session - a thin wrapper around the
/// same [PdfOverlayElement] the final PDF is built from (never a parallel
/// representation), plus the two pieces of bookkeeping only the *editor*
/// needs: [id] (for select/move/resize/delete) and [pageIndex] (which page
/// it belongs to - [PdfOverlayElement] itself carries no page reference,
/// since [PdfOverlayService] takes that separately, per-page).
class PdfEditAnnotation {
  const PdfEditAnnotation({required this.id, required this.pageIndex, required this.element});

  final String id;
  final int pageIndex;
  final PdfOverlayElement element;

  PdfEditAnnotation copyWith({PdfOverlayElement? element}) {
    return PdfEditAnnotation(id: id, pageIndex: pageIndex, element: element ?? this.element);
  }
}

/// Editing at this DPI (not `kPdfThumbnailDpi`, which `PdfOrganizeController`
/// uses for its own small page-grid thumbnails) - a full-screen single-page
/// editing surface needs to stay legible enough to place annotations
/// precisely, which a 72dpi thumbnail is not. A real, disclosed memory-usage
/// tradeoff versus Organize's thumbnail grid: every page of the source PDF
/// is held in memory at this resolution for the life of the editing
/// session, not just the current page - acceptable for this app's realistic
/// document sizes (a few to a few dozen pages), not verified against a
/// deliberately huge (hundreds-of-pages) PDF.
const double _kPdfEditDpi = kPdfOutputDpi;

class PdfEditState {
  const PdfEditState({
    this.source,
    this.pages = const [],
    this.annotationsByPage = const {},
    this.activeTool = PdfEditTool.none,
    this.isBusy = false,
    this.error,
    this.savedFile,
    this.history = const [],
  });

  final PickedToolkitFile? source;
  final List<PdfEditPage> pages;
  final Map<int, List<PdfEditAnnotation>> annotationsByPage;
  final PdfEditTool activeTool;
  final bool isBusy;
  final String? error;
  final ToolkitFile? savedFile;

  /// Snapshots of [annotationsByPage] pushed before every mutating action -
  /// `undo()` pops the most recent one. A full-map snapshot per action
  /// (not a diff/command log) - simplest-correct given this editor's real
  /// scale (a handful to a few dozen annotations across a few pages, not a
  /// large document-wide edit history), matching this app's own "don't
  /// over-engineer for a scale that doesn't exist" discipline.
  final List<Map<int, List<PdfEditAnnotation>>> history;

  bool get isEmpty => source == null;
  bool get canUndo => history.isNotEmpty;
  int get totalAnnotationCount => annotationsByPage.values.fold(0, (sum, list) => sum + list.length);

  PdfEditState copyWith({
    PickedToolkitFile? source,
    List<PdfEditPage>? pages,
    Map<int, List<PdfEditAnnotation>>? annotationsByPage,
    PdfEditTool? activeTool,
    bool? isBusy,
    String? error,
    bool clearError = false,
    ToolkitFile? savedFile,
    List<Map<int, List<PdfEditAnnotation>>>? history,
  }) {
    return PdfEditState(
      source: source ?? this.source,
      pages: pages ?? this.pages,
      annotationsByPage: annotationsByPage ?? this.annotationsByPage,
      activeTool: activeTool ?? this.activeTool,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      savedFile: savedFile ?? this.savedFile,
      history: history ?? this.history,
    );
  }
}

class PdfEditController extends Notifier<PdfEditState> {
  int _idCounter = 0;

  @override
  PdfEditState build() => const PdfEditState();

  String _newId() => 'annotation_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;
    state = PdfEditState(source: picked, isBusy: true);
    final tempPaths = <String>[];
    try {
      final pages = <PdfEditPage>[];
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(
            picked.bytes,
            dpi: _kPdfEditDpi,
            // Must match buildResultBytes's own `cropToContent: true` call
            // exactly (same DPI too) - see PdfOverlayService.applyOverlays's
            // doc comment on why a mismatch here would misplace annotations.
            cropToContent: true,
          )) {
        tempPaths.add(page.tempFilePath);
        final bytes = await File(page.tempFilePath).readAsBytes();
        pages.add(PdfEditPage(pageIndex: page.pageIndex, jpegBytes: bytes, width: page.width, height: page.height));
      }
      pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
      state = state.copyWith(pages: pages, isBusy: false);
    } on PdfRenderingException catch (e) {
      state = PdfEditState(source: picked, error: e.message);
    } catch (_) {
      state = PdfEditState(source: picked, error: 'Could not read this PDF\'s pages.');
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  void selectTool(PdfEditTool tool) {
    state = state.copyWith(activeTool: state.activeTool == tool ? PdfEditTool.none : tool);
  }

  void _pushHistory() {
    state = state.copyWith(
      history: [
        ...state.history,
        {for (final e in state.annotationsByPage.entries) e.key: List.of(e.value)},
      ],
    );
  }

  void undo() {
    if (state.history.isEmpty) return;
    final previous = state.history.last;
    state = state.copyWith(
      annotationsByPage: previous,
      history: state.history.sublist(0, state.history.length - 1),
    );
  }

  /// Adds one annotation to [pageIndex] - the single mutation path every
  /// tool (text/signature/highlight/underline/strikethrough/freehand/
  /// rectangle/arrow) funnels through, so undo/history bookkeeping exists
  /// in exactly one place. Returns the new annotation's id (callers that
  /// need to immediately select it for drag/resize use this).
  String addAnnotation(int pageIndex, PdfOverlayElement element) {
    _pushHistory();
    final id = _newId();
    final updated = {...state.annotationsByPage};
    updated[pageIndex] = [...(updated[pageIndex] ?? const []), PdfEditAnnotation(id: id, pageIndex: pageIndex, element: element)];
    state = state.copyWith(annotationsByPage: updated);
    return id;
  }

  void updateAnnotation(String id, PdfOverlayElement element) {
    final updated = {
      for (final entry in state.annotationsByPage.entries)
        entry.key: [
          for (final a in entry.value)
            if (a.id == id) a.copyWith(element: element) else a,
        ],
    };
    state = state.copyWith(annotationsByPage: updated);
  }

  void deleteAnnotation(String id) {
    _pushHistory();
    final updated = {
      for (final entry in state.annotationsByPage.entries) entry.key: entry.value.where((a) => a.id != id).toList(),
    };
    state = state.copyWith(annotationsByPage: updated);
  }

  /// Applies one text watermark to *every* page at once (Watermark, #35 -
  /// distinct from every other tool, which places on exactly one page the
  /// user is looking at) - a single mutation, one history entry, not one
  /// per page (undoing a watermark should remove it from every page in one
  /// step, matching what the user actually did).
  void applyWatermark(String text, {double fontSize = 48, double opacity = 0.3, double rotationDegrees = -45}) {
    _pushHistory();
    final updated = {...state.annotationsByPage};
    for (var i = 0; i < state.pages.length; i++) {
      final element = PdfOverlayText(
        text: text,
        x: 0.5,
        y: 0.5,
        fontSize: fontSize,
        color: PdfColors.grey700,
        rotationDegrees: rotationDegrees,
        opacity: opacity,
      );
      updated[i] = [...(updated[i] ?? const []), PdfEditAnnotation(id: _newId(), pageIndex: i, element: element)];
    }
    state = state.copyWith(annotationsByPage: updated);
  }

  /// Builds the final PDF bytes with every annotation baked in, via the
  /// exact same `PdfOverlayService` every other overlay-based tool uses -
  /// never a preview-only render. Does **not** save anything - the caller
  /// (the screen's Preview step) decides whether to commit to disk, per
  /// this pass's own "Preview -> Confirm -> Execute" requirement for
  /// destructive-adjacent operations.
  Future<Uint8List> buildResultBytes() async {
    final source = state.source;
    if (source == null) throw StateError('No PDF loaded.');
    return ref.read(pdfOverlayServiceProvider).applyOverlays(
          source.bytes,
          renderingService: ref.read(pdfPageRenderingServiceProvider),
          overlaysByPage: {
            for (final entry in state.annotationsByPage.entries) entry.key: entry.value.map((a) => a.element).toList(),
          },
          dpi: _kPdfEditDpi,
          textPreserver: ref.read(pdfSearchableTextPreserverProvider),
          overlayTextFontFallback: await loadOverlayTextFontFallback(ref),
          // Must match this controller's own canvas-loading call above -
          // see PdfOverlayService.applyOverlays's doc comment.
          cropToContent: true,
        );
  }

  Future<ToolkitFile?> save() async {
    final source = state.source;
    if (source == null) return null;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final bytes = await buildResultBytes();
      final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfEdit, 'pdf');
      await File(outputPath).writeAsBytes(bytes);

      final now = DateTime.now();
      final saved = ToolkitFile(
        id: null,
        toolType: ToolkitToolType.pdfEdit,
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
      state = state.copyWith(isBusy: false, error: 'Could not save this PDF. Please try again.');
      return null;
    }
  }

  void reset() {
    state = const PdfEditState();
  }
}

final pdfEditControllerProvider = NotifierProvider<PdfEditController, PdfEditState>(
  PdfEditController.new,
);
