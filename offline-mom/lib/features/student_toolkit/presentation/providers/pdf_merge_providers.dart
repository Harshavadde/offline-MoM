import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/pdf_merge_service.dart';
import 'toolkit_providers.dart';

/// One file queued for merging - a plain wrapper adding a stable local [id]
/// (for reorder/remove-by-id, the same reasoning as `ScannedPage.id`) and
/// [isPdf] (so the controller knows whether to feed it through
/// `PdfMergeInput.pdf` or `.image` when merging).
class PdfMergeItem {
  const PdfMergeItem({
    required this.id,
    required this.fileName,
    required this.bytes,
    required this.isPdf,
  });

  final String id;
  final String fileName;
  final Uint8List bytes;
  final bool isPdf;

  int get sizeBytes => bytes.lengthInBytes;
}

/// A multi-item queue-building session (add/remove/reorder files, then
/// merge once) - the same shape reasoning as `ScannerState`, not a linear
/// pipeline like `PdfCompressUiState`.
class PdfMergeState {
  const PdfMergeState({
    this.items = const [],
    this.isBusy = false,
    this.error,
    this.mergedBytes,
    this.mergedPageCount,
    this.savedFile,
  });

  final List<PdfMergeItem> items;
  final bool isBusy;
  final String? error;
  final Uint8List? mergedBytes;
  final int? mergedPageCount;
  final ToolkitFile? savedFile;

  PdfMergeState copyWith({
    List<PdfMergeItem>? items,
    bool? isBusy,
    String? error,
    bool clearError = false,
    Uint8List? mergedBytes,
    bool clearMerged = false,
    int? mergedPageCount,
    ToolkitFile? savedFile,
  }) {
    return PdfMergeState(
      items: items ?? this.items,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      mergedBytes: clearMerged ? null : (mergedBytes ?? this.mergedBytes),
      mergedPageCount: clearMerged ? null : (mergedPageCount ?? this.mergedPageCount),
      savedFile: clearMerged ? null : (savedFile ?? this.savedFile),
    );
  }
}

class PdfMergeController extends Notifier<PdfMergeState> {
  int _idCounter = 0;

  @override
  PdfMergeState build() => const PdfMergeState();

  Future<void> addFiles() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickMultiplePdfsOrImages();
    if (picked.isEmpty) return;
    final newItems = [
      for (final file in picked)
        PdfMergeItem(
          id: 'merge_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
          fileName: file.fileName,
          bytes: file.bytes,
          isPdf: file.fileName.toLowerCase().endsWith('.pdf'),
        ),
    ];
    state = state.copyWith(items: [...state.items, ...newItems], clearMerged: true, clearError: true);
  }

  void removeItem(String id) {
    state = state.copyWith(
      items: state.items.where((i) => i.id != id).toList(),
      clearMerged: true,
    );
  }

  void reorderItem(int oldIndex, int newIndex) {
    final updated = [...state.items];
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    state = state.copyWith(items: updated, clearMerged: true);
  }

  Future<void> merge() async {
    if (state.items.length < 2) {
      state = state.copyWith(error: 'Add at least two files to merge.');
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final result = await ref.read(pdfMergeServiceProvider).merge(
            [
              for (final item in state.items)
                item.isPdf ? PdfMergeInput.pdf(item.bytes) : PdfMergeInput.image(item.bytes),
            ],
            renderingService: ref.read(pdfPageRenderingServiceProvider),
            textPreserver: ref.read(pdfSearchableTextPreserverProvider),
            overlayTextFontFallback: await loadOverlayTextFontFallback(ref),
            cropToContent: true,
          );
      state = state.copyWith(
        isBusy: false,
        mergedBytes: result.bytes,
        mergedPageCount: result.pageCount,
      );
    } on PdfMergeException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not merge these files. Please try again.');
    }
  }

  Future<ToolkitFile?> save() async {
    final bytes = state.mergedBytes;
    if (bytes == null) return null;
    if (state.savedFile != null) return state.savedFile;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfMerge, 'pdf');
    await File(outputPath).writeAsBytes(bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.pdfMerge,
      title: 'Merged ${_formatTimestamp(now)}',
      outputPath: outputPath,
      fileSizeBytes: bytes.lengthInBytes,
      originalFileSizeBytes: null,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: state.mergedPageCount,
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

  Future<void> share() async {
    final bytes = state.mergedBytes;
    if (bytes == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: 'merged.pdf', mimeType: 'application/pdf')],
      ),
    );
  }

  void reset() {
    state = const PdfMergeState();
  }

  String _formatTimestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}';
  }
}

final pdfMergeControllerProvider = NotifierProvider<PdfMergeController, PdfMergeState>(
  PdfMergeController.new,
);
