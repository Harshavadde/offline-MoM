import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/logging/app_logger.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/resume/resume_template_renderer.dart';
import '../../../../../services/resume/template/resume_template_catalog.dart';
import '../../../../../services/resume/template/resume_template_spec.dart';
import '../../../../../services/toolkit/pdf_page_rendering_service.dart';
import 'resume_editor_providers.dart';
import 'resume_providers.dart';

/// The beta-scope template catalog (docs/v3/01-prd.md §8) - a plain
/// [Provider] over [ResumeTemplateCatalog.enabled] (5 of the 10 archetypes;
/// see that getter's own doc comment), which is itself already a static,
/// hand-authored list with no I/O of any kind, mirroring `modelCatalogProvider`'s
/// own "wrap a static catalog in a provider so screens `ref.watch` it the
/// same way they would anything else" convention. Intentionally not
/// [ResumeTemplateCatalog.all] - the gallery must only ever offer the 5
/// curated beta templates, though a resume already using one of the other
/// 5 still renders correctly (`specById`/`all` stay unfiltered).
final resumeTemplateCatalogProvider = Provider<List<ResumeTemplateSpec>>((ref) {
  return ResumeTemplateCatalog.enabled;
});

const _thumbnailLog = AppLogger('TemplateThumbnail');

/// State for [ResumeTemplateSelectionController] - a thin busy/error
/// wrapper, mirroring [ResumeVersionControllerState]'s exact shape
/// (`resume_version_providers.dart`): the gallery's actual template list
/// always comes from [resumeTemplateCatalogProvider], never from here.
class ResumeTemplateSelectionState {
  const ResumeTemplateSelectionState({this.isBusy = false, this.error});

  final bool isBusy;
  final String? error;

  ResumeTemplateSelectionState copyWith({bool? isBusy, String? error, bool clearError = false}) {
    return ResumeTemplateSelectionState(
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Persists which template one Resume uses - a single-repository update
/// (`Resume.templateId`, migration v17) needing no use-case orchestration,
/// the same reasoning [ResumeVersionController.rename] already applies to
/// a comparable single-field metadata change. `family` scoped by
/// `resumeId`, `autoDispose` so a second Gallery session (a different
/// resume, or this one reopened later) never reads stale busy/error state
/// left behind by a prior one.
class ResumeTemplateSelectionController
    extends AutoDisposeFamilyNotifier<ResumeTemplateSelectionState, int> {
  @override
  ResumeTemplateSelectionState build(int resumeId) {
    return const ResumeTemplateSelectionState();
  }

  Future<void> select(ResumeTemplateSpec spec) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final resumeRepository = ref.read(resumeRepositoryProvider);
      final resume = await resumeRepository.getById(arg);
      if (resume == null) {
        state = state.copyWith(
          isBusy: false,
          error: 'This resume could not be found. It may have been deleted.',
        );
        return;
      }
      await resumeRepository.update(
        resume.copyWith(templateId: spec.id, updatedAt: DateTime.now()),
      );
      state = state.copyWith(isBusy: false);
      ref.invalidate(resumeByIdProvider(arg));
    } catch (e) {
      state = state.copyWith(isBusy: false, error: friendlyErrorMessage(e));
    }
  }
}

final resumeTemplateSelectionControllerProvider = NotifierProvider.autoDispose
    .family<ResumeTemplateSelectionController, ResumeTemplateSelectionState, int>(
  ResumeTemplateSelectionController.new,
);

/// Serializes calls to `Printing.raster` (via `rasterizePages`) so the
/// Template Gallery's multiple simultaneous `_TemplateThumbnail` widgets
/// never fire it concurrently - R-6, see [templateResumeThumbnailProvider]'s
/// own doc comment for the freeze this fixes. A minimal, dependency-free
/// async queue (chain every new task onto the previous one's completion) -
/// this app's own `LlmRequestQueue` solves the analogous "one exclusive
/// native resource, many callers" problem for the LLM engine, but is
/// itself LLM-specific (priority/foreground handling this doesn't need);
/// this is the same underlying pattern, sized to what's actually needed
/// here.
class _SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  /// Chains [task] onto whatever's already queued, so at most one task
  /// actually runs at a time - [task]'s own success/failure is what [run]
  /// itself returns; the queue's internal chain only ever needs to know
  /// "the previous task is done, run the next one," never *how* it ended,
  /// so a failed task can't jam the queue for everything queued after it.
  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

final _thumbnailQueue = _SerialTaskQueue();

/// Compound key for [templateResumePdfBytesProvider]/[templateResumeThumbnailProvider] -
/// a template preview depends on *which resume* as well as *which
/// template*.
typedef TemplatePreviewKey = ({int resumeId, String templateId});

/// Real PDF bytes for one template's preview, rendered from **the actual
/// resume currently being edited** - real-device beta fix (Phase 7): this
/// previously always rendered [buildSampleResumeSnapshot] (a fixed, fake
/// resume), so the gallery could never show the user what *their own*
/// resume would actually look like in a given template, defeating the
/// entire point of a "compare templates before choosing" gallery. Reuses
/// [ResumeEditorController.compileSnapshot] - the exact same live-draft
/// compile the Editor's own "Preview"/"Export PDF" actions already use -
/// rather than a second, parallel compile path, so this can never drift
/// from what the final export actually produces. If the Editor state
/// isn't loaded yet (a direct deep-link before the Editor has finished
/// loading, not a normal flow), `compileSnapshot()` throws and this
/// provider surfaces that as its own error state - the UI already
/// degrades gracefully on any error (see [templateResumeThumbnailProvider]'s
/// own doc comment), so no separate fallback path is needed.
///
/// [buildSampleResumeSnapshot] is no longer used by any screen but is
/// kept for [ResumeTemplateRenderer] test fixtures/manual verification
/// scripts that still want a realistic, non-empty snapshot without a real
/// database.
final templateResumePdfBytesProvider = FutureProvider.family<Uint8List, TemplatePreviewKey>((ref, key) async {
  final spec = ResumeTemplateCatalog.specById(key.templateId);
  // `compileSnapshot()` throws unless the Editor has already finished
  // loading (`ResumeEditorReady`) - real bug this fixed: this provider's
  // first build can genuinely run before that (the gallery is reachable
  // as soon as its own screen mounts, which races the Editor's async
  // `_load()`), and a plain one-shot `ref.read(...).compileSnapshot()`
  // call never retries once it fails, permanently stranding the preview
  // in an error state even after the Editor becomes ready moments later -
  // confirmed by a real widget-test failure ("grid card renders the real
  // thumbnail image" timing out). Polling on the *state* (not the
  // notifier) briefly is the simple, correct fix - the resume/blockRefs
  // load is already fast (a handful of local Sqflite reads), so this
  // loop resolves within one or two iterations in practice.
  // Wrapped in a function (rather than a direct `while (editorState is
  // ResumeEditorLoading)`) so Dart's type-promotion doesn't narrow
  // `editorState`'s static type to `ResumeEditorLoading` inside the loop
  // body, which would then reject reassigning it back to the wider
  // `ResumeEditorUiState` the provider actually returns.
  bool stillLoading(ResumeEditorUiState s) => s is ResumeEditorLoading;
  ResumeEditorUiState editorState = ref.read(resumeEditorControllerProvider(key.resumeId));
  while (stillLoading(editorState)) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    editorState = ref.read(resumeEditorControllerProvider(key.resumeId));
  }
  final snapshot =
      await ref.read(resumeEditorControllerProvider(key.resumeId).notifier).compileSnapshot();
  const renderer = ResumeTemplateRenderer();
  return renderer.render(snapshot, spec);
});

/// The real preview PDF's first page, rasterized to a thumbnail image for
/// the Template Gallery's grid cards - built from
/// [templateResumePdfBytesProvider]'s real PDF bytes (the *actual* current
/// resume, not a sample) via the app's own existing
/// [PdfPageRenderingService] (the shared `Printing.raster` wrapper every
/// PDF Tool - Compress/Merge/Split/Organize - already reads pages
/// through, see that service's own doc comment), never a hand-drawn mock
/// and never a second rasterization implementation. `Printing.raster` has
/// no implementation under `flutter test` (a platform channel, real
/// device/emulator only) - a failure here degrades to `null`, which the
/// gallery card shows as a neutral placeholder rather than crashing the
/// screen; this only affects the *grid thumbnail*, never template
/// selection itself or the larger real preview the confirm screen shows
/// via `PdfPreview` directly. Tests override [pdfPageRenderingServiceProvider]
/// with `FakePdfPageRenderingService`, the same fake every PDF Tool test
/// already uses.
final templateResumeThumbnailProvider = FutureProvider.family<Uint8List?, TemplatePreviewKey>((ref, key) async {
  final pdfBytes = await ref.watch(templateResumePdfBytesProvider(key).future);
  try {
    // R-6 fix: the gallery grid mounts one of these providers per visible
    // template card (5+ at once, more once scrolled) - `Printing.raster`
    // (inside `rasterizePages`) is a platform-channel call that only runs
    // on the root isolate (see `PdfPageRenderingService`'s own doc
    // comment), so with no serialization here, every card's rasterization
    // fired concurrently, piling up root-isolate/native-channel work all
    // at once and freezing the whole screen (screenshot evidence: stuck
    // spinners on every card, screen unresponsive). `rasterizePages`
    // itself is otherwise correct and shared with every PDF Tool
    // (Compress/Merge/Split/Organize), which never call it concurrently
    // for multiple documents at once - the bug is specific to this
    // screen's own "many cards, one shared root-isolate resource" shape,
    // so the fix is scoped here rather than inside the shared service.
    final page = await _thumbnailQueue.run(
      () => ref
          .read(pdfPageRenderingServiceProvider)
          .rasterizePages(pdfBytes, pageIndices: const [0], dpi: kPdfThumbnailDpi)
          .first,
    );
    final file = File(page.tempFilePath);
    final bytes = await file.readAsBytes();
    if (await file.exists()) await file.delete();
    return bytes;
  } catch (e, stackTrace) {
    // Part J (template gallery/preview - "shows blank when preview" fix):
    // this degradation to `null` (a neutral placeholder icon, never a
    // crash) is intentional and stays - `Printing.raster` genuinely isn't
    // guaranteed on every platform. What was missing is any trace of
    // *why* - a prior investigation pass explicitly disclosed this catch
    // swallowed every failure with zero diagnostics, making a real-device
    // report impossible to root-cause after the fact. `AppLogger.warning`
    // is a caught-and-handled failure, not a crash - logged via
    // `dart:developer` only, never transmitted anywhere.
    _thumbnailLog.warning(
      'Template thumbnail rasterization failed for ${key.templateId} (resume ${key.resumeId})',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
});
