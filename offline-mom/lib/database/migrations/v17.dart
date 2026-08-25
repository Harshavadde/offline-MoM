import 'package:sqflite/sqflite.dart';

/// Schema version 17 (V3 Milestone 0, Data Model & Device Foundation).
///
/// Additive migration, closing gaps the V3 discovery/PRD passes found in
/// the Milestone 1 (v16) schema rather than reopening it:
///
/// 1. **`suggested_edits`** - the new table backing `SuggestedEdit`
///    (docs/v3/01-prd.md §21/§22.3), the first-class "AI proposes, user
///    decides" state machine the whole tailoring pipeline (Milestone 3)
///    depends on. Not populated by anything in this milestone - only its
///    schema and repository land here, ahead of any code that writes to
///    it, matching v16's own precedent of shipping a table before the
///    feature that fills it (`resume_versions` shipped a full milestone
///    before `SaveResumeVersionUseCase` existed).
/// 2. **`resumes.achievements_json`** / **`resumes.template_id`** - two new
///    nullable columns. `achievements_json` is a deliberately lightweight
///    JSON-encoded string list (mirrors `resumes.links_json`'s existing
///    convention) rather than a new block-library table + repository - a
///    resume's achievements are short, non-relational bullets with no
///    reuse-across-resumes need the way experience/education/etc. blocks
///    have (docs/v3/01-prd.md §7). `template_id` records which template
///    rendered a resume's *current* draft - purely descriptive metadata
///    the Milestone 1 template engine will read/write; nothing in this
///    milestone assigns it a value.
/// 3. **`resume_versions.template_id`** / **`.tailored_for_jd_title`** /
///    **`.tailored_for_jd_company`** - three new nullable columns letting a
///    frozen version record which template rendered it and, optionally,
///    which JD it was tailored for. Deliberately *labels* only, never the
///    full JD text - JD content stays session-only per the PRD's offline/
///    privacy requirements (§14); persisting a title/company pair is not
///    "a JD library," it is version metadata.
///
/// Retry-safe, same discipline v16 established: the new table uses
/// `CREATE TABLE IF NOT EXISTS`, and the whole migration runs inside one
/// transaction so a partial failure rolls back to nothing rather than
/// leaving some but not all of these additive changes applied. Unlike
/// `CREATE TABLE`, SQLite's `ALTER TABLE ... ADD COLUMN` has no
/// `IF NOT EXISTS` form in the SQLite version this project's other
/// `ADD COLUMN` migrations (v15's `documents.folder_id`) were already
/// written against, so this migration follows that same precedent exactly
/// rather than introducing a new idiom - the transaction wrapper is what
/// keeps a retried migration safe here, not a per-statement guard.
Future<void> migrateV16ToV17(Database db) async {
  await db.transaction((txn) async {
    // --- Suggested edits ---------------------------------------------
    // target_block_type/target_block_id are nullable together (a
    // profile-level suggestion, e.g. a rewritten summary, has neither) -
    // the same polymorphic-reference shape resume_blocks already uses,
    // just optional here since not every suggestion targets a block.
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS suggested_edits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resume_id INTEGER NOT NULL,
        target_block_type TEXT,
        target_block_id INTEGER,
        field_name TEXT NOT NULL,
        original_value TEXT NOT NULL,
        suggested_value TEXT NOT NULL,
        source_requirement TEXT,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      );
    ''');

    // Supports SuggestedEditRepository.getForResume(resumeId) - the
    // Suggestion Review screen's (Milestone 3) single listing query.
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_suggested_edits_resume_id '
      'ON suggested_edits (resume_id);',
    );

    // --- Additive columns on existing v16 tables -----------------------
    await txn.execute('ALTER TABLE resumes ADD COLUMN achievements_json TEXT;');
    await txn.execute('ALTER TABLE resumes ADD COLUMN template_id TEXT;');

    await txn.execute(
      'ALTER TABLE resume_versions ADD COLUMN template_id TEXT;',
    );
    await txn.execute(
      'ALTER TABLE resume_versions ADD COLUMN tailored_for_jd_title TEXT;',
    );
    await txn.execute(
      'ALTER TABLE resume_versions ADD COLUMN tailored_for_jd_company TEXT;',
    );
  });
}
