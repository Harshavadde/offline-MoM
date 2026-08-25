import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/pdf_security/pdf_permissions.dart';
import '../../../../services/pdf_security/pdf_security_service.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart';
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'toolkit_providers.dart';

/// Protect PDF (P0-8) - picks a plain PDF, rasterizes it (the same shared
/// primitive every other PDF Tool previews with) purely for an honest
/// "here's what you're about to protect" preview, then calls
/// [PdfSecurityService.protect] to produce a genuinely encrypted copy. The
/// result is never shown through `PdfPreview`/`Printing.raster()` - both
/// have no password parameter, so a real encrypted PDF simply cannot be
/// rendered that way; the "preview" step instead re-shows the same
/// already-rasterized plain pages, since a protected PDF's *visual* content
/// is by definition identical to the source.
class ProtectPdfState {
  const ProtectPdfState({
    this.source,
    this.pages = const [],
    this.password = '',
    this.confirmPassword = '',
    this.permissions = const PdfPermissions(),
    this.isBusy = false,
    this.error,
    this.resultBytes,
    this.savedFile,
  });

  final PickedToolkitFile? source;
  final List<Uint8List> pages;
  final String password;
  final String confirmPassword;
  final PdfPermissions permissions;
  final bool isBusy;
  final String? error;
  final Uint8List? resultBytes;
  final ToolkitFile? savedFile;

  bool get isEmpty => source == null;
  bool get isDone => resultBytes != null;
  bool get passwordsMatch => password == confirmPassword;
  bool get canProtect => password.isNotEmpty && passwordsMatch && !isBusy;

  ProtectPdfState copyWith({
    PickedToolkitFile? source,
    List<Uint8List>? pages,
    String? password,
    String? confirmPassword,
    PdfPermissions? permissions,
    bool? isBusy,
    String? error,
    bool clearError = false,
    Uint8List? resultBytes,
    ToolkitFile? savedFile,
  }) {
    return ProtectPdfState(
      source: source ?? this.source,
      pages: pages ?? this.pages,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      permissions: permissions ?? this.permissions,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      resultBytes: resultBytes ?? this.resultBytes,
      savedFile: savedFile ?? this.savedFile,
    );
  }
}

class ProtectPdfController extends Notifier<ProtectPdfState> {
  @override
  ProtectPdfState build() => const ProtectPdfState();

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;
    state = ProtectPdfState(source: picked, isBusy: true);
    final tempPaths = <String>[];
    try {
      final pages = <int, Uint8List>{};
      await for (final page in ref
          .read(pdfPageRenderingServiceProvider)
          .rasterizePages(picked.bytes, dpi: kPdfThumbnailDpi)) {
        tempPaths.add(page.tempFilePath);
        pages[page.pageIndex] = await File(page.tempFilePath).readAsBytes();
      }
      final ordered = pages.keys.toList()..sort();
      state = state.copyWith(pages: [for (final i in ordered) pages[i]!], isBusy: false);
    } on PdfRenderingException catch (e) {
      state = ProtectPdfState(source: picked, error: e.message);
    } catch (_) {
      state = ProtectPdfState(source: picked, error: 'Could not read this PDF\'s pages.');
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  void setPassword(String value) => state = state.copyWith(password: value, clearError: true);
  void setConfirmPassword(String value) => state = state.copyWith(confirmPassword: value, clearError: true);
  void setPermissions(PdfPermissions permissions) => state = state.copyWith(permissions: permissions);

  Future<void> protect() async {
    final source = state.source;
    if (source == null || !state.canProtect) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final bytes = await ref.read(pdfSecurityServiceProvider).protect(
            source.bytes,
            userPassword: state.password,
            permissions: state.permissions,
          );
      state = state.copyWith(isBusy: false, resultBytes: bytes);
    } on PdfSecurityException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isBusy: false, error: friendlyErrorMessage(e));
    }
  }

  Future<ToolkitFile?> save() async {
    final bytes = state.resultBytes;
    if (bytes == null) return null;
    if (state.savedFile != null) return state.savedFile;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfProtect, 'pdf');
    await File(outputPath).writeAsBytes(bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.pdfProtect,
      title: 'Protected ${state.source?.fileName ?? 'document'}',
      outputPath: outputPath,
      fileSizeBytes: bytes.length,
      originalFileSizeBytes: state.source?.bytes.lengthInBytes,
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
    state = state.copyWith(savedFile: withId);
    return withId;
  }

  void reset() => state = const ProtectPdfState();
}

final protectPdfControllerProvider = NotifierProvider<ProtectPdfController, ProtectPdfState>(
  ProtectPdfController.new,
);
