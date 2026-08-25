import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:offline_mom/features/ai_models/presentation/providers/model_download_providers.dart';
import 'package:offline_mom/models/ai_model_spec.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/services/ai/model_catalog.dart';
import 'package:offline_mom/services/ai/model_download_service.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

/// [whisperModelDirectory] resolves via `getApplicationSupportDirectory()`
/// on Android or `getLibraryDirectory()` elsewhere - `flutter test` always
/// runs on the host (never Android), so only `getLibraryPath` needs
/// faking here (mirrors `storage_providers_test.dart`'s identical pattern
/// for `getTemporaryPath`).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getLibraryPath() async => _path;
  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

/// A [ModelDownloadService] that emits exactly one progress event, then
/// waits for the test to explicitly [releaseGate] before checking
/// [ModelDownloadCancelToken.isCancelled] - giving the "pause happens
/// after the first progress event, before the download would otherwise
/// continue" test a real happens-before relationship instead of a
/// [Future.delayed]-based race against [FakeModelDownloadService]'s own
/// fixed chunk loop.
class _GatedFakeModelDownloadService implements ModelDownloadService {
  final _firstProgress = Completer<void>();
  final _gate = Completer<void>();

  Future<void> get firstProgressEmitted => _firstProgress.future;
  void releaseGate() => _gate.complete();

  @override
  Future<bool> hasPartialDownload(File destination) async => true;

  @override
  Future<void> deletePartialDownload(File destination) async {}

  @override
  Future<ModelDownloadOutcome> download({
    required String url,
    required File destination,
    required ModelDownloadCancelToken cancelToken,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(const ModelDownloadProgress(receivedBytes: 1000, totalBytes: 5000));
    _firstProgress.complete();
    await _gate.future;
    if (cancelToken.isCancelled) {
      throw ModelDownloadException('Download paused.', wasCancelled: true);
    }
    return const ModelDownloadOutcome(sizeBytes: 5000, sha256Hex: 'unused');
  }
}

/// Routes each `download()` call to the [ModelDownloadService] registered
/// for that call's own `url` - lets a test give two concurrently-running
/// downloads (different [AiModelSpec]s, same shared
/// [modelDownloadServiceProvider] override the controller reads through)
/// fully independent, individually-controllable fakes, since Riverpod only
/// lets one service instance be registered for the whole provider.
class _DispatchingModelDownloadService implements ModelDownloadService {
  _DispatchingModelDownloadService(this._byUrl);
  final Map<String, ModelDownloadService> _byUrl;

  ModelDownloadService _forUrl(String url) => _byUrl[url] ?? (throw StateError('no fake registered for $url'));

  @override
  Future<bool> hasPartialDownload(File destination) => _byUrl.values.first.hasPartialDownload(destination);

  @override
  Future<void> deletePartialDownload(File destination) => _byUrl.values.first.deletePartialDownload(destination);

  @override
  Future<ModelDownloadOutcome> download({
    required String url,
    required File destination,
    required ModelDownloadCancelToken cancelToken,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) {
    return _forUrl(url).download(
      url: url,
      destination: destination,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }
}

void main() {
  late Database db;
  late Directory modelDir;
  late Directory hiveDir;
  late Box settingsBox;
  late ProviderContainer container;
  late FakeModelDownloadService fakeService;

  const whisperSmall = ModelCatalog.whisperSmall;

  setUp(() async {
    db = await openTestDatabase();
    modelDir = await Directory.systemTemp.createTemp('model_download_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(modelDir.path);
    fakeService = FakeModelDownloadService(chunkCount: 2, bytesPerChunk: 1000);

    // Beta blocker fix (model download resumability) added a
    // `settingsControllerProvider.allowBackgroundDownloads` read to
    // `_startWhisperDownload`/`_startLlamaDownload` - needs the same
    // `settingsBoxProvider` override `installed_models_controller_test.dart`
    // already establishes for the same reason.
    hiveDir = await Directory.systemTemp.createTemp('model_download_controller_test_hive_');
    Hive.init(hiveDir.path);
    settingsBox = await Hive.openBox('settings_box_test');

    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        modelDownloadServiceProvider.overrideWithValue(fakeService),
        settingsBoxProvider.overrideWithValue(settingsBox),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
    await settingsBox.deleteFromDisk();
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  test('starting a Whisper download moves idle -> in progress -> done, and records an InstalledModel', () async {
    final controller = container.read(modelDownloadControllerProvider.notifier);
    expect(controller.stateFor(whisperSmall.id), isA<ModelDownloadIdle>());

    await controller.start(whisperSmall);

    expect(controller.stateFor(whisperSmall.id), isA<ModelDownloadDone>());
    final installed = await container.read(installedModelRepositoryProvider).getByModelId(whisperSmall.id);
    expect(installed, isNotNull);
    expect(installed!.sizeBytes, 2000);
    expect(installed.isActive, isTrue, reason: 'the first model installed for a kind auto-activates');
  });

  test('a second start() call while one is already in flight is a no-op (no duplicate downloads)', () async {
    final controller = container.read(modelDownloadControllerProvider.notifier);

    final first = controller.start(whisperSmall);
    // The state is already in-progress synchronously after the first
    // `start()` call's initial `_setState` - a second call must bail out
    // before doing any further work.
    await controller.start(whisperSmall);
    await first;

    final rows = await container.read(installedModelRepositoryProvider).getAll();
    expect(rows, hasLength(1), reason: 'only one InstalledModel row should ever be written');
  });

  test('pausing a download surfaces ModelDownloadPaused and leaves a resumable partial', () async {
    // A dedicated, deterministic fake (not `FakeModelDownloadService`'s
    // fixed-chunk-count loop, whose timing relative to a real-world
    // `Future.delayed(Duration.zero)` in this test isn't reliably
    // interleave-able): it emits exactly one progress event, then waits on
    // a `Completer` this test controls before checking cancellation - so
    // "pause after the first progress event" is a real happens-before
    // relationship, not a race.
    final pausing = _GatedFakeModelDownloadService();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        modelDownloadServiceProvider.overrideWithValue(pausing),
        settingsBoxProvider.overrideWithValue(settingsBox),
      ],
    );
    final controller = container.read(modelDownloadControllerProvider.notifier);

    final future = controller.start(whisperSmall);
    await pausing.firstProgressEmitted;
    controller.pause(whisperSmall.id);
    pausing.releaseGate();
    await future;

    expect(controller.stateFor(whisperSmall.id), isA<ModelDownloadPaused>());
    expect(await container.read(installedModelRepositoryProvider).getByModelId(whisperSmall.id), isNull);
  });

  test('a failed download surfaces ModelDownloadFailed with a message, not a crash', () async {
    final failing = FakeModelDownloadService(failWith: ModelDownloadException('network unreachable'));
    container.dispose();
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        modelDownloadServiceProvider.overrideWithValue(failing),
        settingsBoxProvider.overrideWithValue(settingsBox),
      ],
    );
    final controller = container.read(modelDownloadControllerProvider.notifier);

    await controller.start(whisperSmall);

    final state = controller.stateFor(whisperSmall.id);
    expect(state, isA<ModelDownloadFailed>());
    expect((state as ModelDownloadFailed).message, contains('network unreachable'));
  });

  test(
    'Part E (multi-model management, product-quality remediation pass): two different models '
    'downloading at the same time track fully independent state - keyed by model id in a Map, '
    'not a single shared field - so one finishing, failing, or pausing never touches the '
    "other's progress or InstalledModel row",
    () async {
      final controller = container.read(modelDownloadControllerProvider.notifier);
      const whisperTiny = ModelCatalog.whisperTiny;

      expect(controller.stateFor(whisperSmall.id), isA<ModelDownloadIdle>());
      expect(controller.stateFor(whisperTiny.id), isA<ModelDownloadIdle>());

      // Genuinely concurrent, not sequential - both in flight at once,
      // exercising the same Map<String, ModelDownloadState> the real UI
      // reads when a user starts a second model's download without
      // waiting for the first to finish.
      await Future.wait([controller.start(whisperSmall), controller.start(whisperTiny)]);

      expect(controller.stateFor(whisperSmall.id), isA<ModelDownloadDone>());
      expect(controller.stateFor(whisperTiny.id), isA<ModelDownloadDone>());

      final repo = container.read(installedModelRepositoryProvider);
      final installedSmall = await repo.getByModelId(whisperSmall.id);
      final installedTiny = await repo.getByModelId(whisperTiny.id);
      expect(installedSmall, isNotNull);
      expect(installedTiny, isNotNull);
      // Each row reflects its own model's own downloaded size, not a
      // value leaked from the other concurrent download.
      expect(installedSmall!.sizeBytes, 2000);
      expect(installedTiny!.sizeBytes, 2000);
      expect(installedSmall.modelId, whisperSmall.id);
      expect(installedTiny.modelId, whisperTiny.id);
    },
  );

  test(
    'Part E: pausing one of two concurrently-downloading models leaves the other completely '
    'unaffected - it keeps progressing and finishes normally',
    () async {
      final tinyGate = _GatedFakeModelDownloadService();
      final smallGate = _GatedFakeModelDownloadService();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
          modelDownloadServiceProvider.overrideWithValue(_DispatchingModelDownloadService({
            whisperSmall.downloadSource: smallGate,
            ModelCatalog.whisperTiny.downloadSource: tinyGate,
          })),
          settingsBoxProvider.overrideWithValue(settingsBox),
        ],
      );
      final controller = container.read(modelDownloadControllerProvider.notifier);
      const whisperTiny = ModelCatalog.whisperTiny;

      final smallFuture = controller.start(whisperSmall);
      final tinyFuture = controller.start(whisperTiny);
      await smallGate.firstProgressEmitted;
      await tinyGate.firstProgressEmitted;

      controller.pause(whisperSmall.id);
      smallGate.releaseGate();
      await smallFuture;

      expect(controller.stateFor(whisperSmall.id), isA<ModelDownloadPaused>());
      // whisperTiny was never paused and is still awaiting its own gate -
      // releasing it now must let it complete normally, proving the
      // sibling's pause had zero effect on it.
      expect(controller.stateFor(whisperTiny.id), isA<ModelDownloadInProgress>());
      tinyGate.releaseGate();
      await tinyFuture;
      expect(controller.stateFor(whisperTiny.id), isA<ModelDownloadDone>());
    },
  );

  test(
    'a vision/translation spec is rejected with a clear "not available yet" message '
    '(P0-7: ocr moved out of this still-unimplemented group - see ocr_model_download_test.dart '
    'for its own real, no-longer-rejected download path)',
    () async {
      final controller = container.read(modelDownloadControllerProvider.notifier);
      const fakeVisionSpec = AiModelSpec(
        id: 'vision-placeholder',
        kind: ModelKind.vision,
        displayName: 'Future Vision model',
        description: 'not a real catalog entry, for testing the future-kind guard only',
        downloadSource: 'https://example.invalid/vision.bin',
        sizeBytesApprox: 1,
        ramRequirementMb: 1,
        speedTier: ModelSpeedTier.fast,
        recommendedDeviceTier: RecommendedDeviceTier.anyModernPhone,
        capabilities: [],
        license: 'n/a',
        version: 'n/a',
      );

      await controller.start(fakeVisionSpec);

      final state = controller.stateFor(fakeVisionSpec.id);
      expect(state, isA<ModelDownloadFailed>());
      expect((state as ModelDownloadFailed).message, contains('not available'));
    },
  );
}
