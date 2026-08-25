import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/image_compression_service.dart' show ImageCompressionException, decodeToolkitImageOrThrow;
import '../../../../services/toolkit/pdf_page_composer.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart' show kPdfOutputDpi;
import '../../../../services/toolkit/toolkit_file_picker_service.dart' show PickedToolkitFile;
import 'toolkit_providers.dart';

/// Images -> PDF (Productivity Toolkit productization pass, P0-6) - select
/// one or more images, reorder/rotate/remove them, then build one PDF -
/// built entirely on the shared `PdfPageComposerService` (P0-5, ADR-043),
/// zero new PDF-writing mechanism. Page sizing mirrors `ScannerPdfService`'s
/// own already-shipped, already-correct convention (`scanner_pdf_service
/// .dart`): each page's size is derived from *that image's own* pixel
/// dimensions at [_kVirtualDpi], never a fixed A4/Letter page - a portrait
/// photo produces a portrait page, a landscape photo produces a landscape
/// page, with no forced cropping or stretching to fit a page shape the
/// image was never meant for.

/// The same "virtual DPI" used to convert an image's pixel dimensions into
/// a PDF page size that Scanner already uses (`kPdfOutputDpi` = 150) - not
/// a new constant, the existing one, so a photo run through Scanner and
/// the same photo run through Images->PDF produce pages of the same
/// physical size for the same pixel dimensions.
const double _kVirtualDpi = kPdfOutputDpi;

class ImageToPdfSlot {
  const ImageToPdfSlot({
    required this.id,
    required this.jpegBytes,
    required this.width,
    required this.height,
    this.rotation = PdfPageRotation.none,
  });

  final String id;
  final Uint8List jpegBytes;
  final int width;
  final int height;
  final PdfPageRotation rotation;

  ImageToPdfSlot copyWith({PdfPageRotation? rotation}) {
    return ImageToPdfSlot(id: id, jpegBytes: jpegBytes, width: width, height: height, rotation: rotation ?? this.rotation);
  }

  PdfPageInput toPageInput() => PdfPageInput(jpegBytes: jpegBytes, width: width, height: height, rotation: rotation);
}

class ImagesToPdfState {
  const ImagesToPdfState({
    this.slots = const [],
    this.isBusy = false,
    this.error,
    this.resultBytes,
    this.savedFile,
    this.history = const [],
  });

  final List<ImageToPdfSlot> slots;
  final bool isBusy;
  final String? error;
  final Uint8List? resultBytes;
  final ToolkitFile? savedFile;

  /// Snapshots of [slots] pushed before every mutating action - mirrors
  /// `PdfOrganizeState.history`'s exact same full-list-snapshot approach.
  final List<List<ImageToPdfSlot>> history;

  bool get isEmpty => slots.isEmpty;
  bool get canUndo => history.isNotEmpty;

  ImagesToPdfState copyWith({
    List<ImageToPdfSlot>? slots,
    bool? isBusy,
    String? error,
    bool clearError = false,
    Uint8List? resultBytes,
    bool clearResult = false,
    ToolkitFile? savedFile,
    List<List<ImageToPdfSlot>>? history,
  }) {
    return ImagesToPdfState(
      slots: slots ?? this.slots,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      resultBytes: clearResult ? null : (resultBytes ?? this.resultBytes),
      savedFile: clearResult ? null : (savedFile ?? this.savedFile),
      history: history ?? this.history,
    );
  }
}

class ImagesToPdfController extends Notifier<ImagesToPdfState> {
  int _idCounter = 0;

  @override
  ImagesToPdfState build() => const ImagesToPdfState();

  String _newId() => 'img_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  /// Adds one or more picked images (from the gallery/photo picker) to the
  /// end of the working list - covers both the initial "Select Images"
  /// step and later "Add more."
  Future<void> addImages() async {
    final picked = await ref.read(toolkitImagePickerServiceProvider).pickMultipleFromGallery();
    if (picked.isEmpty) return;
    await _addImageBytes([for (final p in picked) p.bytes]);
  }

  /// Adds one or more images picked from the device's file/document picker
  /// instead of the photo gallery - same end result (new slots appended),
  /// a different source for where the bytes come from. Reuses
  /// `ToolkitFilePickerService.pickMultiplePdfsOrImages` (already jpg/jpeg/
  /// png-scoped) rather than a new picker abstraction.
  Future<void> addImagesFromFiles() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickMultiplePdfsOrImages();
    if (picked.isEmpty) return;
    await _addImageBytes([for (final PickedToolkitFile p in picked) p.bytes]);
  }

  Future<void> _addImageBytes(List<Uint8List> sources) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final newSlots = <ImageToPdfSlot>[];
      for (final bytes in sources) {
        final img.Image decoded;
        try {
          decoded = decodeToolkitImageOrThrow(bytes);
        } on ImageCompressionException catch (e) {
          state = state.copyWith(isBusy: false, error: e.message);
          return;
        }
        final jpegBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
        newSlots.add(ImageToPdfSlot(id: _newId(), jpegBytes: jpegBytes, width: decoded.width, height: decoded.height));
      }
      _pushHistory();
      state = state.copyWith(slots: [...state.slots, ...newSlots], isBusy: false, clearResult: true);
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not read one or more of those images.');
    }
  }

  void _pushHistory() {
    state = state.copyWith(history: [...state.history, List.of(state.slots)]);
  }

  void undo() {
    if (state.history.isEmpty) return;
    final previous = state.history.last;
    state = state.copyWith(slots: previous, history: state.history.sublist(0, state.history.length - 1), clearResult: true);
  }

  void reorderSlot(int oldIndex, int newIndex) {
    _pushHistory();
    final updated = [...state.slots];
    final slot = updated.removeAt(oldIndex);
    updated.insert(newIndex, slot);
    state = state.copyWith(slots: updated, clearResult: true);
  }

  static PdfPageRotation _advanceRotation(PdfPageRotation current, int quarterTurns) {
    const steps = {
      PdfPageRotation.none: 0,
      PdfPageRotation.rotate90: 1,
      PdfPageRotation.rotate180: 2,
      PdfPageRotation.rotate270: 3,
    };
    const byStep = [PdfPageRotation.none, PdfPageRotation.rotate90, PdfPageRotation.rotate180, PdfPageRotation.rotate270];
    return byStep[(steps[current]! + quarterTurns) % 4];
  }

  /// Rotates one image by [quarterTurns] clockwise 90-degree steps (1=90,
  /// 3=270), on top of whatever rotation it already has. The same real PDF
  /// `/Rotate` mechanism `PdfPageComposerService` already established
  /// (ADR-043) - zero pixel recompute.
  void rotateSlot(String id, int quarterTurns) {
    _pushHistory();
    final updated = [
      for (final s in state.slots)
        if (s.id == id) s.copyWith(rotation: _advanceRotation(s.rotation, quarterTurns)) else s,
    ];
    state = state.copyWith(slots: updated, clearResult: true);
  }

  void removeSlot(String id) {
    _pushHistory();
    state = state.copyWith(slots: state.slots.where((s) => s.id != id).toList(), clearResult: true);
  }

  Future<void> generatePdf() async {
    if (state.slots.isEmpty) {
      state = state.copyWith(error: 'Add at least one image.');
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final bytes = await ref
          .read(pdfPageComposerServiceProvider)
          .compose([for (final s in state.slots) s.toPageInput()], dpi: _kVirtualDpi);
      state = state.copyWith(isBusy: false, resultBytes: bytes);
    } on PdfPageComposerException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not build the PDF. Please try again.');
    }
  }

  Future<ToolkitFile?> save() async {
    final bytes = state.resultBytes;
    if (bytes == null) return null;
    if (state.savedFile != null) return state.savedFile;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.imagesToPdf, 'pdf');
    await File(outputPath).writeAsBytes(bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.imagesToPdf,
      title: 'Images to PDF',
      outputPath: outputPath,
      fileSizeBytes: bytes.lengthInBytes,
      originalFileSizeBytes: null,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: state.slots.length,
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

  void discardResult() => state = state.copyWith(clearResult: true);

  void reset() => state = const ImagesToPdfState();
}

final imagesToPdfControllerProvider = NotifierProvider<ImagesToPdfController, ImagesToPdfState>(
  ImagesToPdfController.new,
);
