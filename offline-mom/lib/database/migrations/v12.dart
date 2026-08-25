import 'package:sqflite/sqflite.dart';

import '../tables.dart';

/// v12: `toolkit_files.page_count` (V2 Phase 5B, Scanner + PDF Tools) - the
/// only new field the five new [ToolkitToolType] values (scan, pdfCompress,
/// pdfMerge, pdfSplit, pdfOrganize) need beyond what migration v11 already
/// provides. Nullable and additive, matching migration v11's own reasoning:
/// `fileSizeBytes`/`originalFileSizeBytes` already covers "before/after
/// size" for every tool type, `title`/`outputPath`/`isFavorite`/timestamps
/// are already tool-agnostic - the one genuinely new piece of information a
/// scan or PDF output can show that an image compress/resize result never
/// had is "how many pages," so this is the only column added rather than a
/// speculative generic metadata blob for fields nothing yet needs.
Future<void> migrateV11ToV12(Database db) async {
  await db.execute('''
    ALTER TABLE ${ToolkitFilesTable.name}
    ADD COLUMN ${ToolkitFilesTable.pageCount} INTEGER;
  ''');
}
