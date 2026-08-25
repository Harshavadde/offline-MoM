import 'package:sqflite/sqflite.dart';

/// Schema version 16 (V3 Milestone 1, Resume Foundation).
///
/// Additive migration: creates the eight tables and two indexes the
/// block-based resume builder needs - `resumes`, its four library block
/// tables (`experience_blocks`, `education_blocks`, `project_blocks`,
/// `certification_blocks`), the flat `skill_entries` library, the live
/// composition join `resume_blocks`, and the frozen-snapshot
/// `resume_versions`. Nothing existing is read, written, or altered. All
/// eight tables ship together - they're interdependent (a Resume Editor is
/// not meaningfully testable with only half of them), unlike a future
/// milestone's tables, which land in their own later migrations exactly
/// when that milestone needs them.
///
/// Retry-safe, safe after partial failure: every `CREATE TABLE`/
/// `CREATE INDEX` is `IF NOT EXISTS`, and the whole migration runs inside
/// one transaction. `sqflite`'s schema version only advances once
/// `onUpgrade` completes without throwing, so an interruption partway
/// through - a bug, a full disk, a killed process, doesn't matter which -
/// would otherwise leave the version unbumped and cause every subsequent
/// launch to retry the identical migration, failing immediately on
/// whichever tables already got created. The transaction means a failure
/// partway through rolls back cleanly to nothing (SQLite's `DDL` is
/// transactional), and the `IF NOT EXISTS` guards mean that even a retry
/// landing after a non-transactional partial state (e.g. an interrupted
/// transaction on platforms with weaker guarantees) still completes
/// without error - belt and suspenders, so a retried migration always
/// finishes instead of boot-looping the app for an existing user,
/// including ones who never touch the Resume feature at all.
///
/// `resume_blocks.resume_id`/`block_id` and `resume_versions.resume_id` are
/// ordinary integer columns, not declared `FOREIGN KEY`s - the same choice
/// this schema already made for `documents.folder_id` (v15) and, more
/// directly, for `knowledge_chunks.content_type` + `source_id`'s
/// polymorphic relation (v8): `block_type` + `block_id` cannot be a real FK
/// across five possible parent tables, so the reference is validated at the
/// application layer instead (`DeleteLibraryBlockUseCase`), matching where
/// that validation already lives for `knowledge_chunks`.
Future<void> migrateV15ToV16(Database db) async {
  await db.transaction((txn) async {
    // --- Resume tables --------------------------------------------------
    // The Resume identity itself - Profile fields inline, 1:1, rather than
    // a separate table (a small, fixed shape with no reason to split out).
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS resumes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        target_role TEXT,
        full_name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        location TEXT,
        links_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    // --- Library block tables --------------------------------------------
    // App-scoped, not resume-scoped: a resume only ever holds a reference
    // into these via resume_blocks, never a copy, so editing a block here
    // updates every resume that references it.
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS experience_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        company TEXT NOT NULL,
        location TEXT,
        start_date TEXT NOT NULL,
        end_date TEXT,
        bullets_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS education_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        institution TEXT NOT NULL,
        degree TEXT NOT NULL,
        field_of_study TEXT,
        start_date TEXT NOT NULL,
        end_date TEXT,
        details_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS project_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        link TEXT,
        bullets_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS certification_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        issuer TEXT NOT NULL,
        issued_date TEXT,
        credential_url TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS skill_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    // --- Join tables -------------------------------------------------
    // A resume's live, editable composition - which library blocks it
    // currently includes, in what order, with what per-resume overrides.
    // Polymorphic (block_type + block_id): the same "cannot be a real FK
    // across multiple possible parent tables" shape knowledge_chunks
    // already has for content_type + source_id.
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS resume_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resume_id INTEGER NOT NULL,
        block_type TEXT NOT NULL,
        block_id INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        override_json TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    // --- Version tables ----------------------------------------------
    // Immutable, frozen snapshots - never edited once created, only
    // created, listed, renamed (metadata only), or deleted.
    // compiled_snapshot is what guarantees this: once written, it is
    // never re-derived from the live block library, so a later edit or
    // deletion of a source block can never retroactively change what a
    // version means.
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS resume_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resume_id INTEGER NOT NULL,
        version_label TEXT NOT NULL,
        compiled_snapshot TEXT NOT NULL,
        exported_pdf_path TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    // --- Indexes -------------------------------------------------------

    // Supports ResumeBlockRepository.getForResume(resumeId) - the Editor's
    // single most frequent query, run on every screen load and after
    // every add/remove/reorder.
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_resume_blocks_resume_id ON resume_blocks (resume_id);',
    );

    // Supports ResumeVersionRepository.getForResume(resumeId) - the
    // Versions screen's listing query, and the version lookup
    // DeleteResumeUseCase/deleteAllForResume runs before cascading a
    // Resume delete.
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_resume_versions_resume_id ON resume_versions (resume_id);',
    );
  });
}
