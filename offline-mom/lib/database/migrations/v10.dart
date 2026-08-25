import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v10: `chat_sessions.is_pinned` (V2 Phase 2B, ADR-028,
/// docs/v2/implementation/03-decisions.md) - backs the "pin conversation"
/// Workspace Chat improvement. Defaults to 0 (unpinned) so every existing
/// conversation on an upgraded install is unaffected.
Future<void> migrateV9ToV10(Database db) async {
  await db.execute(
    'ALTER TABLE ${ChatSessionsTable.name} '
    'ADD COLUMN ${ChatSessionsTable.isPinned} INTEGER NOT NULL DEFAULT 0;',
  );
}
