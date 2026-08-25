import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:offline_mom/features/ai_models/presentation/providers/installed_models_providers.dart';
import 'package:offline_mom/features/ai_models/presentation/providers/model_download_providers.dart';
import 'package:offline_mom/models/installed_model.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/services/ai/model_catalog.dart';
import 'package:offline_mom/services/ai/model_download_service.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

/// `FlutterTesseractOcr.getTessdataPath()` resolves via
/// `getApplicationDocumentsDirectory()` - the one path-provider call OCR
/// downloads need faked that Whisper's own equivalent test
/// (`model_download_controller_test.dart`) doesn't, since Whisper resolves
/// through `getApplicationSupportDirectory()`/`getLibraryDirectory()`
/// instead (`ai_model_paths.dart`).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
  @override
  Future<String?> getApplicationSupportPath() async => _path;
  @override
  Future<String?> getLibraryPath() async => _path;
}

void main() {
  late Database db;
  late Directory modelDir;
  late Directory hiveDir;
  late Box settingsBox;
  late ProviderContainer container;
  late FakeModelDownloadService fakeService;

  const ocrEnglish = ModelCatalog.ocrEnglish;

  setUp(() async {
    db = await openTestDatabase();
    modelDir = await Directory.systemTemp.createTemp('ocr_model_download_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(modelDir.path);
    fakeService = FakeModelDownloadService(chunkCount: 2, bytesPerChunk: 1000);

    hiveDir = await Directory.systemTemp.createTemp('ocr_model_download_test_hive_');
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

  test('starting the OCR English download reuses ModelDownloadService and records an InstalledModel (scenario 13 - resolves "model missing")', () async {
    final controller = container.read(modelDownloadControllerProvider.notifier);
    expect(controller.stateFor(ocrEnglish.id), isA<ModelDownloadIdle>());

    await controller.start(ocrEnglish);

    expect(controller.stateFor(ocrEnglish.id), isA<ModelDownloadDone>());
    final installed = await container.read(installedModelRepositoryProvider).getByModelId(ocrEnglish.id);
    expect(installed, isNotNull);
    expect(installed!.kind, ModelKind.ocr);
    expect(installed.isActive, isTrue, reason: 'the first model installed for a kind auto-activates');

    // The file really landed where FlutterTesseractOcr.getTessdataPath()
    // (appDocuments/tessdata) will look for it.
    expect(installed.localPath.replaceAll('\\', '/'), endsWith('/tessdata/eng.traineddata'));
    expect(await File(installed.localPath).exists(), isTrue);
  });

  test('a corrupted OCR model file fails verification (scenario 14)', () async {
    final controller = container.read(modelDownloadControllerProvider.notifier);
    await controller.start(ocrEnglish);
    final installed = await container.read(installedModelRepositoryProvider).getByModelId(ocrEnglish.id);

    // Corrupt the file on disk after a clean install.
    await File(installed!.localPath).writeAsString('corrupted-not-the-original-bytes');

    final ok = await controller.verify(ocrEnglish, installed);
    expect(ok, isFalse);
    expect(controller.stateFor(ocrEnglish.id), isA<ModelDownloadFailed>());
  });

  test('an interrupted OCR download leaves a resumable partial, not a restart-from-zero (scenario 15/16)', () async {
    final failing = FakeModelDownloadService(
      chunkCount: 1,
      bytesPerChunk: 1000,
      failWith: ModelDownloadException('connection dropped', wasCancelled: true),
    );
    container.dispose();
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        modelDownloadServiceProvider.overrideWithValue(failing),
        settingsBoxProvider.overrideWithValue(settingsBox),
      ],
    );
    final controller = container.read(modelDownloadControllerProvider.notifier);

    await controller.start(ocrEnglish);
    expect(controller.stateFor(ocrEnglish.id), isA<ModelDownloadPaused>());
    expect(
      await container.read(installedModelRepositoryProvider).getByModelId(ocrEnglish.id),
      isNull,
      reason: 'an interrupted download must never be recorded as installed',
    );

    // Resuming reuses the exact same ModelDownloadService.download() call -
    // FakeModelDownloadService (real HttpModelDownloadService equivalent)
    // tracks its own partial-file bookkeeping via hasPartialDownload/
    // deletePartialDownload; the resumability contract itself (never
    // restart from 0 on a genuine resume) is exercised end-to-end by
    // `model_download_service_test.dart`'s own real-file Range/ETag tests -
    // this test's job is only to confirm the OCR kind reaches the same
    // resumable-paused state Whisper already does, not to re-prove the
    // resume mechanism itself.
    final resumed = FakeModelDownloadService(chunkCount: 2, bytesPerChunk: 1000);
    container.dispose();
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        modelDownloadServiceProvider.overrideWithValue(resumed),
        settingsBoxProvider.overrideWithValue(settingsBox),
      ],
    );
    final controller2 = container.read(modelDownloadControllerProvider.notifier);
    await controller2.start(ocrEnglish);
    expect(controller2.stateFor(ocrEnglish.id), isA<ModelDownloadDone>());
  });

  test('multiple OCR models installed can be switched between via setActive (scenario 17/18)', () async {
    // Only English ships in the real catalog today (see ModelCatalog's own
    // doc comment - other languages could not be independently verified to
    // exist this session), but the switching mechanism itself is kind-
    // generic (InstalledModelRepository.setActive/getActiveForKind), so
    // this proves it works correctly for ModelKind.ocr with two installed
    // rows, using a second synthetic modelId rather than a second
    // fabricated catalog entry.
    final repo = container.read(installedModelRepositoryProvider);
    await repo.insert(InstalledModel(
      modelId: 'ocr-eng',
      kind: ModelKind.ocr,
      localPath: '/fake/eng.traineddata',
      sizeBytes: 4000000,
      downloadedAt: DateTime.now(),
      isActive: true,
    ));
    await repo.insert(InstalledModel(
      modelId: 'ocr-test-second-language',
      kind: ModelKind.ocr,
      localPath: '/fake/second.traineddata',
      sizeBytes: 5000000,
      downloadedAt: DateTime.now(),
      isActive: false,
    ));

    expect((await repo.getActiveForKind(ModelKind.ocr))!.modelId, 'ocr-eng');

    await repo.setActive(ModelKind.ocr, 'ocr-test-second-language');

    final active = await repo.getActiveForKind(ModelKind.ocr);
    expect(active!.modelId, 'ocr-test-second-language');
    final rows = await repo.getByKind(ModelKind.ocr);
    expect(rows.where((r) => r.isActive), hasLength(1), reason: 'at most one active row per kind');
  });

  test('activating an installed OCR model persists AppSettings.activeOcrModelId', () async {
    // Installed directly (not via FakeModelDownloadService, whose
    // deliberately-fake sha256 would never match `verify()`'s real
    // recomputed hash of the file it actually wrote) - a real file with a
    // real matching size and no stored hash, so `activate()`'s "verify
    // before switching" gate (ADR-036) passes on the size check alone,
    // exactly like a genuinely-installed model with no hash on record.
    final destinationDir = Directory('${modelDir.path}/tessdata')..createSync(recursive: true);
    final file = File('${destinationDir.path}/eng.traineddata')..writeAsStringSync('real-enough-bytes');
    final repo = container.read(installedModelRepositoryProvider);
    await repo.insert(InstalledModel(
      modelId: ocrEnglish.id,
      kind: ModelKind.ocr,
      localPath: file.path,
      sizeBytes: await file.length(),
      downloadedAt: DateTime.now(),
      isActive: false,
    ));

    final installedController = container.read(installedModelsControllerProvider.notifier);
    final ok = await installedController.activate(ModelKind.ocr, ocrEnglish.id);
    expect(ok, isTrue);

    final settings = container.read(settingsControllerProvider);
    expect(settings.activeOcrModelId, ocrEnglish.id);
  });

  test('deleting an installed OCR model removes its file from disk', () async {
    final controller = container.read(modelDownloadControllerProvider.notifier);
    await controller.start(ocrEnglish);
    final installed = await container.read(installedModelRepositoryProvider).getByModelId(ocrEnglish.id);

    await container.read(installedModelsControllerProvider.notifier).delete(installed!);

    expect(await File(installed.localPath).exists(), isFalse);
    expect(await container.read(installedModelRepositoryProvider).getByModelId(ocrEnglish.id), isNull);
  });
}
