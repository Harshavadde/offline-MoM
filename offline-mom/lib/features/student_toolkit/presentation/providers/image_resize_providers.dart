import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../core/utils/document_title.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../services/toolkit/image_resize_service.dart';
import '../../../../services/toolkit/toolkit_image_picker_service.dart';
import 'toolkit_providers.dart';

/// Mirrors `ImageCompressUiState`'s identical shape/reasoning
/// (image_compress_providers.dart) - a separate sealed hierarchy, not a
/// shared base class, matching this codebase's own established precedent
/// of two conceptually-similar but domain-distinct state machines (e.g.
/// `MeetingStatus`/`DocumentStatus`) each getting their own type rather
/// than forcing a shared abstraction across unrelated tools.
sealed class ImageResizeUiState {
  const ImageResizeUiState();
}

class ImageResizeEmpty extends ImageResizeUiState {
  const ImageResizeEmpty();
}

class ImageResizeReady extends ImageResizeUiState {
  const ImageResizeReady(this.source);
  final PickedToolkitImage source;
}

class ImageResizeProcessing extends ImageResizeUiState {
  const ImageResizeProcessing(this.source);
  final PickedToolkitImage source;
}

class ImageResizeDone extends ImageResizeUiState {
  const ImageResizeDone(this.source, this.result, {this.savedFile});
  final PickedToolkitImage source;
  final ImageResizeResult result;
  final ToolkitFile? savedFile;
}

class ImageResizeError extends ImageResizeUiState {
  const ImageResizeError(this.source, this.message);
  final PickedToolkitImage? source;
  final String message;
}

/// Orchestrates the Resize Image tool (Student Toolkit, V2 Phase 5A) -
/// mirrors `ImageCompressController`'s shape exactly (same `compute()`
/// off-main-isolate reasoning, same UI-level-only cancellation per
/// ADR-027).
class ImageResizeController extends Notifier<ImageResizeUiState> {
  bool _abandoned = false;

  @override
  ImageResizeUiState build() => const ImageResizeEmpty();

  PickedToolkitImage? get _currentSource => switch (state) {
        ImageResizeReady(:final source) => source,
        ImageResizeProcessing(:final source) => source,
        ImageResizeDone(:final source) => source,
        ImageResizeError(:final source) => source,
        ImageResizeEmpty() => null,
      };

  Future<void> pickFromGallery() async {
    try {
      final picked = await ref.read(toolkitImagePickerServiceProvider).pickFromGallery();
      if (picked == null) return;
      state = ImageResizeReady(picked);
    } catch (e) {
      // Production Readiness audit: mirrors `ImageCompressController`'s
      // identical fix - the picker itself can throw (permission denied,
      // camera unavailable), previously unguarded here.
      state = ImageResizeError(null, friendlyErrorMessage(e));
    }
  }

  Future<void> captureFromCamera() async {
    try {
      final picked = await ref.read(toolkitImagePickerServiceProvider).captureFromCamera();
      if (picked == null) return;
      state = ImageResizeReady(picked);
    } catch (e) {
      state = ImageResizeError(null, friendlyErrorMessage(e));
    }
  }

  Future<void> resize({
    required ImageResizeMode mode,
    required ImageResizeOutputFormat outputFormat,
    double? percentage,
    int? targetWidth,
    int? targetHeight,
    bool maintainAspectRatio = true,
  }) async {
    final source = _currentSource;
    if (source == null) return;

    state = ImageResizeProcessing(source);
    _abandoned = false;
    try {
      final request = ImageResizeRequest(
        sourceBytes: source.bytes,
        mode: mode,
        outputFormat: outputFormat,
        percentage: percentage,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        maintainAspectRatio: maintainAspectRatio,
      );
      final result = await compute(resizeImage, request);
      if (_abandoned) return;
      state = ImageResizeDone(source, result);
    } on ImageCompressionException catch (e) {
      if (_abandoned) return;
      state = ImageResizeError(source, e.message);
    } catch (_) {
      if (_abandoned) return;
      state = ImageResizeError(
        source,
        'Something went wrong while resizing this image. Please try again.',
      );
    }
  }

  void cancel() {
    final current = state;
    if (current is! ImageResizeProcessing) return;
    _abandoned = true;
    state = ImageResizeReady(current.source);
  }

  Future<ToolkitFile?> save() async {
    final current = state;
    if (current is! ImageResizeDone) return null;
    if (current.savedFile != null) return current.savedFile;

    final outputPath = await newToolkitOutputPath(
      ToolkitToolType.imageResize,
      current.result.outputFormat.extension,
    );
    await File(outputPath).writeAsBytes(current.result.bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.imageResize,
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
    state = ImageResizeDone(current.source, current.result, savedFile: withId);
    return withId;
  }

  Future<void> share() async {
    final current = state;
    if (current is! ImageResizeDone) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            current.result.bytes,
            name: '${_titleFrom(current.source.fileName)}.${current.result.outputFormat.extension}',
            mimeType: switch (current.result.outputFormat) {
              ImageResizeOutputFormat.jpg => 'image/jpeg',
              ImageResizeOutputFormat.png => 'image/png',
              ImageResizeOutputFormat.webp => 'image/webp',
            },
          ),
        ],
      ),
    );
  }

  void reset() {
    _abandoned = true;
    state = const ImageResizeEmpty();
  }

  // V2.2 Production Hardening, Priority 7 - see pdf_compress_providers
  // .dart's identical fix for the full reasoning (5 files shared this
  // exact naive implementation).
  String _titleFrom(String fileName) => deriveDocumentTitle(fileName);
}

final imageResizeControllerProvider =
    NotifierProvider<ImageResizeController, ImageResizeUiState>(
  ImageResizeController.new,
);
