import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v11: `toolkit_files` (V2 Phase 5A, Student Toolkit) - backs the Recent
/// Files list for image compression/resize outputs. No foreign keys (a
/// toolkit output isn't owned by any meeting/document) and no FTS5 entry
/// (toolkit outputs aren't part of the workspace's searchable knowledge -
/// see `ContentFtsTable`'s own doc comment).
Future<void> migrateV10ToV11(Database db) async {
  await db.execute('''
    CREATE TABLE ${ToolkitFilesTable.name} (
      ${ToolkitFilesTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${ToolkitFilesTable.toolType} TEXT NOT NULL,
      ${ToolkitFilesTable.title} TEXT NOT NULL,
      ${ToolkitFilesTable.outputPath} TEXT NOT NULL,
      ${ToolkitFilesTable.fileSizeBytes} INTEGER NOT NULL,
      ${ToolkitFilesTable.originalFileSizeBytes} INTEGER,
      ${ToolkitFilesTable.isFavorite} INTEGER NOT NULL DEFAULT 0,
      ${ToolkitFilesTable.createdAt} TEXT NOT NULL,
      ${ToolkitFilesTable.updatedAt} TEXT NOT NULL
    );
  ''');
}
