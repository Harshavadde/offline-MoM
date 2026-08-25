import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/llamadart_llm_engine.dart' show LlmModelDownloadTimeoutException;
import '../../../../services/ai/model_download_service.dart' show ModelDownloadException;
import '../../../../services/ai/whisper_speech_to_text_engine.dart';
import '../../../../services/background/background_download_service.dart';

/// State for the mandatory first-run model download (onboarding's second
/// step). Deliberately has no "skip" variant: the user only reaches Home
/// once this succeeds, per the app's requirement that AI models are ready
/// before the main app is usable, rather than downloading silently the
/// first time a meeting is recorded/imported.
sealed class OnboardingSetupState {
  const OnboardingSetupState();
}

class OnboardingSetupIdle extends OnboardingSetupState {
  const OnboardingSetupIdle();
}

/// Every selected speech-to-text model size downloads concurrently with
/// the LLM (not one after another) - each entry in [sttFractions] (keyed
/// by model name, e.g. "small") and [llmFraction] progresses independently,
/// and any of them may already be null (unknown total size) or 1.0
/// (finished, waiting on the others) while the download is still ongoing
/// overall.
class OnboardingSetupDownloading extends OnboardingSetupState {
  const OnboardingSetupDownloading({this.sttFractions = const {}, this.llmFraction});

  final Map<String, double?> sttFractions;
  final double? llmFraction;
}

class OnboardingSetupFailed extends OnboardingSetupState {
  const OnboardingSetupFailed(this.message, {this.wasPaused = false});
  final String message;

  /// R-11 P0 fix: true when this "failure" is actually the download(s)
  /// being cooperatively paused (a stall/backgrounding-induced timeout, or
  /// an explicit cancellation) rather than a genuine error - mirrors
  /// `ModelDownloadFailed.wasPaused` in the post-onboarding Model Manager
  /// (`model_download_providers.dart`), which already makes this exact
  /// distinction correctly. On a real device with no foreground service
  /// keeping the connection alive while backgrounded
  /// (`AppSettings.allowBackgroundDownloads` defaults to false), this is
  /// the common case, not the exceptional one - the `.part` file for every
  /// interrupted download is always preserved on disk regardless (see
  /// [WhisperSpeechToTextEngine.ensureModelDownloaded]'s and
  /// [LlamaDartLlmEngine.ensureModelReady]'s own doc comments), so "tap to
  /// continue" always genuinely resumes rather than restarting from byte 0.
  final bool wasPaused;
}

class OnboardingSetupDone extends OnboardingSetupState {
  const OnboardingSetupDone();
}

class OnboardingSetupController extends Notifier<OnboardingSetupState> {
  @override
  OnboardingSetupState build() => const OnboardingSetupIdle();

  static const _llmLabel = 'AI language model';
  static const _notificationTitle = 'Setting up OfflineMoMAI';

  final Map<String, double?> _sttFractions = {};
  double? _llmFraction;

  /// Real bug found in the reliability-overhaul pass: `Future.wait` below
  /// completes - and this method proceeds into its `catch`/`finally` -
  /// the instant *any one* of the concurrent downloads fails, but the
  /// *other* downloads keep running orphaned in the background (nothing
  /// cancels them). Their `onProgress` callbacks kept firing afterward and
  /// overwrote `OnboardingSetupFailed` back to `OnboardingSetupDownloading`
  /// moments later, within that same failed attempt - the "Retry" button
  /// would flicker or vanish unpredictably - and if the user tapped Retry
  /// (starting a genuinely new attempt) while the old orphaned download was
  /// still writing to the same destination file, its late callbacks could
  /// also corrupt the new attempt's own progress state or flip it straight
  /// to `OnboardingSetupDone` before the new attempt had actually finished.
  /// Incremented on every call to [downloadModels]; each callback captures
  /// the generation it belongs to and checks [_isCurrentAttempt] (which
  /// also covers the same-attempt-already-ended case via
  /// [_currentAttemptEnded]) before writing `state` - a stale callback,
  /// whether from an abandoned attempt or an orphaned download outliving
  /// its own now-finished attempt, can never mutate current state again.
  int _generation = 0;
  bool _currentAttemptEnded = true;

  bool _isCurrentAttempt(int generation) =>
      generation == _generation && !_currentAttemptEnded;

  /// R-11 P0 fix: true for exactly the exception shapes a stall/overall
  /// download timeout or an explicit cancellation produces -
  /// [ModelDownloadException.wasCancelled] for the Whisper/`HttpModelDownloadService`
  /// path, and [LlmModelDownloadTimeoutException] for the LLM path (which
  /// - unlike a genuine HTTP error from `llamadart`'s own downloader - is
  /// only ever thrown from this app's own stall/overall timer cancelling
  /// the attempt, never from a real server error). Never true for an
  /// actual failure (bad URL, disk full, corrupt download, no internet at
  /// the very first attempt) - those still show as a real error, not a
  /// falsely-reassuring "paused".
  bool _wasPaused(Object e) {
    if (e is ModelDownloadException) return e.wasCancelled;
    if (e is LlmModelDownloadTimeoutException) return true;
    return false;
  }

  String _notificationText() {
    String pct(double? fraction) =>
        fraction == null ? '' : ' ${(fraction * 100).round()}%';
    final sttPart = _sttFractions.entries
        .map((e) => 'Speech-to-text (${e.key})${pct(e.value)}')
        .join(', ');
    return '$sttPart · $_llmLabel${pct(_llmFraction)}';
  }

  /// [sttModelNames] is the ordered set of Whisper model sizes the user
  /// picked to download (e.g. `['small']`, or `['base', 'small']` if they
  /// want more than one ready to switch between later without waiting).
  /// If the app's currently-active model isn't among them, the last one
  /// downloaded (the most accurate of the selection, since the UI orders
  /// them tiny -> base -> small) becomes the new active model.
  Future<void> downloadModels(List<String> sttModelNames) async {
    final allowBackground =
        ref.read(settingsControllerProvider).allowBackgroundDownloads;
    _sttFractions
      ..clear()
      ..addEntries(sttModelNames.map((name) => MapEntry(name, null)));
    _llmFraction = null;
    if (allowBackground) {
      await BackgroundDownloadService.start(_notificationTitle, _notificationText());
    }

    final myGeneration = ++_generation;
    _currentAttemptEnded = false;

    state = OnboardingSetupDownloading(sttFractions: Map.of(_sttFractions));
    try {
      // Every selected model, plus the LLM, downloads at the same time
      // rather than one after the other, since none of them depend on
      // each other - far faster than downloading sequentially.
      await Future.wait([
        for (final name in sttModelNames)
          WhisperSpeechToTextEngine.ensureModelDownloaded(
            WhisperModel.values.firstWhere(
              (m) => m.name == name,
              orElse: () => WhisperModel.small,
            ),
            downloadService: ref.read(modelDownloadServiceProvider),
            onProgress: (fraction) {
              if (!_isCurrentAttempt(myGeneration)) return;
              _sttFractions[name] = fraction;
              state = OnboardingSetupDownloading(
                sttFractions: Map.of(_sttFractions),
                llmFraction: _llmFraction,
              );
              if (allowBackground) BackgroundDownloadService.update(_notificationText());
            },
          ),
        ref.read(llmEngineProvider).ensureModelReady(
          onProgress: (fraction) {
            if (!_isCurrentAttempt(myGeneration)) return;
            _llmFraction = fraction;
            state = OnboardingSetupDownloading(
              sttFractions: Map.of(_sttFractions),
              llmFraction: _llmFraction,
            );
            if (allowBackground) BackgroundDownloadService.update(_notificationText());
          },
        ),
      ]);
      if (!_isCurrentAttempt(myGeneration)) return;

      final settingsNotifier = ref.read(settingsControllerProvider.notifier);
      final activeModel = ref.read(settingsControllerProvider).whisperModelName;
      if (!sttModelNames.contains(activeModel) && sttModelNames.isNotEmpty) {
        await settingsNotifier.setWhisperModelName(sttModelNames.last);
      }

      await settingsNotifier.completeOnboarding();
      if (!_isCurrentAttempt(myGeneration)) return;
      _currentAttemptEnded = true;
      state = const OnboardingSetupDone();
    } catch (e) {
      if (!_isCurrentAttempt(myGeneration)) return;
      _currentAttemptEnded = true;
      state = OnboardingSetupFailed(friendlyErrorMessage(e), wasPaused: _wasPaused(e));
    } finally {
      if (allowBackground) await BackgroundDownloadService.stop();
    }
  }
}

final onboardingSetupControllerProvider =
    NotifierProvider<OnboardingSetupController, OnboardingSetupState>(
  OnboardingSetupController.new,
);

/// Which Whisper model sizes the user has chosen to download during setup.
/// UI-only selection, not persisted - defaults to just the app's current
/// default model, so a user who doesn't touch this still gets today's
/// single-model behavior.
final selectedWhisperModelsProvider = StateProvider<Set<String>>((ref) {
  return {ref.read(settingsControllerProvider).whisperModelName};
});
