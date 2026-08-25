import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/audio/audio_import_service.dart';
import 'package:offline_mom/services/audio/file_picker_audio_import_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points `getApplicationDocumentsPath()` at a real, throwaway directory -
/// mirrors this project's own established fake-platform pattern
/// (`storage_providers_test.dart`, `app_database_test.dart`), needed here
/// because `newAudioFilePath()` resolves the destination via `path_provider`.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._docsPath);

  final String _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  group('FilePickerAudioImportService.prepareAudioFile', () {
    late Directory tempDir;
    late FilePickerAudioImportService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_import_service_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      service = FilePickerAudioImportService();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('copies a real audio file into app storage and returns the new path', () async {
      final source = File('${tempDir.path}/picked.mp3');
      await source.writeAsBytes([1, 2, 3]);

      final resultPath = await service.prepareAudioFile(source.path);

      expect(await File(resultPath).exists(), isTrue);
      expect(await File(resultPath).readAsBytes(), [1, 2, 3]);
    });

    test(
        'a copy failure (e.g. the picked file vanishing/a disk error) throws '
        'AudioImportException instead of a raw, uncaught FileSystemException - '
        'real-device QA finding: this was previously unguarded, unlike the '
        'equivalent document-import path, leaving the Import screen stuck on '
        'its spinner forever since ImportController only catches '
        'AudioImportException', () async {
      // A source path that never existed reproduces the same
      // FileSystemException class of failure a full-disk copy would -
      // deterministic and portable, without needing to actually fill a disk.
      final missingSource = '${tempDir.path}/never_existed.mp3';

      await expectLater(
        service.prepareAudioFile(missingSource),
        throwsA(isA<AudioImportException>()),
      );
    });

    test('an unsupported file extension throws AudioImportException', () async {
      final source = File('${tempDir.path}/picked.xyz');
      await source.writeAsBytes([1]);

      await expectLater(
        service.prepareAudioFile(source.path),
        throwsA(isA<AudioImportException>()),
      );
    });
  });
}
