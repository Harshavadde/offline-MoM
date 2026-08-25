import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/database/app_database.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points `getApplicationDocumentsPath()` at a real, throwaway directory
/// instead of the platform channel `path_provider` normally uses (which
/// doesn't exist under `flutter test`) - mirrors this project's own
/// established fake-platform pattern (`storage_providers_test.dart`,
/// `local_crash_logger_test.dart`).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._docsPath);

  final String _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  group('migrateLegacyDatabaseFileIfNeeded (pure file logic)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app_database_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('copies the legacy file to the new path when the new path has no file yet', () async {
      final legacyPath = '${tempDir.path}/legacy/offline_mom.db';
      final newPath = '${tempDir.path}/new/offline_mom.db';
      await File(legacyPath).create(recursive: true);
      await File(legacyPath).writeAsString('legacy database bytes');

      await migrateLegacyDatabaseFileIfNeeded(legacyPath: legacyPath, newPath: newPath);

      expect(await File(newPath).exists(), isTrue);
      expect(await File(newPath).readAsString(), 'legacy database bytes');
    });

    test('does nothing when no legacy file exists', () async {
      final legacyPath = '${tempDir.path}/legacy/offline_mom.db';
      final newPath = '${tempDir.path}/new/offline_mom.db';

      await migrateLegacyDatabaseFileIfNeeded(legacyPath: legacyPath, newPath: newPath);

      expect(await File(newPath).exists(), isFalse);
    });

    test('never overwrites an existing file at the new path', () async {
      final legacyPath = '${tempDir.path}/legacy/offline_mom.db';
      final newPath = '${tempDir.path}/new/offline_mom.db';
      await File(legacyPath).create(recursive: true);
      await File(legacyPath).writeAsString('legacy bytes');
      await File(newPath).create(recursive: true);
      await File(newPath).writeAsString('already-real bytes - must not be clobbered');

      await migrateLegacyDatabaseFileIfNeeded(legacyPath: legacyPath, newPath: newPath);

      expect(await File(newPath).readAsString(), 'already-real bytes - must not be clobbered');
    });

    test('is a no-op when legacyPath is null', () async {
      final newPath = '${tempDir.path}/new/offline_mom.db';

      await migrateLegacyDatabaseFileIfNeeded(legacyPath: null, newPath: newPath);

      expect(await File(newPath).exists(), isFalse);
    });

    test('is a no-op when legacyPath and newPath are the same', () async {
      final path = '${tempDir.path}/offline_mom.db';
      await File(path).create(recursive: true);
      await File(path).writeAsString('original bytes');

      // Should return immediately without attempting to copy a file onto
      // itself (which would otherwise be at best a wasted no-op, at worst
      // an error depending on the platform's copy() semantics).
      await migrateLegacyDatabaseFileIfNeeded(legacyPath: path, newPath: path);

      expect(await File(path).readAsString(), 'original bytes');
    });
  });

  group('AppDatabase.open() against a real (FFI-backed) SQLite database', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app_database_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test(
        'creates a working database whose FTS5 virtual table actually works - '
        'regression test for the real-device "no such module: fts5" crash '
        '(Product Validation Phase)', () async {
      final appDb = await AppDatabase.open();
      addTearDown(appDb.close);

      // The exact statement from the crash log: content_fts is an FTS5
      // virtual table, created during migrateV3ToV4 as part of onCreate
      // above. If FTS5 weren't available, AppDatabase.open() itself would
      // already have thrown before reaching this line.
      await appDb.db.insert('content_fts', {
        'content_type': 'meeting',
        'meeting_id': 1,
        'source_id': 1,
        'title': 'Quarterly budget review',
        'body': 'We discussed the quarterly budget in detail.',
      });

      final matches = await appDb.db.rawQuery(
        "SELECT title FROM content_fts WHERE content_fts MATCH 'budget'",
      );

      expect(matches, hasLength(1));
      expect(matches.single['title'], 'Quarterly budget review');
    });

    test('opening the database twice in the same process does not throw (FFI re-init is idempotent)',
        () async {
      final first = await AppDatabase.open();
      await first.close();

      final second = await AppDatabase.open();
      addTearDown(second.close);

      expect(second.db.isOpen, isTrue);
    });
  });
}
