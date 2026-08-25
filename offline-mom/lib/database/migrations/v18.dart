import 'package:sqflite/sqflite.dart';

/// Schema version 18 (Beta product-validation phase, data-fidelity fix).
///
/// Adds **`custom_section_blocks`** - the new table backing
/// `CustomSectionBlock`, attached to resumes via the existing
/// `resume_blocks` polymorphic join (`block_type = 'customSection'`)
/// exactly like every other block type. This closes the "unknown resume
/// section gets silently discarded on import" gap: `ResumeImportParser`
/// now preserves any recognized-header-but-unmodeled section (Awards,
/// Publications, Volunteer Experience, etc.) as a generic titled section
/// instead of merging its text into whatever section came before it.
///
/// Retry-safe and additive-only, same discipline as v16/v17: `CREATE TABLE
/// IF NOT EXISTS`, whole migration in one transaction.
Future<void> migrateV17ToV18(Database db) async {
  await db.transaction((txn) async {
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS custom_section_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        entries_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  });
}
