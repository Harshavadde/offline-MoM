import 'package:sqflite/sqflite.dart';

/// Schema version 19 (Product Validation phase - "My Profile").
///
/// Adds **`resumes.is_profile`** - a single additive `INTEGER NOT NULL
/// DEFAULT 0` column marking the one resume that is the user's "My
/// Profile" (their complete career source of truth), distinct from every
/// job-specific resume. Every existing resume defaults to `0` (not a
/// profile) - this migration never designates one automatically, since
/// doing so would be guessing which of a user's existing resumes (if any)
/// they'd want treated as their profile; the user chooses explicitly via
/// the new "My Profile" entry point.
///
/// Deliberately reuses the existing `resumes` table rather than a new
/// entity (docs/v3/implementation/03-decisions.md) - a profile is
/// structurally just a resume; the flag only changes presentation and
/// gates JD-tailoring mutation.
///
/// Retry-safe: SQLite's `ALTER TABLE ... ADD COLUMN` has no `IF NOT
/// EXISTS` form, so (matching every prior `ADD COLUMN` migration in this
/// project) the transaction wrapper is what keeps a retried migration
/// safe here, not a per-statement guard.
Future<void> migrateV18ToV19(Database db) async {
  await db.transaction((txn) async {
    await txn.execute(
      'ALTER TABLE resumes ADD COLUMN is_profile INTEGER NOT NULL DEFAULT 0;',
    );
  });
}
