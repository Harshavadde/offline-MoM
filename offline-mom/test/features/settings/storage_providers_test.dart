import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/settings/presentation/providers/storage_providers.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points `getTemporaryDirectory()` at a real, throwaway directory instead
/// of the platform channel `path_provider` normally uses (which doesn't
/// exist under `flutter test`) - mirrors `test/widget_test.dart`'s own
/// "swap the platform dependency for something real-but-local" precedent
/// for Hive/sqflite, applied here to `path_provider` specifically.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._tempPath);

  final String _tempPath;

  @override
  Future<String?> getTemporaryPath() async => _tempPath;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_providers_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('deletes leftover .wav transcode files', () async {
    final wavFile = File('${tempDir.path}/some_transcode.wav');
    await wavFile.writeAsBytes([1, 2, 3]);

    final deleted = await clearTempTranscodeCache();

    expect(deleted, 1);
    expect(await wavFile.exists(), isFalse);
  });

  test(
      'deletes leftover offline_mom_backup_*.db files (Phase 4B) - the '
      'safety net for BackupScreen._exportBackup failing to clean up its '
      'own temp copy (e.g. the app being killed mid-share)', () async {
    final backupFile = File('${tempDir.path}/offline_mom_backup_1234567890.db');
    await backupFile.writeAsBytes([1, 2, 3]);

    final deleted = await clearTempTranscodeCache();

    expect(deleted, 1);
    expect(await backupFile.exists(), isFalse);
  });

  test('deletes both leftover categories together in one pass', () async {
    final wavFile = File('${tempDir.path}/leftover.wav');
    final backupFile = File('${tempDir.path}/offline_mom_backup_1.db');
    await wavFile.writeAsBytes([1]);
    await backupFile.writeAsBytes([1]);

    final deleted = await clearTempTranscodeCache();

    expect(deleted, 2);
    expect(await wavFile.exists(), isFalse);
    expect(await backupFile.exists(), isFalse);
  });

  test('never touches files it does not own - a database file with a '
      'different name, or an unrelated temp file', () async {
    final liveDbCopy = File('${tempDir.path}/some_other_thing.db');
    final randomFile = File('${tempDir.path}/random.tmp');
    await liveDbCopy.writeAsBytes([1]);
    await randomFile.writeAsBytes([1]);

    final deleted = await clearTempTranscodeCache();

    expect(deleted, 0);
    expect(await liveDbCopy.exists(), isTrue);
    expect(await randomFile.exists(), isTrue);
  });

  test('an empty temp directory deletes nothing and does not throw', () async {
    final deleted = await clearTempTranscodeCache();
    expect(deleted, 0);
  });

  group('StorageInfo.totalBytes', () {
    test('includes documents alongside recordings/toolkit/database (Phase '
        '7B, item 7: documents/ was previously never counted at all - R-30, '
        'docs/v2/implementation/04-risk-register.md)', () {
      const info = StorageInfo(
        recordingsBytes: 100,
        recordingsCount: 1,
        toolkitBytes: 200,
        toolkitCount: 1,
        documentsBytes: 300,
        documentsCount: 2,
        databaseBytes: 400,
      );

      expect(info.totalBytes, 1000);
    });

    test('zero documents contributes nothing (documents/ absent or empty)', () {
      const info = StorageInfo(
        recordingsBytes: 100,
        recordingsCount: 1,
        toolkitBytes: 200,
        toolkitCount: 1,
        documentsBytes: 0,
        documentsCount: 0,
        databaseBytes: 400,
      );

      expect(info.totalBytes, 700);
    });
  });
}
