import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/logging/local_crash_logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points `getApplicationDocumentsPath()` at a real, throwaway directory
/// instead of the platform channel `path_provider` normally uses (which
/// doesn't exist under `flutter test`) - mirrors
/// `storage_providers_test.dart`'s own established fake-platform pattern.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._docsPath);

  final String? _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_crash_logger_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('LocalCrashLogger', () {
    test('init() creates logs/crash.log under the app documents directory', () async {
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      await LocalCrashLogger.init();

      expect(LocalCrashLogger.isReady, isTrue);
      expect(LocalCrashLogger.logFilePath, '${tempDir.path}/logs/crash.log');
      expect(await Directory('${tempDir.path}/logs').exists(), isTrue);
    });

    test('record() writes a retrievable entry with timestamp, source, error, and stack trace',
        () async {
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      await LocalCrashLogger.init();

      await LocalCrashLogger.record(
        Exception('boom'),
        StackTrace.fromString('#0 someFunction (file.dart:1:1)'),
        source: 'test-source',
      );

      final entries = await LocalCrashLogger.readEntries();
      expect(entries, hasLength(1));
      expect(entries.single.source, 'test-source');
      expect(entries.single.error, contains('boom'));
      expect(entries.single.stackTrace, contains('someFunction'));
      expect(entries.single.timestamp, isNotNull);
    });

    test('record() appends rather than overwriting previous entries', () async {
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      await LocalCrashLogger.init();

      await LocalCrashLogger.record(Exception('first'), StackTrace.empty, source: 'a');
      await LocalCrashLogger.record(Exception('second'), StackTrace.empty, source: 'b');

      final entries = await LocalCrashLogger.readEntries();
      expect(entries, hasLength(2));
      expect(entries[0].error, contains('first'));
      expect(entries[1].error, contains('second'));
    });

    test('keeps only the most recent 20 entries once more than 20 are recorded', () async {
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      await LocalCrashLogger.init();

      for (var i = 0; i < 25; i++) {
        await LocalCrashLogger.record(Exception('error-$i'), StackTrace.empty, source: 'loop');
      }

      final entries = await LocalCrashLogger.readEntries();
      expect(entries, hasLength(LocalCrashLogger.maxEntries));
      // The oldest 5 (error-0..error-4) should have been trimmed away -
      // the remaining entries should be error-5..error-24, oldest to newest.
      expect(entries.first.error, contains('error-5'));
      expect(entries.last.error, contains('error-24'));
    });

    test('readRaw() returns the full file contents verbatim, one JSON line per entry', () async {
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      await LocalCrashLogger.init();

      await LocalCrashLogger.record(Exception('boom'), StackTrace.empty, source: 'test-source');

      final raw = await LocalCrashLogger.readRaw();
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!.trim()) as Map<String, dynamic>;
      expect(decoded['source'], 'test-source');
      expect(decoded['error'], contains('boom'));
    });

    test('readRaw()/readEntries() return null/empty before anything has been recorded', () async {
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      await LocalCrashLogger.init();

      expect(await LocalCrashLogger.readRaw(), isNull);
      expect(await LocalCrashLogger.readEntries(), isEmpty);
    });

    test('record() never throws even if init() was never called (storage unavailable)', () async {
      PathProviderPlatform.instance = _FakePathProviderPlatform(null);
      await LocalCrashLogger.init();

      expect(LocalCrashLogger.isReady, isFalse);
      // Must complete without throwing - a diagnostics feature that
      // crashes the app it's meant to diagnose would defeat its purpose.
      await LocalCrashLogger.record(Exception('boom'), StackTrace.empty, source: 'test');
      expect(await LocalCrashLogger.readEntries(), isEmpty);
    });
  });
}
