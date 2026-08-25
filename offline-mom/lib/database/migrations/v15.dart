import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v15 (V2.2 Production Hardening, Priority 2): a lightweight folder
/// system for organizing documents - `folders` (a new, standalone table,
/// no relation to anything else) plus `documents.folder_id` (one new
/// nullable column, additive `ALTER TABLE ... ADD COLUMN`, matching every
/// other single-column addition in this schema's history, e.g. v10's
/// `chat_sessions.is_pinned`). No existing table's data is touched or
/// migrated - every pre-existing document gets `folder_id = NULL`
/// automatically (the column's default), meaning every document that
/// existed before this migration keeps showing up under "All Documents"
/// (the folder-less default view) exactly as it always did. No index on
/// `folders` beyond its own primary key (a folder is always listed in
/// full - there is no folder-owned child table to look up by folder id
/// the way, say, `knowledge_chunks` is looked up by `meeting_id`), but
/// `documents.folder_id` gets one, since filtering the document list by
/// folder is this feature's whole point.
Future<void> migrateV14ToV15(Database db) async {
  await db.execute('''
    CREATE TABLE ${FoldersTable.name} (
      ${FoldersTable.id} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${FoldersTable.title} TEXT NOT NULL,
      ${FoldersTable.createdAt} TEXT NOT NULL,
      ${FoldersTable.updatedAt} TEXT NOT NULL
    );
  ''');

  await db.execute('''
    ALTER TABLE ${DocumentsTable.name}
    ADD COLUMN ${DocumentsTable.folderId} INTEGER;
  ''');

  await db.execute(
    'CREATE INDEX idx_documents_folder_id ON ${DocumentsTable.name} (${DocumentsTable.folderId});',
  );
}
