import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart' show WhisperModel;

import '../../../../models/installed_model.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/model_catalog.dart';
import '../../../../services/ai/model_lifecycle_manager.dart';
import 'model_download_providers.dart';

/// Lists/activates/deletes installed models - the "Installed Models" and
/// "Change Active Model" side of the AI Model Manager (Phase 6A, ADR-036),
/// separate from [ModelDownloadController] (which owns the download side).
/// `AsyncNotifier` (not a plain `FutureProvider`) since it needs an
/// explicit, callable [refresh] after every insert/activate/delete rather
/// than relying on provider invalidation alone - the same reasoning
/// `ToolkitFileActions` already applies to `ToolkitFile` rows.
class InstalledModelsController extends AsyncNotifier<List<InstalledModel>> {
  @override
  Future<List<InstalledModel>> build() {
    return ref.watch(installedModelRepositoryProvider).getAll();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await ref.read(installedModelRepositoryProvider).getAll());
  }

  /// Makes [modelId] (already installed, of [kind]) the active model for
  /// that kind - deactivating whatever was active before it
  /// (`InstalledModelRepository.setActive`'s own single-transaction
  /// guarantee), then persisting the choice into
  /// `AppSettings.activeLlmModelId`/`.activeEmbeddingModelId`/
  /// `.whisperModelName` so [llmEngineProvider]/[embeddingEngineProvider]/
  /// [speechToTextEngineProvider] rebuild against it on their next read -
  /// Change Active Model (Phase 6A objective 15).
  ///
  /// Reliability-overhaul pass (Phase 14/17): previously switched the
  /// active model on nothing but its `InstalledModel` row existing - a
  /// row whose file had since been deleted or corrupted outside the app
  /// (or whose install never finished cleanly) could become "active"
  /// with nothing ever having confirmed it actually still loads. For
  /// speech-to-text models, now verifies first via the exact same fast,
  /// local, network-free integrity check the manual "Verify" button
  /// already runs (file exists, size matches, hash matches -
  /// [ModelDownloadController.verify]) - "prepare the new model, verify
  /// it, only then switch." Returns `false` (never throws) if
  /// verification fails, so a genuinely unusable install can never
  /// quietly become active; the caller is expected to surface that
  /// visibly rather than swallow it.
  ///
  /// Deliberately **not** extended to LLM/embedding models:
  /// [ModelDownloadController.verify] for those two kinds re-triggers
  /// `llamadart`'s own cache validation via a real `ensureModelReady()`
  /// call, which can mean genuine network I/O and a multi-second (or, on
  /// a cold cache, multi-minute) wait - unconditionally running that on
  /// every switch would make "switching models" silently turn into "wait
  /// for a network round-trip", directly contradicting this app's own
  /// documented "switching is instant, not a fresh download" promise
  /// (`model_setup_screen.dart`). A disclosed scope limitation, not an
  /// oversight - see docs/v3/implementation/04-risk-register.md.
  Future<bool> activate(ModelKind kind, String modelId) async {
    if (kind == ModelKind.speechToText || kind == ModelKind.ocr) {
      final installed = await ref.read(installedModelRepositoryProvider).getByModelId(modelId);
      final spec = ModelCatalog.byId(modelId);
      if (installed == null || spec == null) return false;
      final verified = await ref.read(modelDownloadControllerProvider.notifier).verify(spec, installed);
      if (!verified) return false;
    }

    await ref.read(installedModelRepositoryProvider).setActive(kind, modelId);
    final settingsController = ref.read(settingsControllerProvider.notifier);
    switch (kind) {
      case ModelKind.llm:
        await settingsController.setActiveLlmModelId(modelId);
      case ModelKind.embedding:
        await settingsController.setActiveEmbeddingModelId(modelId);
      case ModelKind.speechToText:
        // `whisperModelName` stores `WhisperModel.name` (the Dart enum
        // identifier, e.g. `'largeV1'`), which is *not* always the same
        // string as the catalog id's suffix (`AiModelSpec.version` is
        // `WhisperModel.modelName`, e.g. `'large-v1'`, the published file/
        // URL identifier) - resolved through the real enum rather than
        // hand-mapping between the two spellings, so this can never drift.
        final versionSuffix = modelId.replaceFirst('whisper-', '');
        final whisperModel =
            WhisperModel.values.firstWhere((m) => m.modelName == versionSuffix);
        await settingsController.setWhisperModelName(whisperModel.name);
      case ModelKind.ocr:
        await settingsController.setActiveOcrModelId(modelId);
      case ModelKind.vision:
      case ModelKind.translation:
        break;
    }
    await refresh();
    return true;
  }

  /// Deletes an installed model - see [InstalledModelRepository]/
  /// `ModelDownloadController`'s doc comments for the honest, per-kind
  /// disclosure of what "delete" can and can't guarantee on disk
  /// (precise for Whisper; tracking-only, not cache-guaranteed, for
  /// LLM/embedding - ADR-036).
  Future<void> delete(InstalledModel model) async {
    if (model.kind == ModelKind.speechToText || model.kind == ModelKind.ocr) {
      final file = File(model.localPath);
      if (await file.exists()) await file.delete();
    }
    await ref.read(modelLifecycleManagerProvider).unmanagedUnload(model.kind);
    if (model.id != null) {
      await ref.read(installedModelRepositoryProvider).delete(model.id!);
    }
    await refresh();
  }
}

final installedModelsControllerProvider =
    AsyncNotifierProvider<InstalledModelsController, List<InstalledModel>>(
  InstalledModelsController.new,
);
