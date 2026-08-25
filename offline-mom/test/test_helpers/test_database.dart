import 'package:offline_mom/database/migrations/v1.dart';
import 'package:offline_mom/database/migrations/v2.dart';
import 'package:offline_mom/database/migrations/v3.dart';
import 'package:offline_mom/database/migrations/v4.dart';
import 'package:offline_mom/database/migrations/v5.dart';
import 'package:offline_mom/database/migrations/v6.dart';
import 'package:offline_mom/database/migrations/v7.dart';
import 'package:offline_mom/database/migrations/v8.dart';
import 'package:offline_mom/database/migrations/v9.dart';
import 'package:offline_mom/database/migrations/v10.dart';
import 'package:offline_mom/database/migrations/v11.dart';
import 'package:offline_mom/database/migrations/v12.dart';
import 'package:offline_mom/database/migrations/v13.dart';
import 'package:offline_mom/database/migrations/v14.dart';
import 'package:offline_mom/database/migrations/v15.dart';
import 'package:offline_mom/database/migrations/v16.dart';
import 'package:offline_mom/database/migrations/v17.dart';
import 'package:offline_mom/database/migrations/v18.dart';
import 'package:offline_mom/database/migrations/v19.dart';
import 'package:offline_mom/database/migrations/v20.dart';
import 'package:offline_mom/database/migrations/v21.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

/// Opens a fresh in-memory database with every migration applied, for
/// repository/use-case tests that need a real (if throwaway) SQLite
/// database rather than a mock. Mirrors [AppDatabase.open] - kept in sync
/// with it deliberately, since a mismatch here previously let a test suite
/// pass against a schema the real app database no longer builds.
Future<Database> openTestDatabase() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }

  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 21,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
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
    ),
  );
}
