import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/connectivity_check.dart';
import '../../../../models/profession_profile.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/model_catalog.dart';
import '../../../../services/ai/model_lifecycle_manager.dart' show ModelKind;
import '../../../../services/ai/profession_recommendations.dart';
import 'installed_models_providers.dart';
import 'model_download_providers.dart';

/// The user's currently-saved profession (`AppSettings.professionProfile`,
/// Phase 6A), decoded back into a [ProfessionProfile] - `null` if unset.
final selectedProfessionProvider = Provider<ProfessionProfile?>((ref) {
  final raw = ref.watch(settingsControllerProvider).professionProfile;
  if (raw == null) return null;
  for (final p in ProfessionProfile.values) {
    if (p.name == raw) return p;
  }
  return null;
});

/// The recommendation for [selectedProfessionProvider], or `null` if no
/// profession has been chosen yet - drives the AI Model Manager home
/// screen's "Recommended for you" banner (Phase 6A objective 11).
final currentRecommendationProvider = Provider<ProfessionRecommendation?>((ref) {
  final profession = ref.watch(selectedProfessionProvider);
  if (profession == null) return null;
  return ProfessionRecommendations.forProfession(profession);
});

/// Thrown by [ProfessionSetupController.applyRecommendedSetup] when one of
/// the recommended models fails to download - [message] is already
/// user-appropriate text (either [ModelDownloadException]'s own
/// hand-authored wording, for Whisper, or [friendlyErrorMessage]'s output,
/// for LLM/embedding - see [ModelDownloadController]'s two catch blocks),
/// so [toString] returns it verbatim rather than prefixing "Exception: "
/// the way a bare `Exception(message)` would - same convention as
/// `LlmTimeoutException`/every other hand-authored exception in this app.
class ModelSetupException implements Exception {
  ModelSetupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One-tap Recommended Setup (Phase 6A objective 13): saves the chosen
/// [ProfessionProfile], then downloads and activates every model
/// [ProfessionRecommendations.forProfession] recommends for it. Each of
/// the 3 downloads is independently idempotent (a cache hit resolves
/// near-instantly - see [ModelDownloadController.start]'s per-kind doc
/// comments), so re-running this for a profession whose models are
/// already installed is cheap and safe, not just tolerated.
class ProfessionSetupController extends AsyncNotifier<void> {
  @override
  void build() {}

  bool _cancelled = false;

  /// Cancels an in-progress [applyRecommendedSetup] call (V2.2 Production
  /// Hardening, Priority 4 - real-device QA finding: there was previously
  /// no way to cancel this at all). The model currently downloading is
  /// paused via the same resumable [ModelDownloadController.pause] a
  /// manual pause in AI Model Manager uses - re-running Recommended Setup
  /// later resumes it rather than starting over. Models not yet reached
  /// are simply never started.
  void cancel() {
    _cancelled = true;
  }

  Future<void> applyRecommendedSetup(ProfessionProfile profession) async {
    _cancelled = false;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // V2.2 Production Hardening, Priority 4 (real-device QA finding):
      // checked once, up front - a device with no connection previously
      // only found out via a raw download failure partway through the
      // first model. This is a best-effort pre-flight check, not a
      // guarantee (a connection can still drop mid-download, which the
      // existing ModelDownloadFailed/friendlyErrorMessage path already
      // handles) - it just gives an immediate, clear answer for the
      // common case instead of always waiting for a download attempt to
      // fail first.
      if (!await hasInternetConnection()) {
        throw ModelSetupException(
          'No internet connection. Setting up AI models needs an internet '
          'connection once, to download them - after that, everything '
          'runs fully offline. Connect to Wi-Fi or mobile data and try '
          'again.',
        );
      }

      await ref.read(settingsControllerProvider.notifier).setProfessionProfile(profession.name);

      final recommendation = ProfessionRecommendations.forProfession(profession);
      final downloadController = ref.read(modelDownloadControllerProvider.notifier);
      final installedController = ref.read(installedModelsControllerProvider.notifier);

      final specs = [
        (ModelKind.llm, recommendation.recommendedLlmModelId),
        (ModelKind.embedding, recommendation.recommendedEmbeddingModelId),
        (ModelKind.speechToText, recommendation.recommendedWhisperModelId),
      ];

      for (final (kind, modelId) in specs) {
        if (_cancelled) return;
        final spec = ModelCatalog.byId(modelId);
        if (spec == null) continue;

        await downloadController.start(spec);

        if (_cancelled) {
          downloadController.pause(spec.id);
          return;
        }

        // V2.2 Production Hardening, Priority 4 (real-device QA finding):
        // previously this unconditionally activated every model in
        // [specs] regardless of whether its download actually succeeded.
        // ModelDownloadController.start() never throws on failure (every
        // failure is caught internally into a ModelDownloadFailed state,
        // not rethrown) - so a failed download here silently fell through
        // to Activate anyway, which could leave a *different*, previously
        // -active model deactivated in favor of one that was never
        // actually installed.
        final downloadState = downloadController.stateFor(spec.id);
        if (downloadState is ModelDownloadFailed) {
          throw ModelSetupException(downloadState.message);
        }
        // Reliability-overhaul pass: activate() now verifies before
        // switching (Phase 14/17) and returns false rather than throwing
        // if that verification fails - checked here for the same reason
        // the ModelDownloadFailed check above exists: a just-downloaded
        // model that somehow fails its own integrity check must not be
        // silently treated as "set up successfully".
        final activated = await installedController.activate(kind, modelId);
        if (!activated) {
          throw ModelSetupException(
            '${spec.displayName} downloaded but failed verification. Please try again.',
          );
        }
      }
    });
  }
}

final professionSetupControllerProvider =
    AsyncNotifierProvider<ProfessionSetupController, void>(ProfessionSetupController.new);
