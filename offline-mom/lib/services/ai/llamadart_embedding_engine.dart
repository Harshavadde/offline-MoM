import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../../core/logging/app_logger.dart';
import 'download_progress_throttle.dart';
import 'embedding_engine.dart';
import 'llamadart_llm_engine.dart' show LlmModelDownloadTimeoutException, LlmTimeoutException;
import 'model_lifecycle_manager.dart';

/// [EmbeddingEngine] backed by `llamadart`'s `LlamaEngine.embed`/`embedBatch`
/// (confirmed to exist and to require no special model-load flags by direct
/// source inspection of `llamadart` 0.8.17 - see
/// docs/v2/implementation/spikes/m1-0-embedding-spike.md for the full
/// evidence trail). This is a **second, independent** `LlamaEngine`
/// instance from [LlamaDartLlmEngine]'s - same package, same
/// `llama.cpp`-based native runtime and worker-isolate infrastructure
/// (ADR-003 option 1: "reuse the existing LLM's llama.cpp path"), but a
/// different, much smaller GGUF model loaded into its own context, since
/// the chat model (Qwen2.5-1.5B-Instruct) is not an embedding model and
/// `llama_set_embeddings`/`llama_get_embeddings` need a context whose
/// pooling type actually matches an embedding model's metadata.
///
/// Deliberately reuses [LlmTimeoutException]/[LlmModelDownloadTimeoutException]
/// rather than declaring parallel embedding-specific exception types - both
/// are already generic "the shared llama.cpp-backed engine stalled" concepts,
/// not chat-specific ones, and every call site that already handles one
/// (Document.errorMessage surfacing, retry affordances) handles the other
/// identically for free.
class LlamaDartEmbeddingEngine implements EmbeddingEngine {
  /// `embeddinggemma-300M`, Q8_0 quantization (~300MB) - the exact model
  /// `llamadart`'s own maintainers demonstrate working against `embed`/
  /// `embedBatch` in the package's `llamadart_embedding_example.dart`,
  /// chosen specifically to minimize integration risk given this spike
  /// could not itself execute a real on-device download+embed round trip
  /// (see the spike report's "What was and wasn't validated" section).
  /// Distributed under Google's Gemma Terms of Use, not a plain permissive
  /// OSS license - flagged for the same kind of pre-launch check ADR-016
  /// already mandates for parsing *libraries*, extended here to a model
  /// *asset* since this is the first time that question has come up.
  static const _defaultModelSource =
      'hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf';

  static const modelDisplayName = 'On-device embedding model';

  static const _stallTimeout = Duration(seconds: 45);
  // R-11 P0 fix: raised from 90s/15min - see LlamaDartLlmEngine's identical
  // fields for the full real-device reasoning (no foreground service keeps
  // the connection alive while backgrounded, so the old values reliably
  // tripped on a normal "lock the phone" interruption).
  static const _downloadStallTimeout = Duration(minutes: 3);
  static const _downloadOverallTimeout = Duration(minutes: 30);

  LlamaDartEmbeddingEngine({ModelLifecycleManager? lifecycleManager, String? modelSourceOverride})
      : _lifecycleManager = lifecycleManager,
        _modelSource = modelSourceOverride ?? _defaultModelSource {
    _lifecycleManager?.attach(
      ModelKind.embedding,
      unload: unload,
      statusOf: () => status,
    );
  }

  final ModelLifecycleManager? _lifecycleManager;
  final _log = const AppLogger('LlamaDartEmbeddingEngine');

  /// See `LlamaDartLlmEngine._modelSource`'s identical doc comment.
  final String _modelSource;

  LlamaEngine? _engine;

  /// The in-flight first load, if any - mirrors
  /// `LlamaDartLlmEngine._loading`'s exact reasoning (Phase 3A: prevents a
  /// duplicate concurrent load racing two first-ever callers).
  Future<LlamaEngine>? _loading;

  /// See `LlamaDartLlmEngine`'s identical pair of members.
  ModelDownloadCancelToken? _activeDownloadCancelToken;
  void cancelActiveDownload() => _activeDownloadCancelToken?.cancel();
  bool get isDownloading => _loading != null;

  ModelStatus get status {
    if (_engine != null) return ModelStatus.loaded;
    if (_loading != null) return ModelStatus.loading;
    return ModelStatus.unloaded;
  }

  Future<LlamaEngine> _ensureLoaded({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) {
    final existing = _engine;
    if (existing != null) return Future.value(existing);

    final inFlight = _loading;
    if (inFlight != null) return inFlight;

    final future = _load(onPreparingModel: onPreparingModel, onProgress: onProgress);
    _loading = future;
    return future;
  }

  Future<LlamaEngine> _load({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {
    final engine = LlamaEngine(LlamaBackend());
    final cancelToken = ModelDownloadCancelToken();
    _activeDownloadCancelToken = cancelToken;
    var announced = false;
    Timer? stallTimer;
    void resetStallTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(_downloadStallTimeout, cancelToken.cancel);
    }

    final uiThrottle = ProgressThrottle();
    final overallTimer = Timer(_downloadOverallTimeout, cancelToken.cancel);
    try {
      await engine.loadModelSource(
        ModelSource.parse(_modelSource),
        options: ModelLoadOptions(cancelToken: cancelToken),
        onProgress: (progress) {
          if (!announced) {
            announced = true;
            onPreparingModel?.call();
          }
          if (uiThrottle.shouldEmit()) onProgress?.call(progress.fraction);
          resetStallTimer();
        },
      );
      onProgress?.call(1.0);
    } on LlamaStateException {
      if (cancelToken.isCancelled) {
        throw LlmModelDownloadTimeoutException(
          'The embedding model download stalled or took too long (over '
          '${_downloadOverallTimeout.inMinutes} min) - try a faster or '
          'more stable connection (Wi-Fi works best) and retry. This is '
          'a one-time ~300MB download; it will resume rather than start '
          'over.',
        );
      }
      rethrow;
    } finally {
      stallTimer?.cancel();
      overallTimer.cancel();
      _loading = null;
      _activeDownloadCancelToken = null;
    }
    _log.info('Model loaded.');
    _engine = engine;
    return engine;
  }

  /// Unloads the model, freeing its native memory - see
  /// `LlamaDartLlmEngine.unload`'s identical reasoning. A no-op if nothing
  /// is currently loaded.
  Future<void> unload() async {
    final engine = _engine;
    if (engine == null) return;
    _engine = null;
    await engine.unloadModel();
    _log.info('Model unloaded.');
  }

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {
    _lifecycleManager?.beginUse(ModelKind.embedding);
    try {
      await _ensureLoaded(onPreparingModel: onPreparingModel, onProgress: onProgress);
    } finally {
      _lifecycleManager?.endUse(ModelKind.embedding);
    }
  }

  @override
  Future<List<double>> embed(String text, {bool normalize = true}) async {
    _lifecycleManager?.beginUse(ModelKind.embedding);
    try {
      final engine = await _ensureLoaded();
      try {
        return await engine.embed(text, normalize: normalize).timeout(_stallTimeout);
      } on TimeoutException {
        // Frees the shared engine for the next caller - mirrors
        // `LlamaDartLlmEngine._collect`'s identical fix (Phase 3A: a
        // stalled embed call previously left the native computation
        // running with no way to reclaim it, unlike chat generation which
        // already did this).
        engine.cancelGeneration();
        throw LlmTimeoutException(
          'The embedding model stopped responding after '
          '${_stallTimeout.inSeconds}s - please retry.',
        );
      }
    } finally {
      _lifecycleManager?.endUse(ModelKind.embedding);
    }
  }

  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    bool normalize = true,
  }) async {
    if (texts.isEmpty) return const [];
    _lifecycleManager?.beginUse(ModelKind.embedding);
    try {
      final engine = await _ensureLoaded();
      try {
        return await engine.embedBatch(texts, normalize: normalize).timeout(_stallTimeout);
      } on TimeoutException {
        engine.cancelGeneration();
        throw LlmTimeoutException(
          'The embedding model stopped responding after '
          '${_stallTimeout.inSeconds}s - please retry.',
        );
      }
    } finally {
      _lifecycleManager?.endUse(ModelKind.embedding);
    }
  }
}
