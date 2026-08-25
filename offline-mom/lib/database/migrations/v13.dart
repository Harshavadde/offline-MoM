import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v13 (V2 Phase 6A, AI Model Manager): a new, standalone
/// `installed_models` table - see [InstalledModelsTable]'s doc comment for
/// why this is a real table rather than reusing `AppSettings`' Hive-backed
/// single-row shape (a growable, queryable list of install records is
/// exactly the shape `AppSettings`' own doc comment says Hive is a poor
/// fit for). No existing table is touched by this migration.
Future<void> migrateV12ToV13(Database db) async {
  await db.execute('''
    CREATE TABLE ${InstalledModelsTable.name} (
      ${InstalledModelsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${InstalledModelsTable.modelId} TEXT NOT NULL,
      ${InstalledModelsTable.kind} TEXT NOT NULL,
      ${InstalledModelsTable.localPath} TEXT NOT NULL,
      ${InstalledModelsTable.sizeBytes} INTEGER NOT NULL,
      ${InstalledModelsTable.downloadedAt} TEXT NOT NULL,
      ${InstalledModelsTable.localSha256} TEXT,
      ${InstalledModelsTable.isActive} INTEGER NOT NULL DEFAULT 0
    );
  ''');

  await db.execute('''
    CREATE INDEX idx_installed_models_kind
    ON ${InstalledModelsTable.name} (${InstalledModelsTable.kind});
  ''');
}
