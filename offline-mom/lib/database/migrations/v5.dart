import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v5: the `documents` table (V2 Phase 1A, docs/v2/12-database-design.md).
///
/// Deliberately not yet linked into the FTS5 index or the shared
/// `summaries` table here - both require rebuilding existing tables
/// (`content_fts`, `summaries`), which migration v6 does as one atomic
/// step immediately after, once `documents` actually exists for those
/// rebuilt objects to reference. No index on any column here: unlike the
/// meeting-owned child tables, nothing queries `documents` by a foreign
/// key (a document doesn't belong to a meeting) - `id` (the primary key,
/// already indexed implicitly) is the only lookup this table needs.
Future<void> migrateV4ToV5(Database db) async {
  await db.execute('''
    CREATE TABLE ${DocumentsTable.name} (
      ${DocumentsTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${DocumentsTable.title} TEXT NOT NULL,
      ${DocumentsTable.originalFilename} TEXT NOT NULL,
      ${DocumentsTable.sourceType} TEXT NOT NULL,
      ${DocumentsTable.mimeType} TEXT NOT NULL,
      ${DocumentsTable.fileSizeBytes} INTEGER NOT NULL,
      ${DocumentsTable.filePath} TEXT NOT NULL,
      ${DocumentsTable.status} TEXT NOT NULL,
      ${DocumentsTable.extractedText} TEXT,
      ${DocumentsTable.errorMessage} TEXT,
      ${DocumentsTable.createdAt} TEXT NOT NULL,
      ${DocumentsTable.updatedAt} TEXT NOT NULL
    );
  ''');
}
