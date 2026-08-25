import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../core/utils/document_title.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../services/toolkit/image_compression_service.dart';
import '../../../../services/toolkit/toolkit_image_picker_service.dart';
import 'toolkit_providers.dart';

/// Mirrors `DocumentImportUiState`'s sealed-state shape
/// (lib/features/documents/presentation/providers/document_providers.dart),
/// adapted for a pick -> configure -> process -> save/share pipeline that
/// (unlike document import) lets the user re-run with different settings
/// without re-picking, so every variant beyond [ImageCompressEmpty] carries
/// the picked [source] forward.
sealed class ImageCompressUiState {
  const ImageCompressUiState();
}

class ImageCompressEmpty extends ImageCompressUiState {
  const ImageCompressEmpty();
}

class ImageCompressReady extends ImageCompressUiState {
  const ImageCompressReady(this.source);
  final PickedToolkitImage source;
}

class ImageCompressProcessing extends ImageCompressUiState {
  const ImageCompressProcessing(this.source);
  final PickedToolkitImage source;
}

class ImageCompressDone extends ImageCompressUiState {
  const ImageCompressDone(this.source, this.result, {this.savedFile});
  final PickedToolkitImage source;
  final ImageCompressionResult result;

  /// Set once [ImageCompressController.save] has actually written the file
  /// and inserted its Recent Files row - lets the screen show a "Saved" vs
  /// "Save" affordance without re-saving on every rebuild.
  final ToolkitFile? savedFile;
}

class ImageCompressError extends ImageCompressUiState {
  const ImageCompressError(this.source, this.message);

  /// Null only if picking/capturing itself failed before any source image
  /// existed to retry with.
  final PickedToolkitImage? source;
  final String message;
}

/// Orchestrates the Compress Image tool (Student Toolkit, V2 Phase 5A).
/// The actual decode/resize/encode work happens in [compressImage]
/// (services/toolkit/image_compression_service.dart), run via `compute()`
/// so a large photo's real CPU cost never blocks the UI thread - this
/// controller only owns UI state and the save/share side effects.
class ImageCompressController extends Notifier<ImageCompressUiState> {
  bool _abandoned = false;

  @override
  ImageCompressUiState build() => const ImageCompressEmpty();

  PickedToolkitImage? get _currentSource => switch (state) {
        ImageCompressReady(:final source) => source,
        ImageCompressProcessing(:final source) => source,
        ImageCompressDone(:final source) => source,
        ImageCompressError(:final source) => source,
        ImageCompressEmpty() => null,
      };

  Future<void> pickFromGallery() async {
    try {
      final picked = await ref.read(toolkitImagePickerServiceProvider).pickFromGallery();
      if (picked == null) return;
      state = ImageCompressReady(picked);
    } catch (e) {
      // Production Readiness audit: the picker itself can throw (camera/
      // gallery permission denied, or another app holding the camera) -
      // previously unguarded, so this propagated as an uncaught exception
      // instead of the friendly-error path every other pick/capture
      // failure in this app already goes through (mirrors Phase 8C's
      // identical fix for `DocumentImportController`/`ImportController`).
      // `source: null` is exactly what this state already exists for (see
      // `ImageCompressError.source`'s doc comment) - the UI's `ref.listen`
      // for this case was already wired up, just never reachable.
      state = ImageCompressError(null, friendlyErrorMessage(e));
    }
  }

  Future<void> captureFromCamera() async {
    try {
      final picked = await ref.read(toolkitImagePickerServiceProvider).captureFromCamera();
      if (picked == null) return;
      state = ImageCompressReady(picked);
    } catch (e) {
      state = ImageCompressError(null, friendlyErrorMessage(e));
    }
  }

  Future<void> compress({
    required ImageOutputFormat outputFormat,
    int? targetSizeBytes,
    int? quality,
    int? maxWidth,
    int? maxHeight,
  }) async {
    final source = _currentSource;
    if (source == null) return;

    state = ImageCompressProcessing(source);
    _abandoned = false;
    try {
      final request = ImageCompressionRequest(
        sourceBytes: source.bytes,
        outputFormat: outputFormat,
        targetSizeBytes: targetSizeBytes,
        quality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      final result = await compute(compressImage, request);
      if (_abandoned) return;
      state = ImageCompressDone(source, result);
    } on ImageCompressionException catch (e) {
      if (_abandoned) return;
      state = ImageCompressError(source, e.message);
    } catch (_) {
      if (_abandoned) return;
      state = ImageCompressError(
        source,
        'Something went wrong while compressing this image. Please try again.',
      );
    }
  }

  /// UI-level cancellation only - `compute()` has no true mid-flight
  /// cancellation API, so this mirrors `WorkspaceChatUseCase`'s abandon
  /// semantics (ADR-027, docs/v2/implementation/03-decisions.md): return to
  /// the ready state immediately, and [compress]'s `_abandoned` check
  /// discards whatever the in-flight `compute()` eventually returns rather
  /// than showing/saving it.
  void cancel() {
    final current = state;
    if (current is! ImageCompressProcessing) return;
    _abandoned = true;
    state = ImageCompressReady(current.source);
  }

  Future<ToolkitFile?> save() async {
    final current = state;
    if (current is! ImageCompressDone) return null;
    if (current.savedFile != null) return current.savedFile;

    final outputPath = await newToolkitOutputPath(
      ToolkitToolType.imageCompress,
      current.result.outputFormat.extension,
    );
    await File(outputPath).writeAsBytes(current.result.bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.imageCompress,
      title: _titleFrom(current.source.fileName),
      outputPath: outputPath,
      fileSizeBytes: current.result.resultSizeBytes,
      originalFileSizeBytes: current.result.originalSizeBytes,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
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
    );
    state = ImageCompressDone(current.source, current.result, savedFile: withId);
    return withId;
  }

  Future<void> share() async {
    final current = state;
    if (current is! ImageCompressDone) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            current.result.bytes,
            name: '${_titleFrom(current.source.fileName)}.${current.result.outputFormat.extension}',
            mimeType: current.result.outputFormat == ImageOutputFormat.png
                ? 'image/png'
                : 'image/jpeg',
          ),
        ],
      ),
    );
  }

  /// Back to empty (a fresh pick) - distinct from [cancel] (back to the
  /// still-picked, ready-to-reconfigure state).
  void reset() {
    _abandoned = true;
    state = const ImageCompressEmpty();
  }

  // V2.2 Production Hardening, Priority 7 - see pdf_compress_providers
  // .dart's identical fix for the full reasoning (5 files shared this
  // exact naive implementation).
  String _titleFrom(String fileName) => deriveDocumentTitle(fileName);
}

final imageCompressControllerProvider =
    NotifierProvider<ImageCompressController, ImageCompressUiState>(
  ImageCompressController.new,
);
