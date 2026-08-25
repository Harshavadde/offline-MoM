import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/document_title.dart';
import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/image_compression_service.dart' show ImageCompressionException, decodeToolkitImageOrThrow;
import '../../../../services/toolkit/pdf_page_composer.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart';
import '../../../../services/toolkit/pdf_searchable_text_preservation.dart';
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'toolkit_providers.dart';

/// Page Management (Productivity Toolkit productization pass, P0-5,
/// ADR-043) - Rotate/Delete/Extract/Insert/Duplicate/Replace/Reorder, all
/// built on the shared `PdfPageComposerService` (`pdf_page_composer.dart`).
/// Supersedes the earlier V2 Phase 5B "Organize Pages" (reorder + extract
/// only) in place - same route/tool tile/`ToolkitToolType.pdfOrganize`, a
/// strict capability superset, not a parallel screen.
enum InsertPosition { beforeSelection, afterSelection, atStart, atEnd }

/// Editing at this DPI (not the old, smaller thumbnail-only DPI Organize
/// used before P0-5) - every slot holds real, final-quality rasterized
/// bytes directly, so `applyChanges()`/`extractSelected()` never need to
/// re-rasterize the source a second time the way the pre-P0-5 "thumbnail
/// grid now, `PdfOrganizeService.organize()` later" design did. A real,
/// disclosed memory tradeoff (every page held in memory at this higher
/// resolution for the session's life, not just a 72dpi thumbnail) -
/// matches the same tradeoff `pdf_edit_providers.dart`/
/// `pdf_redact_providers.dart` already accepted for the identical reason.
const double _kPdfOrganizeDpi = kPdfOutputDpi;

/// One page in a Page Management session's working list - fully
/// self-contained (rasterized bytes held directly, not a lazy reference
/// back into a source file), so every operation below (reorder/rotate/
/// delete/duplicate) is pure list/metadata manipulation with no further
/// rasterization needed until the final compose step. Deliberately its
/// own type, not `PdfEditPage`/`PdfRedactPage`/`PdfSplitProviders`'
/// `PdfPageThumbnail` - the same reasoning P0-3/P0-4 already established
/// for not sharing a struct across independent features: a 5-field value
/// type costs nothing to keep distinct.
class PdfPageSlot {
  const PdfPageSlot({
    required this.id,
    required this.jpegBytes,
    required this.width,
    required this.height,
    required this.originalPageNumber,
    this.rotation = PdfPageRotation.none,
  });

  final String id;
  final Uint8List jpegBytes;
  final int width;
  final int height;

  /// 1-based page number in whichever source this slot's bytes came from
  /// originally - null for a page inserted or replaced from a *different*
  /// source than the one the user originally picked, where "page 3 of the
  /// document you started with" no longer means anything for this slot.
  final int? originalPageNumber;
  final PdfPageRotation rotation;

  PdfPageSlot copyWith({PdfPageRotation? rotation}) {
    return PdfPageSlot(
      id: id,
      jpegBytes: jpegBytes,
      width: width,
      height: height,
      originalPageNumber: originalPageNumber,
      rotation: rotation ?? this.rotation,
    );
  }

  /// B3 (release readiness, R-49) - [existingTextByOriginalPage] is keyed
  /// 1-based, matching [originalPageNumber] (0-based `null`-for-inserted
  /// convention would collide with a genuine page 0). A slot with no
  /// [originalPageNumber] (inserted or replaced from a different source)
  /// gets no reconstructed overlay - there is no "original page" whose text
  /// could apply to genuinely new content, and fabricating one would be
  /// exactly the kind of unearned claim this codebase's no-fabrication
  /// discipline (R-35) already forbids elsewhere. A duplicated slot keeps
  /// its own [originalPageNumber] (copied from the slot it was duplicated
  /// from), so it correctly reconstructs the same text on both copies -
  /// the right outcome, not a bug: two identical pages should both remain
  /// equally searchable.
  PdfPageInput toPageInput({Map<int, String>? existingTextByOriginalPage, double dpi = kPdfOutputDpi}) {
    final text = originalPageNumber == null ? null : existingTextByOriginalPage?[originalPageNumber];
    return PdfPageInput(
      jpegBytes: jpegBytes,
      width: width,
      height: height,
      rotation: rotation,
      overlayElements: overlayForExistingText(text, width, height, dpi),
    );
  }
}

class PdfOrganizeState {
  const PdfOrganizeState({
    this.source,
    this.slots = const [],
    this.selectedIds = const {},
    this.isBusy = false,
    this.error,
    this.resultBytes,
    this.resultPageCount,
    this.savedFile,
    this.history = const [],
    this.existingTextByOriginalPage = const {},
  });

  final PickedToolkitFile? source;
  final List<PdfPageSlot> slots;
  final Set<String> selectedIds;
  final bool isBusy;
  final String? error;
  final Uint8List? resultBytes;
  final int? resultPageCount;
  final ToolkitFile? savedFile;

  /// B3 (release readiness, R-49) - extracted once in [PdfOrganizeController
  /// .pickPdf], keyed 1-based to match [PdfPageSlot.originalPageNumber].
  final Map<int, String> existingTextByOriginalPage;

  /// Snapshots of [slots] pushed before every mutating action - mirrors
  /// `PdfEditState.history`/`PdfRedactState.history`'s exact same
  /// simplest-correct full-list-snapshot approach.
  final List<List<PdfPageSlot>> history;

  bool get isEmpty => source == null;
  bool get canUndo => history.isNotEmpty;
  bool get hasSelection => selectedIds.isNotEmpty;
  int get selectionCount => selectedIds.length;

  PdfOrganizeState copyWith({
    PickedToolkitFile? source,
    List<PdfPageSlot>? slots,
    Set<String>? selectedIds,
    bool? isBusy,
    String? error,
    bool clearError = false,
    Uint8List? resultBytes,
    bool clearResult = false,
    int? resultPageCount,
    ToolkitFile? savedFile,
    List<List<PdfPageSlot>>? history,
    Map<int, String>? existingTextByOriginalPage,
  }) {
    return PdfOrganizeState(
      source: source ?? this.source,
      slots: slots ?? this.slots,
      selectedIds: selectedIds ?? this.selectedIds,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      resultBytes: clearResult ? null : (resultBytes ?? this.resultBytes),
      resultPageCount: clearResult ? null : (resultPageCount ?? this.resultPageCount),
      savedFile: clearResult ? null : (savedFile ?? this.savedFile),
      history: history ?? this.history,
      existingTextByOriginalPage: existingTextByOriginalPage ?? this.existingTextByOriginalPage,
    );
  }
}

class PdfOrganizeController extends Notifier<PdfOrganizeState> {
  int _idCounter = 0;

  @override
  PdfOrganizeState build() => const PdfOrganizeState();

  String _newId() => 'slot_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;
    state = PdfOrganizeState(source: picked, isBusy: true);
    final tempPaths = <String>[];
    try {
      final indexed = <MapEntry<int, PdfPageSlot>>[];
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(
            picked.bytes,
            dpi: _kPdfOrganizeDpi,
          )) {
        tempPaths.add(page.tempFilePath);
        final bytes = await File(page.tempFilePath).readAsBytes();
        indexed.add(MapEntry(
          page.pageIndex,
          PdfPageSlot(id: _newId(), jpegBytes: bytes, width: page.width, height: page.height, originalPageNumber: page.pageIndex + 1),
        ));
      }
      indexed.sort((a, b) => a.key.compareTo(b.key));
      final existingText0Based = await ref.read(pdfSearchableTextPreserverProvider).extractExistingText(picked.bytes);
      state = state.copyWith(
        slots: [for (final e in indexed) e.value],
        isBusy: false,
        existingTextByOriginalPage: {for (final entry in existingText0Based.entries) entry.key + 1: entry.value},
      );
    } on PdfRenderingException catch (e) {
      state = PdfOrganizeState(source: picked, error: e.message);
    } catch (_) {
      state = PdfOrganizeState(source: picked, error: 'Could not read this PDF\'s pages.');
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  void _pushHistory() {
    state = state.copyWith(history: [...state.history, List.of(state.slots)]);
  }

  void undo() {
    if (state.history.isEmpty) return;
    final previous = state.history.last;
    state = state.copyWith(
      slots: previous,
      history: state.history.sublist(0, state.history.length - 1),
      clearResult: true,
    );
  }

  void toggleSelect(String id) {
    final updated = {...state.selectedIds};
    if (!updated.add(id)) updated.remove(id);
    state = state.copyWith(selectedIds: updated);
  }

  void selectAll() => state = state.copyWith(selectedIds: {for (final s in state.slots) s.id});

  void clearSelection() => state = state.copyWith(selectedIds: const {});

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
    const byStep = [
      PdfPageRotation.none,
      PdfPageRotation.rotate90,
      PdfPageRotation.rotate180,
      PdfPageRotation.rotate270,
    ];
    return byStep[(steps[current]! + quarterTurns) % 4];
  }

  /// Rotates [ids] (or the current selection, if omitted) by [quarterTurns]
  /// clockwise 90-degree steps (1=90°, 2=180°, 3=270°), on top of whatever
  /// rotation each page already has - a second 90° rotation on an
  /// already-90°-rotated page correctly becomes 180°, not a reset.
  void rotateSelected(int quarterTurns, {Iterable<String>? ids}) {
    final targets = (ids ?? state.selectedIds).toSet();
    if (targets.isEmpty) return;
    _pushHistory();
    final updated = [
      for (final s in state.slots)
        if (targets.contains(s.id)) s.copyWith(rotation: _advanceRotation(s.rotation, quarterTurns)) else s,
    ];
    state = state.copyWith(slots: updated, clearResult: true);
  }

  void rotateAll(int quarterTurns) => rotateSelected(quarterTurns, ids: [for (final s in state.slots) s.id]);

  /// Deletes [ids] (or the current selection, if omitted). Refuses (sets a
  /// friendly error, does not mutate) if doing so would leave zero pages -
  /// this app never produces an invalid empty PDF.
  void deleteSelected({Iterable<String>? ids}) {
    final targets = (ids ?? state.selectedIds).toSet();
    if (targets.isEmpty) return;
    final remaining = state.slots.where((s) => !targets.contains(s.id)).toList();
    if (remaining.isEmpty) {
      state = state.copyWith(error: 'Keep at least one page - a PDF can\'t be empty.');
      return;
    }
    _pushHistory();
    state = state.copyWith(
      slots: remaining,
      selectedIds: state.selectedIds.difference(targets),
      clearResult: true,
      clearError: true,
    );
  }

  /// Duplicates [ids] (or the current selection, if omitted) - each
  /// duplicate is inserted immediately after its own source page, per the
  /// P0-5 spec's own stated default behavior.
  void duplicateSelected({Iterable<String>? ids}) {
    final targets = (ids ?? state.selectedIds).toSet();
    if (targets.isEmpty) return;
    _pushHistory();
    final updated = <PdfPageSlot>[];
    final newIds = <String>{};
    for (final s in state.slots) {
      updated.add(s);
      if (targets.contains(s.id)) {
        final dup = PdfPageSlot(
          id: _newId(),
          jpegBytes: s.jpegBytes,
          width: s.width,
          height: s.height,
          originalPageNumber: s.originalPageNumber,
          rotation: s.rotation,
        );
        updated.add(dup);
        newIds.add(dup.id);
      }
    }
    state = state.copyWith(slots: updated, selectedIds: newIds, clearResult: true);
  }

  Future<bool> insertPdf({required InsertPosition position}) async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return false;
    return _insertRasterizedSource(picked.bytes, isPdf: true, position: position);
  }

  Future<bool> insertImage({required InsertPosition position}) async {
    final picked = await ref.read(toolkitImagePickerServiceProvider).pickFromGallery();
    if (picked == null) return false;
    return _insertRasterizedSource(picked.bytes, isPdf: false, position: position);
  }

  Future<bool> replaceSelectedWithPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return false;
    return _replaceSelected(picked.bytes, isPdf: true);
  }

  Future<bool> replaceSelectedWithImage() async {
    final picked = await ref.read(toolkitImagePickerServiceProvider).pickFromGallery();
    if (picked == null) return false;
    return _replaceSelected(picked.bytes, isPdf: false);
  }

  Future<List<PdfPageSlot>?> _rasterizeInsertable(Uint8List bytes, {required bool isPdf, required List<String> tempPaths}) async {
    if (isPdf) {
      final indexed = <MapEntry<int, PdfPageSlot>>[];
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(bytes, dpi: _kPdfOrganizeDpi)) {
        tempPaths.add(page.tempFilePath);
        final jpeg = await File(page.tempFilePath).readAsBytes();
        indexed.add(MapEntry(
          page.pageIndex,
          PdfPageSlot(id: _newId(), jpegBytes: jpeg, width: page.width, height: page.height, originalPageNumber: null),
        ));
      }
      indexed.sort((a, b) => a.key.compareTo(b.key));
      return [for (final e in indexed) e.value];
    }
    final decoded = decodeToolkitImageOrThrow(bytes);
    final jpeg = img.encodeJpg(decoded, quality: 90);
    return [PdfPageSlot(id: _newId(), jpegBytes: jpeg, width: decoded.width, height: decoded.height, originalPageNumber: null)];
  }

  int _resolveInsertIndex(InsertPosition position) {
    switch (position) {
      case InsertPosition.atStart:
        return 0;
      case InsertPosition.atEnd:
        return state.slots.length;
      case InsertPosition.beforeSelection:
      case InsertPosition.afterSelection:
        if (state.selectedIds.isEmpty) return state.slots.length;
        final selectedPositions = [
          for (var i = 0; i < state.slots.length; i++)
            if (state.selectedIds.contains(state.slots[i].id)) i,
        ];
        return position == InsertPosition.beforeSelection ? selectedPositions.first : selectedPositions.last + 1;
    }
  }

  Future<bool> _insertRasterizedSource(Uint8List bytes, {required bool isPdf, required InsertPosition position}) async {
    state = state.copyWith(isBusy: true, clearError: true);
    final tempPaths = <String>[];
    try {
      final newSlots = await _rasterizeInsertable(bytes, isPdf: isPdf, tempPaths: tempPaths);
      if (newSlots == null || newSlots.isEmpty) {
        state = state.copyWith(isBusy: false, error: 'Could not read that file\'s pages.');
        return false;
      }
      _pushHistory();
      final atIndex = _resolveInsertIndex(position);
      final updated = [...state.slots]..insertAll(atIndex, newSlots);
      state = state.copyWith(
        slots: updated,
        selectedIds: {for (final s in newSlots) s.id},
        isBusy: false,
        clearResult: true,
      );
      return true;
    } on PdfRenderingException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    } on ImageCompressionException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not insert this file.');
      return false;
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// Replaces every currently-selected page's *content* with pages from
  /// [bytes] - 1-to-1 if the replacement has exactly as many pages as the
  /// selection, or the same single replacement page applied to every
  /// selected page if the replacement is exactly one page/image. Every
  /// other, unselected page is left completely untouched, in place.
  Future<bool> _replaceSelected(Uint8List bytes, {required bool isPdf}) async {
    final targetIds = state.selectedIds;
    if (targetIds.isEmpty) {
      state = state.copyWith(error: 'Select at least one page to replace.');
      return false;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    final tempPaths = <String>[];
    try {
      final replacementSlots = await _rasterizeInsertable(bytes, isPdf: isPdf, tempPaths: tempPaths);
      if (replacementSlots == null || replacementSlots.isEmpty) {
        state = state.copyWith(isBusy: false, error: 'Could not read that file\'s pages.');
        return false;
      }
      final targetIndices = [
        for (var i = 0; i < state.slots.length; i++)
          if (targetIds.contains(state.slots[i].id)) i,
      ];
      if (replacementSlots.length != 1 && replacementSlots.length != targetIndices.length) {
        state = state.copyWith(
          isBusy: false,
          error: 'Pick a replacement with 1 page, or exactly ${targetIndices.length} pages.',
        );
        return false;
      }
      _pushHistory();
      final updated = [...state.slots];
      final newSelection = <String>{};
      for (var i = 0; i < targetIndices.length; i++) {
        final replacement = replacementSlots.length == 1 ? replacementSlots.first : replacementSlots[i];
        final placed = PdfPageSlot(
          id: _newId(),
          jpegBytes: replacement.jpegBytes,
          width: replacement.width,
          height: replacement.height,
          originalPageNumber: null,
        );
        updated[targetIndices[i]] = placed;
        newSelection.add(placed.id);
      }
      state = state.copyWith(slots: updated, selectedIds: newSelection, isBusy: false, clearResult: true);
      return true;
    } on PdfRenderingException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    } on ImageCompressionException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not replace this page. Please try again.');
      return false;
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// Composes the full working page list into the result PDF - the
  /// "Apply Changes" action covering Rotate/Delete/Duplicate/Insert/
  /// Replace/Reorder all at once (each already applied to [state.slots]
  /// as it happened).
  Future<void> applyChanges() async {
    if (state.slots.isEmpty) {
      state = state.copyWith(error: 'Keep at least one page.');
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final bytes = await ref.read(pdfPageComposerServiceProvider).compose(
            [
              for (final s in state.slots)
                s.toPageInput(existingTextByOriginalPage: state.existingTextByOriginalPage, dpi: _kPdfOrganizeDpi),
            ],
            dpi: _kPdfOrganizeDpi,
            overlayTextFontFallback: await loadOverlayTextFontFallback(ref),
          );
      state = state.copyWith(isBusy: false, resultBytes: bytes, resultPageCount: state.slots.length);
    } on PdfPageComposerException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not save these page changes. Please try again.');
    }
  }

  /// Composes *only* the current selection, in their current working
  /// order, into a new, separate result PDF - "Extract Selected." Does not
  /// remove the selected pages from the working session (non-destructive
  /// to the in-progress edit; the user can keep working after extracting).
  Future<void> extractSelected() async {
    if (state.selectedIds.isEmpty) {
      state = state.copyWith(error: 'Select at least one page to extract.');
      return;
    }
    final selected = state.slots.where((s) => state.selectedIds.contains(s.id)).toList();
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final bytes = await ref.read(pdfPageComposerServiceProvider).compose(
            [
              for (final s in selected)
                s.toPageInput(existingTextByOriginalPage: state.existingTextByOriginalPage, dpi: _kPdfOrganizeDpi),
            ],
            dpi: _kPdfOrganizeDpi,
            overlayTextFontFallback: await loadOverlayTextFontFallback(ref),
          );
      state = state.copyWith(isBusy: false, resultBytes: bytes, resultPageCount: selected.length);
    } on PdfPageComposerException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not extract these pages. Please try again.');
    }
  }

  Future<ToolkitFile?> save() async {
    final bytes = state.resultBytes;
    final source = state.source;
    if (bytes == null || source == null) return null;
    if (state.savedFile != null) return state.savedFile;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfOrganize, 'pdf');
    await File(outputPath).writeAsBytes(bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.pdfOrganize,
      title: '${_titleFrom(source.fileName)} (organized)',
      outputPath: outputPath,
      fileSizeBytes: bytes.lengthInBytes,
      originalFileSizeBytes: null,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: state.resultPageCount,
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
    final bytes = state.resultBytes;
    if (bytes == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: 'organized.pdf', mimeType: 'application/pdf')],
      ),
    );
  }

  /// Discards the working result preview (e.g. "Keep Editing" from the
  /// preview dialog) without discarding the session's slots - distinct
  /// from [reset], which discards everything.
  void discardResult() => state = state.copyWith(clearResult: true);

  void reset() {
    state = const PdfOrganizeState();
  }

  // V2.2 Production Hardening, Priority 7 - see pdf_compress_providers
  // .dart's identical fix for the full reasoning (5 files shared this
  // exact naive implementation).
  String _titleFrom(String fileName) => deriveDocumentTitle(fileName);
}

final pdfOrganizeControllerProvider = NotifierProvider<PdfOrganizeController, PdfOrganizeState>(
  PdfOrganizeController.new,
);
