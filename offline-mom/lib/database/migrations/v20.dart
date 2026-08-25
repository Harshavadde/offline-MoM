import 'package:sqflite/sqflite.dart';

/// Schema version 20 (reliability-overhaul pass, real-device finding: the
/// user's real resume nests distinct sub-projects - "SciLab", "ByHeart",
/// "Crossword" - under one Experience entry, each with its own bullets.
/// The parser previously had nowhere structural to put this, so every
/// sub-project's name and bullets flattened into the parent entry's own
/// `bullets` list, indistinguishable from the entry's own accomplishments).
///
/// Adds **`experience_blocks.sub_projects_json`** - a single additive,
/// nullable `TEXT` column, JSON-encoded as
/// `[{"name": "...", "bullets": ["...", ...]}, ...]`. Deliberately reuses
/// the existing `experience_blocks` table rather than a new child table -
/// a sub-project has no independent lifecycle of its own (it cannot exist
/// without its parent Experience entry, is never referenced from anywhere
/// else, and never needs its own `id`), so a JSON column mirrors exactly
/// how `bullets_json` on this same table already represents an ordered,
/// entry-owned list with no separate identity - not a new join table for
/// what is really one more field on the existing entity
/// (docs/v3/implementation/03-decisions.md's "do not create duplicate
/// data models unnecessarily" convention).
///
/// Nullable (not `NOT NULL DEFAULT '[]'`) so `ExperienceBlock.fromMap` can
/// tell "this row predates the column, treat as empty" apart from "this
/// row explicitly has zero sub-projects" the exact same way - both decode
/// to an empty list either way, so the distinction is moot in practice,
/// but nullable is the simpler, more standard SQLite `ADD COLUMN` shape
/// and avoids re-encoding every existing row.
///
/// Retry-safe: SQLite's `ALTER TABLE ... ADD COLUMN` has no `IF NOT
/// EXISTS` form, so (matching every prior `ADD COLUMN` migration in this
/// project) the transaction wrapper is what keeps a retried migration
/// safe here, not a per-statement guard.
Future<void> migrateV19ToV20(Database db) async {
  await db.transaction((txn) async {
    await txn.execute(
      'ALTER TABLE experience_blocks ADD COLUMN sub_projects_json TEXT;',
    );
  });
}
