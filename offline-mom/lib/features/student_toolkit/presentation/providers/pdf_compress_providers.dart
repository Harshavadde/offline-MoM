import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/pdf_compression_service.dart';
import '../../../../core/utils/document_title.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart' show PdfRenderingException;
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'toolkit_providers.dart';

/// Mirrors `ImageCompressUiState`'s shape exactly (V2 Phase 5A) - a linear
/// pick -> configure -> compress -> result pipeline, the one PDF Tool
/// whose shape matches Image Compress rather than Scanner/Merge/Split/
/// Organize's multi-item session shape (a single source file in, a single
/// compressed file out).
sealed class PdfCompressUiState {
  const PdfCompressUiState();
}

class PdfCompressEmpty extends PdfCompressUiState {
  const PdfCompressEmpty();
}

class PdfCompressReady extends PdfCompressUiState {
  const PdfCompressReady(this.source);
  final PickedToolkitFile source;
}

class PdfCompressProcessing extends PdfCompressUiState {
  const PdfCompressProcessing(this.source);
  final PickedToolkitFile source;
}

class PdfCompressDone extends PdfCompressUiState {
  const PdfCompressDone(this.source, this.result, {this.savedFile});
  final PickedToolkitFile source;
  final PdfCompressionResult result;
  final ToolkitFile? savedFile;
}

class PdfCompressError extends PdfCompressUiState {
  const PdfCompressError(this.source, this.message);
  final PickedToolkitFile? source;
  final String message;
}

class PdfCompressController extends Notifier<PdfCompressUiState> {
  bool _abandoned = false;

  @override
  PdfCompressUiState build() => const PdfCompressEmpty();

  PickedToolkitFile? get _currentSource => switch (state) {
        PdfCompressReady(:final source) => source,
        PdfCompressProcessing(:final source) => source,
        PdfCompressDone(:final source) => source,
        PdfCompressError(:final source) => source,
        PdfCompressEmpty() => null,
      };

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;
    state = PdfCompressReady(picked);
  }

  Future<void> compress(PdfCompressionPreset preset, {double? customDpi, int? customQuality}) async {
    final source = _currentSource;
    if (source == null) return;

    state = PdfCompressProcessing(source);
    _abandoned = false;
    try {
      final spec = preset == PdfCompressionPreset.custom
          ? PdfCompressSpec(dpi: customDpi ?? 150, jpegQuality: customQuality ?? 80)
          : PdfCompressPresetSpecs.specFor(preset);
      final result = await ref.read(pdfCompressionServiceProvider).compress(
            source.bytes,
            renderingService: ref.read(pdfPageRenderingServiceProvider),
            dpi: spec.dpi,
            jpegQuality: spec.jpegQuality,
            textPreserver: ref.read(pdfSearchableTextPreserverProvider),
            overlayTextFontFallback: await loadOverlayTextFontFallback(ref),
            cropToContent: true,
          );
      if (_abandoned) return;
      state = PdfCompressDone(source, result);
    } catch (e) {
      if (_abandoned) return;
      state = PdfCompressError(
        source,
        e is PdfRenderingException
            ? e.message
            : 'Could not compress this PDF. Please try a different file.',
      );
    }
  }

  void cancel() {
    final current = state;
    if (current is! PdfCompressProcessing) return;
    _abandoned = true;
    state = PdfCompressReady(current.source);
  }

  Future<ToolkitFile?> save() async {
    final current = state;
    if (current is! PdfCompressDone) return null;
    if (current.savedFile != null) return current.savedFile;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfCompress, 'pdf');
    await File(outputPath).writeAsBytes(current.result.bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.pdfCompress,
      title: _titleFrom(current.source.fileName),
      outputPath: outputPath,
      fileSizeBytes: current.result.resultSizeBytes,
      originalFileSizeBytes: current.result.originalSizeBytes,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: current.result.pageCount,
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
    state = PdfCompressDone(current.source, current.result, savedFile: withId);
    return withId;
  }

  Future<void> share() async {
    final current = state;
    if (current is! PdfCompressDone) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            current.result.bytes,
            name: '${_titleFrom(current.source.fileName)}.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      ),
    );
  }

  void reset() {
    _abandoned = true;
    state = const PdfCompressEmpty();
  }

  // V2.2 Production Hardening, Priority 7 (real-device QA finding): was a
  // naive "strip the extension" implementation, duplicated identically
  // across 5 toolkit provider files, none of which stripped UUIDs, long
  // numeric/hex tokens, or generic download-tool prefixes the way
  // deriveDocumentTitle() (used by document import since Phase 7B)
  // already does - a file picked from a gallery/camera-roll app named
  // like `IMG_20240615_143022_a1b2c3d4.jpg` (deriveDocumentTitle's own
  // canonical example) would have shown that raw name verbatim as the
  // saved output's title. Reuses the existing, already-tested utility
  // instead of fixing 5 duplicated naive copies independently.
  String _titleFrom(String fileName) => deriveDocumentTitle(fileName);
}

final pdfCompressControllerProvider =
    NotifierProvider<PdfCompressController, PdfCompressUiState>(
  PdfCompressController.new,
);
