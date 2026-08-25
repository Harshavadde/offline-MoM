import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:offline_mom/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/services/ai/llamadart_llm_engine.dart' show LlmModelDownloadTimeoutException;
import 'package:offline_mom/services/ai/model_download_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_helpers/fake_ai_engines.dart';

/// [whisperModelDirectory] resolves via `getApplicationSupportDirectory()`
/// on Android or `getLibraryDirectory()` elsewhere - `flutter test` always
/// runs on the host, so only `getLibraryPath` needs faking (mirrors
/// `model_download_controller_test.dart`'s identical pattern).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getLibraryPath() async => _path;
  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

/// A [ModelDownloadService] whose [download] emits one progress event, then
/// blocks on [releaseGate] before emitting a second, later event and
/// finishing - lets a test hold one call's whisper download open while a
/// *second, overlapping* call to `downloadModels()` starts and finishes.
class _GatedFakeModelDownloadService implements ModelDownloadService {
  final _gate = Completer<void>();
  void releaseGate() => _gate.complete();

  @override
  Future<bool> hasPartialDownload(File destination) async => false;

  @override
  Future<void> deletePartialDownload(File destination) async {}

  @override
  Future<ModelDownloadOutcome> download({
    required String url,
    required File destination,
    required ModelDownloadCancelToken cancelToken,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(const ModelDownloadProgress(receivedBytes: 100, totalBytes: 1000));
    await _gate.future;
    onProgress?.call(const ModelDownloadProgress(receivedBytes: 1000, totalBytes: 1000));
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes([1, 2, 3]);
    return const ModelDownloadOutcome(sizeBytes: 3, sha256Hex: 'fake-sha256');
  }
}

void main() {
  late Directory modelDir;
  late Directory hiveDir;
  late Box settingsBox;
  late ProviderContainer container;

  setUp(() async {
    modelDir = await Directory.systemTemp.createTemp('onboarding_setup_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(modelDir.path);

    // downloadModels() reads/writes AppSettings (allowBackgroundDownloads,
    // whisperModelName, onboardingComplete) via SettingsController, which
    // needs a real Hive box - mirrors model_download_controller_test.dart's
    // identical setup.
    hiveDir = await Directory.systemTemp.createTemp('onboarding_setup_controller_test_hive_');
    Hive.init(hiveDir.path);
    settingsBox = await Hive.openBox('settings_box_test');
  });

  tearDown(() async {
    container.dispose();
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
    await settingsBox.deleteFromDisk();
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  group('OnboardingSetupController.downloadModels', () {
    test('a normal, all-succeeding download reaches OnboardingSetupDone', () async {
      container = ProviderContainer(
        overrides: [
          llmEngineProvider.overrideWithValue(FakeLlmEngine()),
          modelDownloadServiceProvider.overrideWithValue(
            FakeModelDownloadService(chunkCount: 2, bytesPerChunk: 100),
          ),
          settingsBoxProvider.overrideWithValue(settingsBox),
        ],
      );
      final notifier = container.read(onboardingSetupControllerProvider.notifier);
      await notifier.downloadModels(['tiny']);
      expect(container.read(onboardingSetupControllerProvider), isA<OnboardingSetupDone>());
    });

    // Dart's `Future.wait` defaults to `eagerError: false` - confirmed by
    // this test itself, not merely assumed: even though the LLM engine
    // below throws almost immediately, `downloadModels()`'s internal
    // `await Future.wait([...])` does not settle (and OnboardingSetupState
    // does not become Failed) until the concurrent, still-gated Whisper
    // download also finishes. This is the real, empirically-verified
    // behavior an earlier version of this test file's own doc comments
    // incorrectly assumed was "eager" - corrected here rather than left
    // wrong.
    test(
      'reaches OnboardingSetupFailed only once every concurrent download has settled, never before',
      () async {
        final gatedWhisper = _GatedFakeModelDownloadService();
        container = ProviderContainer(
          overrides: [
            llmEngineProvider.overrideWithValue(
              FakeLlmEngine(errorToThrow: Exception('simulated LLM download failure')),
            ),
            modelDownloadServiceProvider.overrideWithValue(gatedWhisper),
            settingsBoxProvider.overrideWithValue(settingsBox),
          ],
        );
        final notifier = container.read(onboardingSetupControllerProvider.notifier);

        final downloadFuture = notifier.downloadModels(['tiny']);

        // The LLM already threw internally, but the whisper side is still
        // gated - state must NOT be Failed yet.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          container.read(onboardingSetupControllerProvider),
          isA<OnboardingSetupDownloading>(),
          reason: 'Future.wait must not settle while the whisper download is still pending',
        );

        gatedWhisper.releaseGate();
        await downloadFuture;

        final failed = container.read(onboardingSetupControllerProvider);
        expect(failed, isA<OnboardingSetupFailed>());
        // A genuine error (not a stall/cancellation) must never be
        // mislabeled as a resumable pause - see the two dedicated
        // wasPaused=true tests below (R-11 P0 fix).
        expect((failed as OnboardingSetupFailed).wasPaused, isFalse);
      },
    );

    // R-11 P0 fix: real-device report - starting a model download, then
    // backgrounding/locking the phone, previously always looked like a
    // scary generic failure requiring a manual "Retry" (which happened to
    // work anyway, since the underlying `.part` file was always preserved -
    // but nothing told the user that). These two tests cover the exact
    // exception shapes a stall/overall download timeout produces for each
    // download mechanism this app has, and confirm the resulting state
    // says "paused", not "failed".
    test('a stalled LLM download (LlmModelDownloadTimeoutException) reaches '
        'OnboardingSetupFailed with wasPaused=true, not a generic failure', () async {
      container = ProviderContainer(
        overrides: [
          llmEngineProvider.overrideWithValue(
            FakeLlmEngine(
              errorToThrow: LlmModelDownloadTimeoutException(
                'The AI model download stalled or took too long - it will resume rather than start over.',
              ),
            ),
          ),
          modelDownloadServiceProvider.overrideWithValue(
            FakeModelDownloadService(chunkCount: 2, bytesPerChunk: 100),
          ),
          settingsBoxProvider.overrideWithValue(settingsBox),
        ],
      );
      final notifier = container.read(onboardingSetupControllerProvider.notifier);
      await notifier.downloadModels(['tiny']);

      final state = container.read(onboardingSetupControllerProvider);
      expect(state, isA<OnboardingSetupFailed>());
      expect((state as OnboardingSetupFailed).wasPaused, isTrue);
    });

    test('a cooperatively-cancelled Whisper download (ModelDownloadException.wasCancelled) '
        'reaches OnboardingSetupFailed with wasPaused=true', () async {
      container = ProviderContainer(
        overrides: [
          llmEngineProvider.overrideWithValue(FakeLlmEngine()),
          modelDownloadServiceProvider.overrideWithValue(
            FakeModelDownloadService(
              failWith: ModelDownloadException('Download paused.', wasCancelled: true),
            ),
          ),
          settingsBoxProvider.overrideWithValue(settingsBox),
        ],
      );
      final notifier = container.read(onboardingSetupControllerProvider.notifier);
      await notifier.downloadModels(['tiny']);

      final state = container.read(onboardingSetupControllerProvider);
      expect(state, isA<OnboardingSetupFailed>());
      expect((state as OnboardingSetupFailed).wasPaused, isTrue);
    });

    // The real, verified guarantee the generation-guard fix provides:
    // `downloadModels()` has no internal re-entrancy guard, so nothing
    // stops it from being called a second time while a first call is
    // still in flight (e.g. a fast double-tap on "Download & Continue"
    // before the button is rebuilt away, or a caller-side bug). Without
    // the fix, `_sttFractions`/`_llmFraction` are shared instance state,
    // so the *first* call's eventual settlement (its own `Future.wait`,
    // still pending below) would overwrite whatever the *second*,
    // already-finished call left behind. The generation guard
    // (`_isCurrentAttempt`) makes a stale call's late state write a
    // guaranteed no-op once a newer call has started.
    test(
      'a second, overlapping call to downloadModels() is not corrupted by the first call\'s late settlement',
      () async {
        final gatedWhisper = _GatedFakeModelDownloadService();
        container = ProviderContainer(
          overrides: [
            llmEngineProvider.overrideWithValue(
              FakeLlmEngine(errorToThrow: Exception('simulated LLM download failure')),
            ),
            modelDownloadServiceProvider.overrideWithValue(gatedWhisper),
            settingsBoxProvider.overrideWithValue(settingsBox),
          ],
        );
        final notifier = container.read(onboardingSetupControllerProvider.notifier);

        // First call - its whisper download is gated, so its own
        // Future.wait cannot settle yet (still in flight when the second
        // call below starts).
        final firstAttempt = notifier.downloadModels(['tiny']);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Second, overlapping call - fully successful, fast engines -
        // starts and finishes while the first call is still pending.
        container.updateOverrides([
          llmEngineProvider.overrideWithValue(FakeLlmEngine()),
          modelDownloadServiceProvider.overrideWithValue(
            FakeModelDownloadService(chunkCount: 2, bytesPerChunk: 100),
          ),
          settingsBoxProvider.overrideWithValue(settingsBox),
        ]);
        final secondAttempt = notifier.downloadModels(['tiny']);
        await secondAttempt;
        expect(container.read(onboardingSetupControllerProvider), isA<OnboardingSetupDone>());

        // Now let the first (now-stale) call finally settle - its LLM
        // error surfaces only once its own whisper future completes.
        gatedWhisper.releaseGate();
        await firstAttempt;

        // The regression assertion: the first call's late failure must
        // not have overwritten the second call's already-settled Done
        // state.
        expect(container.read(onboardingSetupControllerProvider), isA<OnboardingSetupDone>());
      },
    );
  });
}
