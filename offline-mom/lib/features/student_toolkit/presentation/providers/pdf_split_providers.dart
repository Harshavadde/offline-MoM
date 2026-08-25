import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart';
import '../../../../core/utils/document_title.dart';
import '../../../../services/toolkit/pdf_split_service.dart';
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'toolkit_providers.dart';

enum PdfSplitMode { everyNPages, customBreakpoints }

class PdfPageThumbnail {
  const PdfPageThumbnail({required this.pageIndex, required this.jpegBytes});
  final int pageIndex;
  final Uint8List jpegBytes;
}

/// Picks one PDF, shows a page-thumbnail grid so the user can choose how
/// to divide it (every N pages, or tapping between pages to mark a split
/// point), then produces multiple output PDFs at once. Session-shaped
/// like `ScannerState`/`PdfMergeState`, not a linear pipeline - "how many
/// outputs" isn't known until the user finishes choosing split points.
class PdfSplitState {
  const PdfSplitState({
    this.source,
    this.isBusy = false,
    this.error,
    this.pageThumbnails = const [],
    this.mode = PdfSplitMode.everyNPages,
    this.everyN = 1,
    this.splitAfterPageIndices = const {},
    this.outputs = const [],
    this.savedOutputIndices = const {},
  });

  final PickedToolkitFile? source;
  final bool isBusy;
  final String? error;
  final List<PdfPageThumbnail> pageThumbnails;
  final PdfSplitMode mode;
  final int everyN;
  final Set<int> splitAfterPageIndices;
  final List<PdfSplitOutput> outputs;
  final Set<int> savedOutputIndices;

  int get pageCount => pageThumbnails.length;

  /// The page-index groups the current mode/settings would produce -
  /// computed on demand (cheap: pure list math over an already-loaded
  /// thumbnail list), not stored, so it always reflects the latest mode/
  /// breakpoint/everyN change without a separate "recompute" step.
  List<List<int>> get pageGroups {
    final indices = [for (final t in pageThumbnails) t.pageIndex];
    if (indices.isEmpty) return const [];
    if (mode == PdfSplitMode.everyNPages) {
      final groups = <List<int>>[];
      for (var i = 0; i < indices.length; i += everyN) {
        groups.add(indices.sublist(i, (i + everyN).clamp(0, indices.length)));
      }
      return groups;
    }
    final groups = <List<int>>[];
    var current = <int>[];
    for (final index in indices) {
      current.add(index);
      if (splitAfterPageIndices.contains(index)) {
        groups.add(current);
        current = [];
      }
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  PdfSplitState copyWith({
    PickedToolkitFile? source,
    bool? isBusy,
    String? error,
    bool clearError = false,
    List<PdfPageThumbnail>? pageThumbnails,
    PdfSplitMode? mode,
    int? everyN,
    Set<int>? splitAfterPageIndices,
    List<PdfSplitOutput>? outputs,
    bool clearOutputs = false,
    Set<int>? savedOutputIndices,
  }) {
    return PdfSplitState(
      source: source ?? this.source,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      pageThumbnails: pageThumbnails ?? this.pageThumbnails,
      mode: mode ?? this.mode,
      everyN: everyN ?? this.everyN,
      splitAfterPageIndices: splitAfterPageIndices ?? this.splitAfterPageIndices,
      outputs: clearOutputs ? const [] : (outputs ?? this.outputs),
      savedOutputIndices: clearOutputs ? const {} : (savedOutputIndices ?? this.savedOutputIndices),
    );
  }
}

class PdfSplitController extends Notifier<PdfSplitState> {
  @override
  PdfSplitState build() => const PdfSplitState();

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;
    state = PdfSplitState(source: picked, isBusy: true);
    try {
      final thumbnails = <PdfPageThumbnail>[];
      final tempPaths = <String>[];
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(
            picked.bytes,
            dpi: kPdfThumbnailDpi,
          )) {
        tempPaths.add(page.tempFilePath);
        final bytes = await File(page.tempFilePath).readAsBytes();
        thumbnails.add(PdfPageThumbnail(pageIndex: page.pageIndex, jpegBytes: bytes));
      }
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      thumbnails.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
      state = state.copyWith(pageThumbnails: thumbnails, isBusy: false);
    } on PdfRenderingException catch (e) {
      state = PdfSplitState(source: picked, error: e.message);
    } catch (_) {
      state = PdfSplitState(source: picked, error: 'Could not read this PDF\'s pages.');
    }
  }

  void setMode(PdfSplitMode mode) => state = state.copyWith(mode: mode, clearOutputs: true);

  void setEveryN(int n) {
    if (n < 1) return;
    state = state.copyWith(everyN: n, clearOutputs: true);
  }

  void toggleBreakpointAfter(int pageIndex) {
    final updated = {...state.splitAfterPageIndices};
    if (!updated.add(pageIndex)) updated.remove(pageIndex);
    state = state.copyWith(splitAfterPageIndices: updated, clearOutputs: true);
  }

  Future<void> split() async {
    final source = state.source;
    if (source == null) return;
    final groups = state.pageGroups;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final outputs = await ref.read(pdfSplitServiceProvider).split(
            source.bytes,
            groups,
            renderingService: ref.read(pdfPageRenderingServiceProvider),
            textPreserver: ref.read(pdfSearchableTextPreserverProvider),
            overlayTextFontFallback: await loadOverlayTextFontFallback(ref),
            cropToContent: true,
          );
      state = state.copyWith(isBusy: false, outputs: outputs);
    } on PdfSplitException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not split this PDF. Please try again.');
    }
  }

  Future<ToolkitFile?> saveOutput(int outputIndex) async {
    if (state.savedOutputIndices.contains(outputIndex)) return null;
    final output = state.outputs[outputIndex];
    final source = state.source!;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfSplit, 'pdf');
    await File(outputPath).writeAsBytes(output.bytes);

    final now = DateTime.now();
    final baseTitle = _titleFrom(source.fileName);
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.pdfSplit,
      title: '$baseTitle - ${output.label}',
      outputPath: outputPath,
      fileSizeBytes: output.bytes.lengthInBytes,
      originalFileSizeBytes: null,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: output.pageCount,
    );
    final id = await ref.read(toolkitFileRepositoryProvider).insert(saved);
    ref.invalidate(toolkitFileListProvider);
    state = state.copyWith(savedOutputIndices: {...state.savedOutputIndices, outputIndex});

    return ToolkitFile(
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
  }

  Future<void> saveAll() async {
    for (var i = 0; i < state.outputs.length; i++) {
      await saveOutput(i);
    }
  }

  Future<void> shareOutput(int outputIndex) async {
    final output = state.outputs[outputIndex];
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(output.bytes, name: '${output.label}.pdf', mimeType: 'application/pdf'),
        ],
      ),
    );
  }

  void reset() {
    state = const PdfSplitState();
  }

  // V2.2 Production Hardening, Priority 7 - see pdf_compress_providers
  // .dart's identical fix for the full reasoning (5 files shared this
  // exact naive implementation).
  String _titleFrom(String fileName) => deriveDocumentTitle(fileName);
}

final pdfSplitControllerProvider = NotifierProvider<PdfSplitController, PdfSplitState>(
  PdfSplitController.new,
);
