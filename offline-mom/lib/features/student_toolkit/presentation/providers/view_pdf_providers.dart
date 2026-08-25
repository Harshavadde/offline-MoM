import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ocr/searchable_pdf_builder_service.dart';
import '../../../../services/pdf_security/pdf_security_service.dart';
import '../../../../services/toolkit/pdf_page_rendering_service.dart';
import '../../../../services/toolkit/pdf_search_matcher.dart';
import '../../../../services/toolkit/pdf_text_search_service.dart';
import '../../../../services/toolkit/toolkit_file_picker_service.dart';
import 'ocr_providers.dart';
import 'toolkit_providers.dart';

/// View PDF + Search (Productivity Toolkit productization pass, P0-6) - a
/// dedicated single-page-at-a-time PDF viewer (mirroring the same
/// rasterize-and-display pattern Edit/Redact/Organize already established,
/// P0-3/P0-4/P0-5 - not wrapping `printing`'s `PdfPreview` widget, which
/// exposes no safe external "jump to page N" API and no text-search
/// capability at all) with page-indexed, fully offline search over the
/// PDF's own extractable text (`PdfTextSearchService`) - never OCR.

/// One rasterized page held for display - its own small type (not
/// `PdfEditPage`/`PdfRedactPage`/`PdfPageThumbnail`), matching every prior
/// pass's own precedent for why a 4-field value type isn't worth sharing
/// across independent features.
class ViewPdfPage {
  const ViewPdfPage({required this.pageIndex, required this.jpegBytes, required this.width, required this.height});
  final int pageIndex;
  final Uint8List jpegBytes;
  final int width;
  final int height;
}

class ViewPdfState {
  const ViewPdfState({
    this.source,
    this.pages = const [],
    this.currentPage = 0,
    this.isBusy = false,
    this.error,
    this.pagesText,
    this.isSearchBusy = false,
    this.searchQuery = '',
    this.matches = const [],
    this.currentMatchIndex = 0,
    this.needsPassword = false,
    this.passwordError,
    this.unlockedBytes,
    this.unlockedSavedFile,
  });

  final PickedToolkitFile? source;
  final List<ViewPdfPage> pages;
  final int currentPage;
  final bool isBusy;
  final String? error;

  /// True once [source] has been picked and detected as password-protected
  /// (P0-8), before a correct password has been supplied - the UI shows
  /// "This PDF is password protected" + a password field instead of
  /// attempting to rasterize bytes `Printing.raster()` has no password
  /// parameter for at all.
  final bool needsPassword;

  /// Set specifically for a wrong password attempt (distinct from [error],
  /// which covers unrelated failures) - cleared on the next attempt.
  final String? passwordError;

  /// The real, fully decrypted plain PDF bytes once the correct password
  /// has been supplied - what pages are actually rasterized from, and what
  /// [ViewPdfController.saveUnlockedCopy] writes out. Never derived from
  /// [source] again after this point; [source]'s own bytes stay untouched
  /// on disk.
  final Uint8List? unlockedBytes;
  final ToolkitFile? unlockedSavedFile;

  /// Null until text extraction has run at least once; an empty (but
  /// non-null) list of all-blank strings means extraction genuinely found
  /// no text (a scanned/image-only PDF) - the P0-6 spec's own explicit
  /// "not yet searched" vs. "searched, nothing searchable" distinction.
  final List<String>? pagesText;
  final bool isSearchBusy;
  final String searchQuery;
  final List<PdfSearchMatch> matches;
  final int currentMatchIndex;

  bool get isEmpty => source == null;
  bool get hasExtractedText => pagesText != null;
  bool get isSearchable => pagesText != null && !hasNoSearchableText(pagesText!);
  int get totalOccurrences => matches.fold(0, (sum, m) => sum + m.occurrenceCount);

  ViewPdfState copyWith({
    PickedToolkitFile? source,
    List<ViewPdfPage>? pages,
    int? currentPage,
    bool? isBusy,
    String? error,
    bool clearError = false,
    List<String>? pagesText,
    bool? isSearchBusy,
    String? searchQuery,
    List<PdfSearchMatch>? matches,
    int? currentMatchIndex,
    bool? needsPassword,
    String? passwordError,
    bool clearPasswordError = false,
    Uint8List? unlockedBytes,
    ToolkitFile? unlockedSavedFile,
  }) {
    return ViewPdfState(
      source: source ?? this.source,
      pages: pages ?? this.pages,
      currentPage: currentPage ?? this.currentPage,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      pagesText: pagesText ?? this.pagesText,
      isSearchBusy: isSearchBusy ?? this.isSearchBusy,
      searchQuery: searchQuery ?? this.searchQuery,
      matches: matches ?? this.matches,
      currentMatchIndex: currentMatchIndex ?? this.currentMatchIndex,
      needsPassword: needsPassword ?? this.needsPassword,
      passwordError: clearPasswordError ? null : (passwordError ?? this.passwordError),
      unlockedBytes: unlockedBytes ?? this.unlockedBytes,
      unlockedSavedFile: unlockedSavedFile ?? this.unlockedSavedFile,
    );
  }
}

class ViewPdfController extends Notifier<ViewPdfState> {
  @override
  ViewPdfState build() => const ViewPdfState();

  Future<void> pickPdf() async {
    final picked = await ref.read(toolkitFilePickerServiceProvider).pickPdf();
    if (picked == null) return;

    // P0-8: detect encryption *before* ever attempting rasterization -
    // Printing.raster()/read_pdf_text have no password parameter at all,
    // so feeding them an encrypted PDF directly would only ever surface a
    // confusing generic failure instead of "This PDF is password protected."
    // A merely-unreadable/corrupted (not encrypted) file is deliberately
    // *not* special-cased here - it falls through to the exact same
    // rasterization attempt and PdfRenderingException handling every other
    // unreadable PDF has always gone through, rather than a second,
    // parallel "is this corrupted" opinion that could disagree with it.
    final info = ref.read(pdfSecurityServiceProvider).inspect(picked.bytes);
    if (info.isEncrypted) {
      state = ViewPdfState(source: picked, needsPassword: true);
      return;
    }

    state = ViewPdfState(source: picked, isBusy: true);
    await _rasterize(picked.bytes);
  }

  /// Cryptographically validates [password] against the picked, still-
  /// encrypted [ViewPdfState.source] (real check against its /O and /U -
  /// see [PdfSecurityService.checkPassword]) and, if correct, produces a
  /// genuinely decrypted copy before rasterizing it for display - the
  /// original picked bytes are never themselves decrypted in place.
  Future<void> tryPassword(String password) async {
    final source = state.source;
    if (source == null || !state.needsPassword) return;
    state = state.copyWith(isBusy: true, clearPasswordError: true);
    final security = ref.read(pdfSecurityServiceProvider);
    if (!security.checkPassword(source.bytes, password)) {
      state = state.copyWith(isBusy: false, passwordError: 'Incorrect password.');
      return;
    }
    try {
      final plain = await security.removePassword(source.bytes, password);
      state = state.copyWith(needsPassword: false, unlockedBytes: plain);
      await _rasterize(plain);
    } on PdfSecurityException catch (e) {
      state = state.copyWith(isBusy: false, passwordError: e.message);
    }
  }

  Future<void> _rasterize(Uint8List bytes) async {
    final tempPaths = <String>[];
    try {
      final indexed = <MapEntry<int, ViewPdfPage>>[];
      await for (final page in ref.read(pdfPageRenderingServiceProvider).rasterizePages(
            bytes,
            dpi: kPdfOutputDpi,
            cropToContent: true,
          )) {
        tempPaths.add(page.tempFilePath);
        final pageBytes = await File(page.tempFilePath).readAsBytes();
        indexed.add(MapEntry(page.pageIndex, ViewPdfPage(pageIndex: page.pageIndex, jpegBytes: pageBytes, width: page.width, height: page.height)));
      }
      indexed.sort((a, b) => a.key.compareTo(b.key));
      state = state.copyWith(pages: [for (final e in indexed) e.value], isBusy: false);
    } on PdfRenderingException catch (e) {
      state = state.copyWith(isBusy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isBusy: false, error: 'Could not read this PDF\'s pages.');
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// Saves the decrypted [ViewPdfState.unlockedBytes] as a brand-new
  /// `ToolkitFile` (P0-8, "Unlock PDF") - the original protected file
  /// picked from the user's device is never touched or overwritten.
  Future<ToolkitFile?> saveUnlockedCopy() async {
    final bytes = state.unlockedBytes;
    final source = state.source;
    if (bytes == null || source == null) return null;
    if (state.unlockedSavedFile != null) return state.unlockedSavedFile;

    final outputPath = await newToolkitOutputPath(ToolkitToolType.pdfUnlock, 'pdf');
    await File(outputPath).writeAsBytes(bytes);

    final now = DateTime.now();
    final saved = ToolkitFile(
      id: null,
      toolType: ToolkitToolType.pdfUnlock,
      title: 'Unlocked ${source.fileName}',
      outputPath: outputPath,
      fileSizeBytes: bytes.length,
      originalFileSizeBytes: source.bytes.lengthInBytes,
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
    state = state.copyWith(unlockedSavedFile: withId);
    return withId;
  }

  void goToPage(int index) {
    if (index < 0 || index >= state.pages.length) return;
    state = state.copyWith(currentPage: index);
  }

  /// Extracts per-page text on demand (the first time the user opens
  /// search, not eagerly at pick time) - `read_pdf_text` needs a real
  /// on-disk file path, so the already-picked bytes are written to a
  /// throwaway toolkit temp file for exactly this call, then deleted -
  /// the same temp-file-then-cleanup discipline every other PDF Tool
  /// already uses, never leaving the source bytes' own path exposed.
  Future<void> ensureTextExtracted() async {
    if (state.pagesText != null || state.isSearchBusy) return;
    final source = state.source;
    if (source == null) return;
    state = state.copyWith(isSearchBusy: true, clearError: true);
    final tempPath = await newToolkitTempFilePath('pdf');
    try {
      await File(tempPath).writeAsBytes(source.bytes);
      final pagesText = await ref.read(pdfTextSearchServiceProvider).extractPagesText(tempPath);
      state = state.copyWith(isSearchBusy: false, pagesText: pagesText);
    } on PdfTextSearchException catch (e) {
      state = state.copyWith(isSearchBusy: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isSearchBusy: false, error: 'Could not search this PDF. Please try again.');
    } finally {
      final file = File(tempPath);
      if (await file.exists()) await file.delete();
    }
  }

  void setSearchQuery(String query) {
    final pagesText = state.pagesText;
    if (pagesText == null) {
      state = state.copyWith(searchQuery: query);
      return;
    }
    final matches = searchPdfPagesText(pagesText, query);
    state = state.copyWith(searchQuery: query, matches: matches, currentMatchIndex: 0);
    if (matches.isNotEmpty) {
      state = state.copyWith(currentPage: matches.first.pageIndex);
    }
  }

  void clearSearch() {
    state = state.copyWith(searchQuery: '', matches: const [], currentMatchIndex: 0);
  }

  void nextMatch() {
    if (state.matches.isEmpty) return;
    final next = (state.currentMatchIndex + 1) % state.matches.length;
    state = state.copyWith(currentMatchIndex: next, currentPage: state.matches[next].pageIndex);
  }

  void previousMatch() {
    if (state.matches.isEmpty) return;
    final prev = (state.currentMatchIndex - 1 + state.matches.length) % state.matches.length;
    state = state.copyWith(currentMatchIndex: prev, currentPage: state.matches[prev].pageIndex);
  }

  void selectMatch(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= state.matches.length) return;
    state = state.copyWith(currentMatchIndex: matchIndex, currentPage: state.matches[matchIndex].pageIndex);
  }

  /// P0-7 - primes the shared OCR session (`OcrSessionController`) with
  /// this PDF's already-rasterized pages, so Run OCR never re-rasterizes
  /// the same bytes a second time. Ensures text is extracted first so
  /// pages that already have real, extractable text (a mixed document -
  /// scenario 26) are passed through as [OcrSourcePage.existingText] and
  /// never actually sent to the OCR engine - only genuinely image-only
  /// pages are OCR'd. The caller navigates to [RoutePaths.toolkitOcr]
  /// right after this returns, matching every other controller's
  /// "prime state, then push" convention in this Toolkit.
  Future<void> runOcr() async {
    await ensureTextExtracted();
    final source = state.source;
    if (source == null) return;
    final text = state.pagesText;
    final pages = [
      for (final page in state.pages)
        OcrSourcePage(
          jpegBytes: page.jpegBytes,
          width: page.width,
          height: page.height,
          existingText: text != null && page.pageIndex < text.length ? text[page.pageIndex] : null,
        ),
    ];
    await ref.read(ocrSessionControllerProvider.notifier).start(
          pages: pages,
          documentName: source.fileName,
        );
  }

  void reset() => state = const ViewPdfState();
}

final viewPdfControllerProvider = NotifierProvider<ViewPdfController, ViewPdfState>(
  ViewPdfController.new,
);
