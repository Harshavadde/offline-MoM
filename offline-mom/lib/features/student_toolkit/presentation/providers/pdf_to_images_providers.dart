import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart';
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'pdf_split_providers.dart' show PdfPageThumbnail;
import 'toolkit_providers.dart';

/// PDF -> Images (Productivity Toolkit productization pass, P0-6) - export
/// all or selected pages of an existing PDF as real JPEG image files, one
/// output per page. Built entirely on `PdfPageRenderingService
/// .rasterizePages` (the same rasterization primitive Compress/Merge/
/// Split/Organize already use) - no new rasterization mechanism, just a
/// new *destination* for its output (save the images themselves, rather
/// than re-embedding them into a rebuilt PDF).
///
/// **Format decision (JPEG only, no PNG option):** `PdfPageRenderingService`
/// always JPEG-encodes each rasterized page internally, before the temp
/// file this class reads is ever written - there is no hook in its public
/// interface to intercept pre-JPEG raw pixel data. Offering a "PNG" option
/// here would either mean widening the shared rendering interface every
/// other PDF Tool depends on (real risk to code none of this pass touches
/// otherwise), or silently re-encoding an already-JPEG-compressed image as
/// PNG (a lossy-then-lossless round trip that isn't genuinely lossless,
/// misleading to present as a real format choice) - per this pass's own
/// "do not add format options current dependencies cannot reliably
/// support" instruction, this class deliberately offers JPEG only.
///
/// **Two-DPI design (deliberately not the P0-5 "rasterize once" pattern):**
/// the page-selection grid is built once, cheaply, at `kPdfThumbnailDpi`
/// (matching every other page-picker grid in this app, Organize/Split);
/// the actual export re-rasterizes only the *selected* pages at
/// `kPdfOutputDpi`. Unlike P0-5's Page Management (where the same bytes
/// were needed for both display *and* final output, so rasterizing once
/// and holding them was strictly better), a PDF->Images grid and export
/// serve genuinely different resolutions for potentially very different
/// page subsets - rasterizing every page at full export quality just to
/// show a selection grid would waste memory/time on pages the user may
/// never actually export.
class PdfToImageOutput {
  const PdfToImageOutput({required this.pageIndex, required this.jpegBytes, required this.width, required this.height});
  final int pageIndex;
  final Uint8List jpegBytes;
  final int width;
  final int height;
}

class PdfToImagesState {
  const PdfToImagesState({
    this.source,
    this.pageThumbnails = const [],
    this.selectedPageIndices = const {},
    this.isBusy = false,
    this.error,
    this.progress,
    this.results = const [],
    this.savedOutputIndices = const {},
  });

  final PickedToolkitFile? source;
  final List<PdfPageThumbnail> pageThumbnails;
  final Set<int> selectedPageIndices;
  final bool isBusy;
  final String? error;

  /// 0.0-1.0 while an export is running, null otherwise - the export
  /// progress this pass's own "show progress for long PDFs" requirement
  /// asks for.
  final double? progress;
  final List<PdfToImageOutput> results;
  final Set<int> savedOutputIndices;

  bool get isEmpty => source == null;
  bool get hasResults => results.isNotEmpty;
  int get pageCount => pageThumbnails.length;

  PdfToImagesState copyWith({
    PickedToolkitFile? source,
    List<PdfPageThumbnail>? pageThumbnails,
    Set<int>? selectedPageIndices,
    bool? isBusy,
    String? error,
    bool clearError = false,
    double? progress,
    bool clearProgress = false,
    List<PdfToImageOutput>? results,
    Set<int>? savedOutputIndices,
  }) {
    return PdfToImagesState(
      source: source ?? this.source,
      pageThumbnails: pageThumbnails ?? this.pageThumbnails,
      selectedPageIndices: selectedPageIndices ?? this.selectedPageIndices,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      progress: clearProgress ? null : (progress ?? this.progress),
      results: results ?? this.results,
      savedOutputIndices: savedOutputIndices ?? this.savedOutputIndices,
    );
  }
}

class PdfToImagesController extends Notifier<PdfToImagesState> {
  bool _cancelRequested = false;

  @override
  PdfToImagesState build() => const PdfToImagesState();

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;
    state = PdfToImagesState(source: picked, isBusy: true);
    final tempPaths = <String>[];
    try {
      final indexed = <MapEntry<int, PdfPageThumbnail>>[];
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(picked.bytes, dpi: kPdfThumbnailDpi)) {
        tempPaths.add(page.tempFilePath);
        final bytes = await File(page.tempFilePath).readAsBytes();
        indexed.add(MapEntry(page.pageIndex, PdfPageThumbnail(pageIndex: page.pageIndex, jpegBytes: bytes)));
      }
      indexed.sort((a, b) => a.key.compareTo(b.key));
      final thumbnails = [for (final e in indexed) e.value];
      // "Export all pages" is the common case - select everything by
      // default, letting the user narrow down rather than build up.
      state = state.copyWith(pageThumbnails: thumbnails, selectedPageIndices: {for (final t in thumbnails) t.pageIndex}, isBusy: false);
    } on PdfRenderingException catch (e) {
      state = PdfToImagesState(source: picked, error: e.message);
    } catch (_) {
      state = PdfToImagesState(source: picked, error: 'Could not read this PDF\'s pages.');
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  void toggleSelect(int pageIndex) {
    final updated = {...state.selectedPageIndices};
    if (!updated.add(pageIndex)) updated.remove(pageIndex);
    state = state.copyWith(selectedPageIndices: updated);
  }

  void selectAll() => state = state.copyWith(selectedPageIndices: {for (final t in state.pageThumbnails) t.pageIndex});

  void selectNone() => state = state.copyWith(selectedPageIndices: const {});

  /// Rasterizes every currently-selected page at export quality and holds
  /// the results in memory - streamed and progress-reported one page at a
  /// time, cancellable mid-export via [cancelExport]. Cancelling stops
  /// *consuming* further pages from the stream immediately (the loop
  /// breaks on the next iteration) and cleans up every temp file already
  /// received - the one page whose native rasterization was already in
  /// flight when cancel was requested still completes in the background
  /// before that next check fires, a small, disclosed limitation of
  /// cooperating with a native platform-channel call this app doesn't
  /// control, not a fake "instant" cancel.
  Future<void> exportSelected() async {
    if (state.selectedPageIndices.isEmpty) {
      state = state.copyWith(error: 'Select at least one page to export.');
      return;
    }
    _cancelRequested = false;
    final source = state.source;
    if (source == null) return;
    final indices = state.selectedPageIndices.toList()..sort();
    state = state.copyWith(isBusy: true, clearError: true, progress: 0, results: const [], savedOutputIndices: const {});
    final tempPaths = <String>[];
    final results = <PdfToImageOutput>[];
    try {
      var done = 0;
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(
            source.bytes,
            pageIndices: indices,
            dpi: kPdfOutputDpi,
          )) {
        if (_cancelRequested) break;
        tempPaths.add(page.tempFilePath);
        final bytes = await File(page.tempFilePath).readAsBytes();
        results.add(PdfToImageOutput(pageIndex: page.pageIndex, jpegBytes: bytes, width: page.width, height: page.height));
        done++;
        state = state.copyWith(progress: done / indices.length);
      }
      results.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
      if (_cancelRequested) {
        state = state.copyWith(isBusy: false, clearProgress: true, error: 'Export cancelled.');
      } else {
        state = state.copyWith(isBusy: false, clearProgress: true, results: results);
      }
    } on PdfRenderingException catch (e) {
      state = state.copyWith(isBusy: false, clearProgress: true, error: e.message);
    } catch (_) {
      state = state.copyWith(isBusy: false, clearProgress: true, error: 'Could not export these pages. Please try again.');
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  void cancelExport() => _cancelRequested = true;

  Future<ToolkitFile?> saveOutput(int outputIndex) async {
    if (state.savedOutputIndices.contains(outputIndex)) return null;
    final output = state.results[outputIndex];
    final source = state.source!;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfToImages, 'jpg');
    await File(outputPath).writeAsBytes(output.jpegBytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.pdfToImages,
      title: '${source.fileName} - Page ${output.pageIndex + 1}',
      outputPath: outputPath,
      fileSizeBytes: output.jpegBytes.lengthInBytes,
      originalFileSizeBytes: null,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: null,
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
    for (var i = 0; i < state.results.length; i++) {
      await saveOutput(i);
    }
  }

  Future<void> shareOutput(int outputIndex) async {
    final output = state.results[outputIndex];
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(output.jpegBytes, name: 'page_${output.pageIndex + 1}.jpg', mimeType: 'image/jpeg')],
      ),
    );
  }

  void reset() => state = const PdfToImagesState();
}

final pdfToImagesControllerProvider = NotifierProvider<PdfToImagesController, PdfToImagesState>(
  PdfToImagesController.new,
);
