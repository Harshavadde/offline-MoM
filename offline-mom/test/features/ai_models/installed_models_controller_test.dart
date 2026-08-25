import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:offline_mom/features/ai_models/presentation/providers/installed_models_providers.dart';
import 'package:offline_mom/models/installed_model.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late Directory hiveDir;
  late Box settingsBox;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    hiveDir = await Directory.systemTemp.createTemp('installed_models_controller_test_hive_');
    Hive.init(hiveDir.path);
    settingsBox = await Hive.openBox('settings_box_test');
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        settingsBoxProvider.overrideWithValue(settingsBox),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await settingsBox.deleteFromDisk();
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  test('activate(llm) deactivates other llm rows and persists the choice into AppSettings', () async {
    final repo = container.read(installedModelRepositoryProvider);
    await repo.insert(
      InstalledModel(
        modelId: 'llm-a',
        kind: ModelKind.llm,
        localPath: 'hf://a',
        sizeBytes: 1,
        downloadedAt: DateTime(2026, 1, 1),
        isActive: true,
      ),
    );
    await repo.insert(
      InstalledModel(
        modelId: 'llm-b',
        kind: ModelKind.llm,
        localPath: 'hf://b',
        sizeBytes: 1,
        downloadedAt: DateTime(2026, 1, 2),
        isActive: false,
      ),
    );

    final controller = container.read(installedModelsControllerProvider.notifier);
    await controller.activate(ModelKind.llm, 'llm-b');

    expect((await repo.getActiveForKind(ModelKind.llm))!.modelId, 'llm-b');
    expect(container.read(settingsControllerProvider).activeLlmModelId, 'llm-b');
  });

  test('activate(speechToText) writes the whisper.cpp enum name, not the catalog id, into whisperModelName', () async {
    // Reliability-overhaul pass (Phase 14/17): activate() now verifies a
    // speech-to-text model's on-disk file (exists, correct size) before
    // switching to it - a real file is required here for that check to
    // pass, unlike before this pass, when a bare DB row was enough.
    final tempDir = await Directory.systemTemp.createTemp('installed_models_controller_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final file = File('${tempDir.path}/ggml-large-v1.bin');
    await file.writeAsBytes([1, 2, 3]);

    final repo = container.read(installedModelRepositoryProvider);
    await repo.insert(
      InstalledModel(
        modelId: 'whisper-large-v1',
        kind: ModelKind.speechToText,
        localPath: file.path,
        sizeBytes: 3,
        downloadedAt: DateTime(2026, 1, 1),
        isActive: false,
      ),
    );

    final controller = container.read(installedModelsControllerProvider.notifier);
    final activated = await controller.activate(ModelKind.speechToText, 'whisper-large-v1');

    expect(activated, isTrue);
    // WhisperModel.largeV1.name == 'largeV1' - the Dart enum identifier,
    // not the hyphenated 'large-v1' the catalog id/download URL use.
    expect(container.read(settingsControllerProvider).whisperModelName, 'largeV1');
  });

  test(
    'activate(speechToText) refuses to switch (returns false) when the on-disk file is missing',
    () async {
      // Regression test for the reliability-overhaul pass's own fix
      // (Phase 14/17): a DB row whose file has since been deleted
      // outside the app must never quietly become the active model.
      final repo = container.read(installedModelRepositoryProvider);
      await repo.insert(
        InstalledModel(
          modelId: 'whisper-large-v1',
          kind: ModelKind.speechToText,
          localPath: '/does/not/exist/ggml-large-v1.bin',
          sizeBytes: 3,
          downloadedAt: DateTime(2026, 1, 1),
          isActive: false,
        ),
      );

      final controller = container.read(installedModelsControllerProvider.notifier);
      final activated = await controller.activate(ModelKind.speechToText, 'whisper-large-v1');

      expect(activated, isFalse);
      expect(await repo.getActiveForKind(ModelKind.speechToText), isNull);
      expect(container.read(settingsControllerProvider).whisperModelName, isNot('largeV1'));
    },
  );

  test('delete removes the row and the on-disk file for speech-to-text models', () async {
    final tempDir = await Directory.systemTemp.createTemp('installed_models_controller_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final file = File('${tempDir.path}/ggml-tiny.bin');
    await file.writeAsBytes([1, 2, 3]);

    final repo = container.read(installedModelRepositoryProvider);
    final id = await repo.insert(
      InstalledModel(
        modelId: 'whisper-tiny',
        kind: ModelKind.speechToText,
        localPath: file.path,
        sizeBytes: 3,
        downloadedAt: DateTime(2026, 1, 1),
        isActive: false,
      ),
    );
    final installed = (await repo.getById(id))!;

    final controller = container.read(installedModelsControllerProvider.notifier);
    await controller.delete(installed);

    expect(await file.exists(), isFalse);
    expect(await repo.getById(id), isNull);
  });

  test(
    'Part E (multi-model management, product-quality remediation pass): the active model '
    'survives an app restart - a fresh ProviderContainer/AsyncNotifier reading the SAME '
    'persisted Hive settings box and SQLite database (not the same in-memory instance this test '
    'already ran activate() against) still reports the correct active model, since it was '
    'genuinely written to disk, not just held in memory',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('installed_models_controller_test_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final file = File('${tempDir.path}/ggml-tiny.bin');
      await file.writeAsBytes([1, 2, 3]);

      final repo = container.read(installedModelRepositoryProvider);
      await repo.insert(
        InstalledModel(
          modelId: 'whisper-tiny',
          kind: ModelKind.speechToText,
          localPath: file.path,
          sizeBytes: 3,
          downloadedAt: DateTime(2026, 1, 1),
          isActive: false,
        ),
      );
      final activated =
          await container.read(installedModelsControllerProvider.notifier).activate(ModelKind.speechToText, 'whisper-tiny');
      expect(activated, isTrue);

      // "Restart" - dispose this container (mirrors the app process
      // ending) and build a genuinely new one, reopening the SAME Hive
      // box file and reusing the SAME sqflite database connection (the
      // real-world equivalent: the same on-disk database file) rather
      // than carrying over any in-memory state from the container above.
      container.dispose();
      final restartedContainer = ProviderContainer(
        overrides: [
          installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
          settingsBoxProvider.overrideWithValue(settingsBox),
        ],
      );
      addTearDown(restartedContainer.dispose);

      expect(restartedContainer.read(settingsControllerProvider).whisperModelName, 'tiny');
      final reloaded = await restartedContainer.read(installedModelsControllerProvider.future);
      expect(reloaded.singleWhere((m) => m.modelId == 'whisper-tiny').isActive, isTrue);
    },
  );

  test('refresh() reloads the list after an external repository change', () async {
    final repo = container.read(installedModelRepositoryProvider);
    await container.read(installedModelsControllerProvider.future);
    expect(container.read(installedModelsControllerProvider).valueOrNull, isEmpty);

    await repo.insert(
      InstalledModel(
        modelId: 'whisper-tiny',
        kind: ModelKind.speechToText,
        localPath: '/data/x',
        sizeBytes: 1,
        downloadedAt: DateTime(2026, 1, 1),
        isActive: false,
      ),
    );
    await container.read(installedModelsControllerProvider.notifier).refresh();

    expect(container.read(installedModelsControllerProvider).valueOrNull, hasLength(1));
  });
}
