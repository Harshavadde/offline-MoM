import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';

/// Which model-backed engine a [ModelLifecycleManager] entry tracks. Every
/// value corresponds to exactly one model-backed engine in
/// `lib/services/ai/` - kept as an enum (not the engine types themselves)
/// so this file has zero dependency on `llamadart`/`whisper_flutter_new` or
/// any concrete engine class, matching the same "presentation/use-case code
/// never depends on a specific wrapper package" discipline
/// `LlmEngine`/`EmbeddingEngine`/`SpeechToTextEngine` already establish.
///
/// [ocr], [vision], and [translation] are Phase 6A additions (ADR-036,
/// docs/v2/implementation/03-decisions.md) with **no backing engine or
/// catalog entry today** - reserved so the AI Model Manager's catalog,
/// database schema, and UI (all generic over [ModelKind]) never need a
/// migration or refactor the day a real engine for one of them ships; only
/// that engine and its catalog entries would need adding then. Every
/// existing call site that switches over [ModelKind] exhaustively
/// (`ModelLifecycleManager` itself has none - it never branches on the enum
/// value, only uses it as a map key) is unaffected by this extension.
enum ModelKind { llm, embedding, speechToText, ocr, vision, translation }

/// A model-backed engine's current residency state - not the same thing as
/// "has this device ever downloaded the model file" ([WhisperSpeechToTextEngine
/// .isModelDownloaded]/download-cache checks answer that question
/// separately and are unaffected by this enum).
enum ModelStatus {
  /// No native model resident in memory - either never loaded, or unloaded
  /// (explicitly, or by [ModelLifecycleManager]'s idle timeout).
  unloaded,

  /// A download and/or native load is currently in progress.
  loading,

  /// A native model is resident in memory and ready for inference.
  loaded,
}

/// Centralizes what Phase 3A's "model lifecycle manager" requirement asks
/// for: loading is still each engine's own responsibility (lazy, on first
/// use, exactly as before Phase 3A - see `LlamaDartLlmEngine._ensureLoaded`/
/// `LlamaDartEmbeddingEngine._ensureLoaded`), but *unloading*, *duplicate-load
/// prevention*, *status reporting*, and *reference-counted idle cleanup* are
/// centralized here rather than each engine reinventing them.
///
/// An engine that wants to be managed calls [attach] once (at construction,
/// via DI - see `app_providers.dart`) with its own `unload`/`statusOf`
/// callbacks, then wraps every public method body in
/// `beginUse(kind)` / `endUse(kind)` (see `LlamaDartLlmEngine`/
/// `LlamaDartEmbeddingEngine`/`WhisperSpeechToTextEngine` for the concrete
/// wiring). This is a plain callback registration, not a typed dependency
/// on any engine class, so [LlmEngine]/[EmbeddingEngine]/
/// [SpeechToTextEngine] (and every existing fake test double implementing
/// only those interfaces - `FakeLlmEngine`, `FakeEmbeddingEngine`,
/// `FakeSpeechToTextEngine`) need no changes at all to keep working exactly
/// as before; only the three real, `llamadart`/`whisper_flutter_new`-backed
/// implementations opt in.
///
/// Reference counting: [beginUse] increments a per-kind counter (and
/// cancels any pending idle-unload timer); [endUse] decrements it, and only
/// once it reaches zero does the idle-unload timer start (or restart). This
/// guarantees a model already serving a request is never unloaded out from
/// under it, no matter how long that single request takes relative to
/// [idleTimeout] - the clock only starts once nothing is using the model.
class ModelLifecycleManager {
  ModelLifecycleManager({
    this.idleTimeout = AppConstants.modelIdleUnloadTimeout,
  });

  final Duration idleTimeout;
  final _log = const AppLogger('ModelLifecycleManager');
  final Map<ModelKind, _ModelEntry> _entries = {};

  /// Registers (or re-registers) [kind]'s lifecycle callbacks. Safe to call
  /// again for the same [kind] - e.g. if a provider rebuilds the engine
  /// (settings change) - any pending idle timer from the previous
  /// registration is cancelled first so it can never fire against a
  /// since-replaced engine instance.
  void attach(
    ModelKind kind, {
    required Future<void> Function() unload,
    required ModelStatus Function() statusOf,
  }) {
    _entries[kind]?.idleTimer?.cancel();
    _entries[kind] = _ModelEntry(unload: unload, statusOf: statusOf);
  }

  /// Current residency status, or [ModelStatus.unloaded] if [kind] was
  /// never [attach]ed (nothing to report yet).
  ModelStatus statusOf(ModelKind kind) =>
      _entries[kind]?.statusOf.call() ?? ModelStatus.unloaded;

  /// How many callers currently hold [kind] "in use" (between a
  /// [beginUse]/[endUse] pair) - exposed for tests/diagnostics, not
  /// something call sites should branch on.
  int refCountOf(ModelKind kind) => _entries[kind]?.refCount ?? 0;

  /// Marks one caller as actively using [kind]'s model - cancels any
  /// pending idle-unload timer, since the model is now demonstrably not
  /// idle. Always paired with a later [endUse] (typically in a `finally`
  /// block), even if the call throws.
  void beginUse(ModelKind kind) {
    final entry = _entries[kind];
    if (entry == null) return;
    entry.refCount++;
    entry.idleTimer?.cancel();
    entry.idleTimer = null;
  }

  /// Ends one [beginUse] - once every caller has called [endUse] (ref count
  /// back to zero), starts the idle-unload countdown.
  void endUse(ModelKind kind) {
    final entry = _entries[kind];
    if (entry == null) return;
    if (entry.refCount > 0) entry.refCount--;
    if (entry.refCount == 0) _scheduleIdleUnload(kind, entry);
  }

  void _scheduleIdleUnload(ModelKind kind, _ModelEntry entry) {
    entry.idleTimer?.cancel();
    entry.idleTimer = Timer(idleTimeout, () => unmanagedUnload(kind));
  }

  /// Unloads [kind] right now if (and only if) nothing is currently using
  /// it - never interrupts an in-flight caller. Safe to call at any time,
  /// including when [kind] is already unloaded (a no-op) or mid-load (also
  /// a no-op - a caller that wants to abort a download uses that engine's
  /// own cancellation path, not this).  Exposed publicly (not just reached
  /// via the idle timer) so a future low-memory signal or explicit Settings
  /// action can request the same "unload if safe to do so" behavior on
  /// demand.
  Future<void> unmanagedUnload(ModelKind kind) async {
    final entry = _entries[kind];
    if (entry == null) return;
    if (entry.refCount > 0) return;
    if (entry.statusOf() != ModelStatus.loaded) return;

    _log.info('Unloading idle model: ${kind.name}');
    try {
      await entry.unload();
    } catch (e, stackTrace) {
      _log.warning('Failed to unload idle model ${kind.name}', error: e, stackTrace: stackTrace);
    }
  }

  /// Cancels every pending idle timer - called when the owning provider
  /// itself is disposed (app shutdown / a full `ProviderContainer` reset in
  /// tests), so no timer ever fires after the thing it would act on is
  /// gone.
  void dispose() {
    for (final entry in _entries.values) {
      entry.idleTimer?.cancel();
    }
    _entries.clear();
  }
}

class _ModelEntry {
  _ModelEntry({required this.unload, required this.statusOf});

  final Future<void> Function() unload;
  final ModelStatus Function() statusOf;
  int refCount = 0;
  Timer? idleTimer;
}
