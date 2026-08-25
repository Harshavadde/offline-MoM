import 'package:sqflite/sqflite.dart';

/// Schema version 22 (AI-tailored resume from Job Description feature).
///
/// Adds **`project_blocks.status`** - a single additive, nullable `TEXT`
/// column storing `ProjectBlockStatus.name` ("planned" or "completed").
/// This is the structural enforcement point for that feature's core "no
/// fabrication" requirement: an AI-suggested project idea must never be
/// silently promoted into a resume as completed work. Wording alone (the
/// bullets a user types) is not a real guardrail - it can be freely
/// re-edited. This column is instead set explicitly by which of the two
/// review-screen actions the user actually pressed ("Add as Planned
/// Project" vs. "I've Actually Completed This"), independent of whatever
/// text ends up in the project's own bullets.
///
/// Nullable, not `NOT NULL DEFAULT`: every pre-existing `ProjectBlock` row,
/// and every project added through the normal (unmodified) Project Block
/// Editor, has no opinion on planned-vs-completed - `status == null` means
/// exactly that, not "predates this feature" vs. "genuinely unspecified"
/// (the distinction is moot; both read back the same way via
/// `ProjectBlock.fromMap`), matching `Resume.isProfile`'s and
/// `ExperienceBlock.subProjects`'s own precedent for absent-column handling.
///
/// Retry-safe: SQLite's `ALTER TABLE ... ADD COLUMN` has no `IF NOT EXISTS`
/// form, so (matching every prior `ADD COLUMN` migration in this project)
/// the transaction wrapper is what keeps a retried migration safe here, not
/// a per-statement guard.
Future<void> migrateV21ToV22(Database db) async {
  await db.transaction((txn) async {
    await txn.execute(
      'ALTER TABLE project_blocks ADD COLUMN status TEXT;',
    );
  });
}
