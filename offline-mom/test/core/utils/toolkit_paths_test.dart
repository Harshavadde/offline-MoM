import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/utils/toolkit_paths.dart';
import 'package:offline_mom/models/toolkit_file.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('toolkit_paths_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  group('newToolkitTempFilePath', () {
    test('returns distinct paths on successive calls, under toolkit/tmp/', () async {
      final first = await newToolkitTempFilePath('jpg');
      final second = await newToolkitTempFilePath('jpg');

      expect(first, isNot(second));
      expect(first, contains('${Platform.pathSeparator}toolkit${Platform.pathSeparator}tmp${Platform.pathSeparator}'));
      expect(first, endsWith('.jpg'));
    });

    test('the returned path is actually writable', () async {
      final path = await newToolkitTempFilePath('jpg');
      final file = File(path);
      await file.writeAsBytes([1, 2, 3]);

      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), [1, 2, 3]);
    });
  });

  group('clearToolkitTempFiles', () {
    test('deletes every file under toolkit/tmp/ and reports the count', () async {
      final first = await newToolkitTempFilePath('jpg');
      final second = await newToolkitTempFilePath('jpg');
      await File(first).writeAsBytes([1]);
      await File(second).writeAsBytes([1]);

      final deleted = await clearToolkitTempFiles();

      expect(deleted, 2);
      expect(await File(first).exists(), isFalse);
      expect(await File(second).exists(), isFalse);
    });

    test('returns 0 without error when no temp files exist yet', () async {
      expect(await clearToolkitTempFiles(), 0);
    });

    test('does not touch toolkit output files (only the tmp/ subfolder)',
        () async {
      final outputPath = await newToolkitOutputPath(ToolkitToolType.scan, 'pdf');
      await File(outputPath).writeAsBytes([1, 2, 3]);
      final tempPath = await newToolkitTempFilePath('jpg');
      await File(tempPath).writeAsBytes([1]);

      await clearToolkitTempFiles();

      expect(await File(outputPath).exists(), isTrue);
      expect(await File(tempPath).exists(), isFalse);
    });
  });
}
