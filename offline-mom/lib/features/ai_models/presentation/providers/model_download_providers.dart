import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:whisper_flutter_new/whisper_flutter_new.dart' show WhisperModel;

import '../../../../core/utils/ai_model_paths.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../models/ai_model_spec.dart';
import '../../../../models/installed_model.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/llamadart_embedding_engine.dart';
import '../../../../services/ai/llamadart_llm_engine.dart';
import '../../../../services/ai/model_download_service.dart';
import '../../../../services/ai/model_lifecycle_manager.dart' show ModelKind;
import '../../../../services/background/background_download_service.dart';

/// One model's current download/install lifecycle state - keyed by
/// [AiModelSpec.id] in [ModelDownloadController]'s state map. Sealed (not
/// a flat mutable class) since these states are genuinely mutually
/// exclusive and each carries different data, mirroring
/// `PdfCompressUiState`'s exact convention (Phase 5B).
sealed class ModelDownloadState {
  const ModelDownloadState();
}

class ModelDownloadIdle extends ModelDownloadState {
  const ModelDownloadIdle();
}

class ModelDownloadInProgress extends ModelDownloadState {
  const ModelDownloadInProgress({required this.fraction, this.receivedBytes, this.totalBytes});
  final double? fraction;
  final int? receivedBytes;
  final int? totalBytes;
}

/// Reachable only for [ModelKind.speechToText] today - see
/// [ModelDownloadController.pause]'s doc comment for why LLM/embedding
/// pauses surface as [ModelDownloadFailed] with [ModelDownloadException
/// .wasCancelled] instead of this state.
class ModelDownloadPaused extends ModelDownloadState {
  const ModelDownloadPaused({this.receivedBytes, this.totalBytes});
  final int? receivedBytes;
  final int? totalBytes;
}

class ModelDownloadVerifying extends ModelDownloadState {
  const ModelDownloadVerifying();
}

class ModelDownloadFailed extends ModelDownloadState {
  const ModelDownloadFailed(this.message, {this.wasPaused = false});
  final String message;
  final bool wasPaused;
}

class ModelDownloadDone extends ModelDownloadState {
  const ModelDownloadDone();
}

/// Orchestrates downloading/pausing/verifying every [AiModelSpec] across
/// every [ModelKind] - the AI Model Manager's Model Download Center
/// (Phase 6A, ADR-036). One [Notifier] instance for the whole app (not
/// `.autoDispose`), so a download started from one screen keeps running
/// (and its progress stays visible) if the user navigates away and back -
/// the same "app-wide singleton controller" reasoning already applied to
/// `OnboardingSetupController`/`ScannerController`.
///
/// **Kind-specific download strategy, stated once here:** [ModelKind
/// .speechToText] downloads go through [ModelDownloadService] directly
/// (real HTTP-range resume, real progress, a local integrity fingerprint -
/// see that service's doc comment). [ModelKind.llm]/[ModelKind.embedding]
/// downloads instead construct a throwaway `LlamaDartLlmEngine`/
/// `LlamaDartEmbeddingEngine` pointed at the target [AiModelSpec
/// .downloadSource] and call its own `ensureModelReady` - `llamadart`'s
/// internal downloader already does real HTTP-range resume (confirmed by
/// source inspection, ADR-036), so this reuses it rather than
/// reimplementing it. A real, honest consequence of that choice: the
/// measured [InstalledModel.sizeBytes]/[InstalledModel.localSha256] for
/// these two kinds fall back to the catalog's approximation and `null`
/// respectively, since `llamadart` doesn't expose the downloaded file's
/// exact byte count or a content hash through its public API - see
/// [InstalledModel.localSha256]'s doc comment.
class ModelDownloadController extends Notifier<Map<String, ModelDownloadState>> {
  @override
  Map<String, ModelDownloadState> build() => const {};

  final Map<String, ModelDownloadCancelToken> _whisperCancelTokens = {};
  final Map<String, ModelDownloadCancelToken> _ocrCancelTokens = {};
  final Map<String, dynamic> _llamaEngines = {};

  ModelDownloadState stateFor(String modelId) => state[modelId] ?? const ModelDownloadIdle();

  void _setState(String modelId, ModelDownloadState value) {
    state = {...state, modelId: value};
  }

  /// Starts (or resumes) downloading [spec] - a no-op if [spec] is already
  /// downloading, the Model Safety guarantee against duplicate concurrent
  /// downloads of the same model (ADR-036): the [state] map is this
  /// controller's single source of truth for "is this already in flight",
  /// checked before any I/O starts.
  Future<void> start(AiModelSpec spec) async {
    if (stateFor(spec.id) is ModelDownloadInProgress) return;

    switch (spec.kind) {
      case ModelKind.speechToText:
      case ModelKind.llm:
      case ModelKind.embedding:
      case ModelKind.ocr:
        // Set *before* any `await` below (including the first one inside
        // `_startWhisperDownload`/`_startLlamaDownload`/`_startOcrDownload`,
        // all of which resolve a destination/construct an engine
        // asynchronously) - the guard above only works if nothing can
        // observe a stale [ModelDownloadIdle] between two back-to-back
        // `start()` calls for the same model. Setting this synchronously,
        // before this method's own first `await`, closes that gap
        // completely (Model Safety, ADR-036: no duplicate concurrent
        // downloads).
        _setState(spec.id, const ModelDownloadInProgress(fraction: null));
      case ModelKind.vision:
      case ModelKind.translation:
        _setState(
          spec.id,
          const ModelDownloadFailed('This model type is not available yet.'),
        );
        return;
    }

    switch (spec.kind) {
      case ModelKind.speechToText:
        await _startWhisperDownload(spec);
      case ModelKind.llm:
      case ModelKind.embedding:
        await _startLlamaDownload(spec);
      case ModelKind.ocr:
        // P0-7: OCR language packs are a plain HTTP file download (a
        // `.traineddata` file, not a llamadart-managed GGUF model), so this
        // reuses the exact same `ModelDownloadService` HTTP-range-resume
        // path Whisper already uses - only the destination directory
        // differs (`FlutterTesseractOcr.getTessdataPath()`, the one
        // directory the OCR plugin's own native `TessBaseAPI.init()` call
        // looks in, confirmed by reading the plugin's Android source).
        await _startOcrDownload(spec);
      case ModelKind.vision:
      case ModelKind.translation:
        break;
    }
  }

  /// [AiModelSpec.version] for every Whisper catalog entry is the exact
  /// `WhisperModel.modelName` string (`'tiny'`, `'large-v1'`, ...) - this
  /// resolves it back to the real enum value so the destination path is
  /// built by the package's own `getPath` (never a hand-duplicated string
  /// template that could silently drift from it).
  WhisperModel _whisperModelFor(AiModelSpec spec) =>
      WhisperModel.values.firstWhere((m) => m.modelName == spec.version);

  Future<File> _whisperDestination(AiModelSpec spec) async {
    final dir = await whisperModelDirectory();
    return File(_whisperModelFor(spec).getPath(dir.path));
  }

  Future<void> _startWhisperDownload(AiModelSpec spec) async {
    final destination = await _whisperDestination(spec);
    if (await destination.exists()) {
      await _recordInstalled(spec, destination);
      _setState(spec.id, const ModelDownloadDone());
      return;
    }

    final cancelToken = ModelDownloadCancelToken();
    _whisperCancelTokens[spec.id] = cancelToken;
    final service = ref.read(modelDownloadServiceProvider);

    // Beta blocker fix (docs/v3/implementation/03-decisions.md): this
    // entry point - the actual Model Manager/Model Details download flow
    // used after onboarding - never protected itself from OS suspension
    // while backgrounded, unlike `OnboardingSetupController.downloadModels`,
    // which already wires the same `BackgroundDownloadService` opt-in. The
    // underlying `.part` file/Range-resume logic in `HttpModelDownloadService`
    // was already correct; without this, a long download could be
    // suspended/killed mid-transfer before ever reaching a clean pause,
    // which is what produced the "restarts from 0" symptom - the bytes on
    // disk were fine, but the app never got a chance to resume them
    // gracefully. Same opt-in flag, same best-effort semantics as
    // onboarding's own usage.
    final allowBackground = ref.read(settingsControllerProvider).allowBackgroundDownloads;
    if (allowBackground) {
      await BackgroundDownloadService.start('Downloading ${spec.displayName}', 'Starting…');
    }

    try {
      final outcome = await service.download(
        url: spec.downloadSource,
        destination: destination,
        cancelToken: cancelToken,
        onProgress: (progress) {
          _setState(
            spec.id,
            ModelDownloadInProgress(
              fraction: progress.fraction,
              receivedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
            ),
          );
          if (allowBackground) {
            final pct = progress.fraction == null ? '' : ' ${(progress.fraction! * 100).round()}%';
            BackgroundDownloadService.update('${spec.displayName}$pct');
          }
        },
      );
      await _recordInstalled(spec, destination, sizeBytes: outcome.sizeBytes, sha256Hex: outcome.sha256Hex);
      _setState(spec.id, const ModelDownloadDone());
    } on ModelDownloadException catch (e) {
      _setState(
        spec.id,
        e.wasCancelled
            ? ModelDownloadPaused(receivedBytes: await _partialBytesOnDisk(destination))
            : ModelDownloadFailed(e.message),
      );
    } finally {
      _whisperCancelTokens.remove(spec.id);
      if (allowBackground) await BackgroundDownloadService.stop();
    }
  }

  /// Where an OCR language pack's `.traineddata` file lives -
  /// `FlutterTesseractOcr.getTessdataPath()` is the plugin's own directory
  /// (its native `TessBaseAPI.init()` call looks for
  /// `<parent>/tessdata/<language>.traineddata`, confirmed by reading
  /// `FlutterTesseractOcrPlugin.java`), never a path this app invents
  /// itself - the whole point is that a file downloaded here is
  /// immediately usable by the plugin with no extra copy step.
  /// [AiModelSpec.version] for every OCR catalog entry is the exact
  /// Tesseract language code (`'eng'`) the filename uses.
  Future<File> _ocrDestination(AiModelSpec spec) async {
    final dir = await FlutterTesseractOcr.getTessdataPath();
    return File(p.join(dir, '${spec.version}.traineddata'));
  }

  Future<void> _startOcrDownload(AiModelSpec spec) async {
    final destination = await _ocrDestination(spec);
    if (await destination.exists()) {
      await _recordInstalled(spec, destination);
      _setState(spec.id, const ModelDownloadDone());
      return;
    }

    final cancelToken = ModelDownloadCancelToken();
    _ocrCancelTokens[spec.id] = cancelToken;
    final service = ref.read(modelDownloadServiceProvider);

    final allowBackground = ref.read(settingsControllerProvider).allowBackgroundDownloads;
    if (allowBackground) {
      await BackgroundDownloadService.start('Downloading ${spec.displayName} OCR', 'Starting…');
    }

    try {
      final outcome = await service.download(
        url: spec.downloadSource,
        destination: destination,
        cancelToken: cancelToken,
        onProgress: (progress) {
          _setState(
            spec.id,
            ModelDownloadInProgress(
              fraction: progress.fraction,
              receivedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
            ),
          );
          if (allowBackground) {
            final pct = progress.fraction == null ? '' : ' ${(progress.fraction! * 100).round()}%';
            BackgroundDownloadService.update('${spec.displayName}$pct');
          }
        },
      );
      await _recordInstalled(spec, destination, sizeBytes: outcome.sizeBytes, sha256Hex: outcome.sha256Hex);
      _setState(spec.id, const ModelDownloadDone());
    } on ModelDownloadException catch (e) {
      _setState(
        spec.id,
        e.wasCancelled
            ? ModelDownloadPaused(receivedBytes: await _partialBytesOnDisk(destination))
            : ModelDownloadFailed(e.message),
      );
    } finally {
      _ocrCancelTokens.remove(spec.id);
      if (allowBackground) await BackgroundDownloadService.stop();
    }
  }

  /// Bytes already on disk for a `.part` file, or `null` if none exists -
  /// used to seed [ModelDownloadPaused.receivedBytes] accurately (both
  /// when a download is cooperatively paused and when
  /// [checkForResumableDownload] finds one on screen open after a cold
  /// app restart), so the resume affordance reflects real progress instead
  /// of looking like it's starting over.
  Future<int?> _partialBytesOnDisk(File destination) async {
    final partFile = File('${destination.path}.part');
    if (!await partFile.exists()) return null;
    return partFile.length();
  }

  /// Seeds an accurate [ModelDownloadPaused] state for [spec] if a
  /// resumable `.part` file already exists on disk but this controller's
  /// (in-memory, process-lifetime) state doesn't know about it yet - the
  /// case after a cold app restart (the OS killed the process while
  /// backgrounded, or the user simply force-closed the app mid-download).
  /// Call this when a model's details screen is opened; a no-op if a
  /// download is already actively tracked, if this isn't a Whisper model
  /// (the only kind whose `.part` path this controller can name directly -
  /// see this class's own doc comment on `llamadart`'s separate internal
  /// cache), or if there's genuinely nothing to resume. Never restarts
  /// anything from 0 on its own - purely a read of what's already there.
  Future<void> checkForResumableDownload(AiModelSpec spec) async {
    if (spec.kind != ModelKind.speechToText && spec.kind != ModelKind.ocr) return;
    if (stateFor(spec.id) is! ModelDownloadIdle) return;
    try {
      final destination =
          spec.kind == ModelKind.ocr ? await _ocrDestination(spec) : await _whisperDestination(spec);
      if (await destination.exists()) return;
      final hasPartial = await ref.read(modelDownloadServiceProvider).hasPartialDownload(destination);
      if (!hasPartial) return;
      final receivedBytes = await _partialBytesOnDisk(destination);
      _setState(spec.id, ModelDownloadPaused(receivedBytes: receivedBytes));
    } catch (_) {
      // Best-effort only, mirroring `BackgroundDownloadService`'s own
      // discipline - this is a pure UX nicety (an accurate initial state
      // instead of "Idle"/"Download"), never a required correctness step.
      // A failure here (e.g. the platform's own storage-path lookup not
      // being available) must never crash or block opening this screen;
      // worst case, the resume affordance simply doesn't pre-populate and
      // the user sees the same "Download" button `start()` already knows
      // how to resume correctly from anyway.
    }
  }

  Future<void> _startLlamaDownload(AiModelSpec spec) async {
    Object engine;
    if (spec.kind == ModelKind.llm) {
      engine = LlamaDartLlmEngine(modelSourceOverride: spec.downloadSource);
    } else {
      engine = LlamaDartEmbeddingEngine(modelSourceOverride: spec.downloadSource);
    }
    _llamaEngines[spec.id] = engine;

    // Same beta blocker fix as `_startWhisperDownload` - these are
    // typically the largest downloads of all, so the most exposed to being
    // suspended/killed while backgrounded without this.
    final allowBackground = ref.read(settingsControllerProvider).allowBackgroundDownloads;
    if (allowBackground) {
      await BackgroundDownloadService.start('Downloading ${spec.displayName}', 'Starting…');
    }

    void onProgress(double? fraction) {
      _setState(spec.id, ModelDownloadInProgress(fraction: fraction));
      if (allowBackground) {
        final pct = fraction == null ? '' : ' ${(fraction * 100).round()}%';
        BackgroundDownloadService.update('${spec.displayName}$pct');
      }
    }

    try {
      if (engine is LlamaDartLlmEngine) {
        await engine.ensureModelReady(onProgress: onProgress);
        await engine.unload();
      } else if (engine is LlamaDartEmbeddingEngine) {
        await engine.ensureModelReady(onProgress: onProgress);
        await engine.unload();
      }
      await _recordInstalled(spec, null, sizeBytes: spec.sizeBytesApprox);
      _setState(spec.id, const ModelDownloadDone());
    } on LlmModelDownloadTimeoutException catch (_) {
      // Thrown by `LlamaDartLlmEngine`/`LlamaDartEmbeddingEngine` when
      // `cancelActiveDownload()` cancels an in-flight download - see
      // `pause`'s doc comment for why this maps to the same resumable
      // [ModelDownloadPaused] state a real Whisper pause reaches.
      _setState(spec.id, const ModelDownloadPaused());
    } catch (e) {
      // V2.2 Production Hardening, Priority 6: was the raw exception
      // (`'$e'`) shown directly in Model Details' status section.
      _setState(spec.id, ModelDownloadFailed(friendlyErrorMessage(e)));
    } finally {
      // This throwaway engine was never attached to `ModelLifecycleManager`
      // (no `lifecycleManager:` passed to its constructor above) -
      // deliberately, since it exists only for the duration of this one
      // download and is explicitly `unload()`-ed on success above; nothing
      // further to release here on any path.
      _llamaEngines.remove(spec.id);
      if (allowBackground) await BackgroundDownloadService.stop();
    }
  }

  Future<void> _recordInstalled(
    AiModelSpec spec,
    File? destination, {
    int? sizeBytes,
    String? sha256Hex,
  }) async {
    final repo = ref.read(installedModelRepositoryProvider);
    final existing = await repo.getByModelId(spec.id);
    if (existing != null) return;

    int resolvedSize;
    if (sizeBytes != null) {
      resolvedSize = sizeBytes;
    } else if (destination != null && await destination.exists()) {
      resolvedSize = await destination.length();
    } else {
      resolvedSize = spec.sizeBytesApprox;
    }
    final row = InstalledModel(
      modelId: spec.id,
      kind: spec.kind,
      localPath: destination?.path ?? spec.downloadSource,
      sizeBytes: resolvedSize,
      downloadedAt: DateTime.now(),
      localSha256: sha256Hex,
      isActive: false,
    );
    await repo.insert(row);

    // Default Model Selection (Phase 6A objective 14): the first model
    // ever installed for a kind becomes active automatically - every
    // subsequent install for that kind requires an explicit "Activate"
    // (see `InstalledModelsController.activate`), never a silent switch.
    final activeAlready = await repo.getActiveForKind(spec.kind);
    if (activeAlready == null) {
      await repo.setActive(spec.kind, spec.id);
    }
  }

  /// Pauses [spec]'s in-flight download - real, resumable pause for
  /// [ModelKind.speechToText] (the `.part` file is left on disk, next
  /// [start] call resumes it). For [ModelKind.llm]/[ModelKind.embedding],
  /// this cancels the throwaway engine's download; `llamadart`'s own
  /// cache resumes on the next [start] call the same way (confirmed by
  /// source inspection, ADR-036) - the *outcome* is equivalent resumable
  /// pause behavior, even though the two kinds reach it through different
  /// underlying mechanisms.
  void pause(String modelId) {
    _whisperCancelTokens[modelId]?.cancel();
    _ocrCancelTokens[modelId]?.cancel();
    final engine = _llamaEngines[modelId];
    if (engine is LlamaDartLlmEngine) engine.cancelActiveDownload();
    if (engine is LlamaDartEmbeddingEngine) engine.cancelActiveDownload();
  }

  /// Cancels [spec]'s download and discards any partial data - unlike
  /// [pause], this is not resumable. Only fully precise for
  /// [ModelKind.speechToText] (this controller owns the exact `.part`
  /// file path); for [ModelKind.llm]/[ModelKind.embedding], `llamadart`'s
  /// own cache directory is left as-is (no public cache-eviction API - see
  /// ADR-036's disclosed limitation, also covered by the Storage Usage
  /// screen's "Delete Cache" action).
  Future<void> cancelAndDiscard(AiModelSpec spec) async {
    pause(spec.id);
    if (spec.kind == ModelKind.speechToText || spec.kind == ModelKind.ocr) {
      final destination =
          spec.kind == ModelKind.ocr ? await _ocrDestination(spec) : await _whisperDestination(spec);
      await ref.read(modelDownloadServiceProvider).deletePartialDownload(destination);
    }
    _setState(spec.id, const ModelDownloadIdle());
  }

  /// Re-verifies an already-installed model - see [InstalledModel
  /// .localSha256]'s doc comment for what this can prove per kind.
  Future<bool> verify(AiModelSpec spec, InstalledModel installed) async {
    _setState(spec.id, const ModelDownloadVerifying());
    try {
      if (spec.kind == ModelKind.speechToText || spec.kind == ModelKind.ocr) {
        final file = File(installed.localPath);
        if (!await file.exists()) {
          _setState(spec.id, const ModelDownloadFailed('The model file is missing - please re-download.'));
          return false;
        }
        final actualSize = await file.length();
        var ok = actualSize == installed.sizeBytes;
        final storedHash = installed.localSha256;
        if (ok && storedHash != null) {
          final hashSink = AccumulatorSink<Digest>();
          final input = sha256.startChunkedConversion(hashSink);
          await for (final chunk in file.openRead()) {
            input.add(chunk);
          }
          input.close();
          ok = hashSink.events.single.toString() == storedHash;
        }
        _setState(
          spec.id,
          ok
              ? const ModelDownloadDone()
              : const ModelDownloadFailed('The model file appears corrupted - please re-download.'),
        );
        return ok;
      }
      // LLM/embedding: `ensureModelReady()` re-triggers `llamadart`'s own
      // cache validation (confirmed real by source inspection - a cache
      // hit re-checks byte count against its stored metadata before
      // trusting it); a corrupted cache re-downloads transparently rather
      // than silently serving a bad file.
      await start(spec);
      return stateFor(spec.id) is! ModelDownloadFailed;
    } finally {
      if (stateFor(spec.id) is ModelDownloadVerifying) _setState(spec.id, const ModelDownloadDone());
    }
  }
}

final modelDownloadControllerProvider =
    NotifierProvider<ModelDownloadController, Map<String, ModelDownloadState>>(
  ModelDownloadController.new,
);
