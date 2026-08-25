import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v21 (Productivity Toolkit productization pass, P0-9 - File-Manager
/// Parity): a folder system for organizing Student Toolkit outputs,
/// mirroring v15's `folders`/`documents.folder_id` pattern exactly but as
/// its own, separate table - `toolkit_folders` is deliberately not the same
/// table as `folders` (Documents), even though the shape is identical.
/// Documents (imported source material for RAG/chat) and toolkit files
/// (generated tool outputs) are unrelated content types with no shared
/// lifecycle; sharing one folder table would mean deleting/renaming a
/// folder from either screen silently affects the other, a coupling this
/// pass never audited Documents for. `toolkit_files.folder_id` is one new
/// nullable column, additive `ALTER TABLE ... ADD COLUMN`, same
/// no-real-FK-validated-at-the-repository-layer convention as
/// `documents.folder_id`/`toolkit_files.tool_type`. Every pre-existing
/// toolkit file gets `folder_id = NULL` automatically (the column's
/// default), so every file that existed before this migration keeps
/// showing up under "All Files"/"Recent" exactly as it always did.
Future<void> migrateV20ToV21(Database db) async {
  await db.execute('''
    CREATE TABLE ${ToolkitFoldersTable.name} (
      ${ToolkitFoldersTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${ToolkitFoldersTable.title} TEXT NOT NULL,
      ${ToolkitFoldersTable.createdAt} TEXT NOT NULL,
      ${ToolkitFoldersTable.updatedAt} TEXT NOT NULL
    );
  ''');

  await db.execute('''
    ALTER TABLE ${ToolkitFilesTable.name}
    ADD COLUMN ${ToolkitFilesTable.folderId} INTEGER;
  ''');

  await db.execute(
    'CREATE INDEX idx_toolkit_files_folder_id ON ${ToolkitFilesTable.name} (${ToolkitFilesTable.folderId});',
  );
}
