import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/constants/app_constants.dart';
import 'migrations/v1.dart';
import 'migrations/v2.dart';
import 'migrations/v3.dart';
import 'migrations/v4.dart';
import 'migrations/v5.dart';
import 'migrations/v6.dart';
import 'migrations/v7.dart';
import 'migrations/v8.dart';
import 'migrations/v9.dart';
import 'migrations/v10.dart';
import 'migrations/v11.dart';
import 'migrations/v12.dart';
import 'migrations/v13.dart';
import 'migrations/v14.dart';
import 'migrations/v15.dart';
import 'migrations/v16.dart';
import 'migrations/v17.dart';
import 'migrations/v18.dart';
import 'migrations/v19.dart';
import 'migrations/v20.dart';
import 'migrations/v21.dart';

/// If a database file exists at [legacyPath] but not yet at [newPath],
/// copies it across - a device that already has a database from before
/// this app switched its `databaseFactory` (see [AppDatabase.open]'s doc
/// comment) keeps its data instead of appearing to have a fresh, empty
/// database once paths are resolved differently. A no-op in every other
/// case (no legacy file, or a file already at the new path - never
/// overwrites). Extracted as its own top-level function (no `Database`/
/// `databaseFactory` dependency) so this file-level behavior is directly
/// unit-testable without needing a real/fake SQLite factory at all.
Future<void> migrateLegacyDatabaseFileIfNeeded({
  required String? legacyPath,
  required String newPath,
}) async {
  if (legacyPath == null || legacyPath == newPath) return;
  final legacyFile = File(legacyPath);
  final newFile = File(newPath);
  if (await legacyFile.exists() && !await newFile.exists()) {
    await newFile.parent.create(recursive: true);
    await legacyFile.copy(newPath);
  }
}

/// Owns the single sqflite [Database] connection for the app.
///
/// Repositories depend on this (via Riverpod, see `providers/app_providers.dart`)
/// instead of opening the database themselves, so there is exactly one
/// connection and one place that knows about file paths and migrations.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// Guards [sqfliteFfiInit]/the [databaseFactory] assignment below so a
  /// second call to [open] within the same process (there is no legitimate
  /// one today, but tests/hot-restart scenarios shouldn't re-init) doesn't
  /// re-register the FFI factory redundantly.
  static bool _ffiInitialized = false;

  Database get db => _db;

  static Future<AppDatabase> open() async {
    // Product Validation Phase (real-device crash): sqflite's *default*
    // Android backend talks to `android.database.sqlite.SQLiteDatabase` -
    // the OS/framework's own bundled SQLite - and that build is not
    // guaranteed to have the FTS5 extension compiled in (confirmed the
    // real cause of `no such module: fts5` on a real device; not an ABI,
    // R8/ProGuard, or Gradle-packaging issue - see the accompanying report
    // for the full investigation). `sqflite_common_ffi` + `sqlite3_flutter_libs`
    // (already used by every test in this project via
    // `test/test_helpers/test_database.dart`) instead bundles this app's
    // *own* statically-configured SQLite build (FTS5 compiled in) and
    // talks to it directly via Dart FFI, bypassing the OS's SQLite
    // entirely. This changes nothing about the SQL, schema, migrations, or
    // the `Database`/`Batch` API every repository already uses - only
    // which SQLite binary actually executes it.
    //
    // Capture sqflite's *original* default database path before switching
    // `databaseFactory` below - needed only so a device that already has a
    // database from before this fix (the platform-channel backend's
    // `getDatabasesPath()`, Android's `Context.getDatabasePath()`
    // directory) doesn't appear to "lose" it once the FFI backend resolves
    // paths differently. In practice no real device has ever completed
    // `onCreate` (the crash above happens *during* it, on every attempt
    // regardless of build type), so there is nothing to migrate today -
    // this is forward-looking safety, not a workaround for known data.
    String? legacyDbPath;
    try {
      legacyDbPath = p.join(await getDatabasesPath(), AppConstants.sqliteDbName);
    } catch (_) {
      legacyDbPath = null;
    }

    if (!_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }

    // `databaseFactoryFfi`'s own default `getDatabasesPath()` resolves to
    // a `.dart_tool/...` path relative to the working directory - fine for
    // desktop tooling, meaningless on a real device. Resolve this app's
    // actual private storage directory instead (`path_provider`, already
    // used elsewhere in this app for the same reason).
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, AppConstants.sqliteDbName);

    await migrateLegacyDatabaseFileIfNeeded(legacyPath: legacyDbPath, newPath: dbPath);

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: AppConstants.sqliteDbVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          // A brand-new install gets every migration applied in order, so it
          // ends up on the same final schema an upgraded install would reach.
          await createV1Schema(db);
          await migrateV1ToV2(db);
          await migrateV2ToV3(db);
          await migrateV3ToV4(db);
          await migrateV4ToV5(db);
          await migrateV5ToV6(db);
          await migrateV6ToV7(db);
          await migrateV7ToV8(db);
          await migrateV8ToV9(db);
          await migrateV9ToV10(db);
          await migrateV10ToV11(db);
          await migrateV11ToV12(db);
          await migrateV12ToV13(db);
          await migrateV13ToV14(db);
          await migrateV14ToV15(db);
          await migrateV15ToV16(db);
          await migrateV16ToV17(db);
          await migrateV17ToV18(db);
          await migrateV18ToV19(db);
          await migrateV19ToV20(db);
          await migrateV20ToV21(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await migrateV1ToV2(db);
          if (oldVersion < 3) await migrateV2ToV3(db);
          if (oldVersion < 4) await migrateV3ToV4(db);
          if (oldVersion < 5) await migrateV4ToV5(db);
          if (oldVersion < 6) await migrateV5ToV6(db);
          if (oldVersion < 7) await migrateV6ToV7(db);
          if (oldVersion < 8) await migrateV7ToV8(db);
          if (oldVersion < 9) await migrateV8ToV9(db);
          if (oldVersion < 10) await migrateV9ToV10(db);
          if (oldVersion < 11) await migrateV10ToV11(db);
          if (oldVersion < 12) await migrateV11ToV12(db);
          if (oldVersion < 13) await migrateV12ToV13(db);
          if (oldVersion < 14) await migrateV13ToV14(db);
          if (oldVersion < 15) await migrateV14ToV15(db);
          if (oldVersion < 16) await migrateV15ToV16(db);
          if (oldVersion < 17) await migrateV16ToV17(db);
          if (oldVersion < 18) await migrateV17ToV18(db);
          if (oldVersion < 19) await migrateV18ToV19(db);
          if (oldVersion < 20) await migrateV19ToV20(db);
          if (oldVersion < 21) await migrateV20ToV21(db);
        },
      ),
    );

    return AppDatabase._(db);
  }

  Future<void> close() => _db.close();
}
