import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/resume_version.dart';

/// Contract for reading/writing immutable, frozen [ResumeVersion] snapshots
/// - never edited once created, only created, listed, renamed (metadata
/// only), or deleted. Mirrors the append-only spirit of
/// [ChatMessageRepository] - messages aren't edited in place either, a
/// correction produces a new message.
abstract class ResumeVersionRepository {
  /// Persist a newly-compiled, frozen snapshot.
  Future<int> insert(ResumeVersion version);

  /// The one permitted metadata edit - never touches `compiledSnapshot`.
  Future<void> renameLabel(int id, String newLabel);

  /// Records where a version's exported PDF landed, once the export
  /// itself has already succeeded - `SaveResumeVersionUseCase` calls this
  /// only after `ResumePdfExportService.exportToFile` returns a final
  /// path, never before. The version row itself is written by [insert]
  /// with `exportedPdfPath` left null; a failed export simply never calls
  /// this, leaving that null rather than being rolled back.
  Future<void> setExportedPdfPath(int id, String path);

  /// Remove one version's row and its exported PDF file, if any.
  Future<void> delete(int id);

  /// Remove every version belonging to one Resume - deletes each version's
  /// exported file, then its row, internally. This is the method
  /// `DeleteResumeUseCase` calls; it never issues a bulk delete against
  /// `resume_versions` directly, which would silently skip file cleanup.
  Future<void> deleteAllForResume(int resumeId);

  /// For the Preview screen.
  Future<ResumeVersion?> getById(int id);

  /// Every version of one Resume, most recent first.
  Future<List<ResumeVersion>> getForResume(int resumeId);
}

class SqfliteResumeVersionRepository implements ResumeVersionRepository {
  SqfliteResumeVersionRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(ResumeVersion version) {
    final map = version.toMap()..remove(ResumeVersionsTable.id);
    return _db.insert(ResumeVersionsTable.name, map);
  }

  @override
  Future<void> renameLabel(int id, String newLabel) async {
    await _db.update(
      ResumeVersionsTable.name,
      {ResumeVersionsTable.versionLabel: newLabel},
      where: '${ResumeVersionsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> setExportedPdfPath(int id, String path) async {
    await _db.update(
      ResumeVersionsTable.name,
      {ResumeVersionsTable.exportedPdfPath: path},
      where: '${ResumeVersionsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> delete(int id) async {
    final version = await getById(id);
    if (version == null) return;

    await _deleteExportedFileIfAny(version);

    await _db.delete(
      ResumeVersionsTable.name,
      where: '${ResumeVersionsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteAllForResume(int resumeId) async {
    // Deletes each version through delete(), one at a time - never a bulk
    // `DELETE FROM resume_versions WHERE resume_id = ?`, which would
    // remove every row in one statement but skip the file cleanup step
    // entirely. Reusing delete() is what guarantees that can't happen,
    // rather than duplicating the file-cleanup logic here and risking the
    // two copies drifting apart.
    final versions = await getForResume(resumeId);
    for (final version in versions) {
      await delete(version.id!);
    }
  }

  Future<void> _deleteExportedFileIfAny(ResumeVersion version) async {
    final path = version.exportedPdfPath;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<ResumeVersion?> getById(int id) async {
    final rows = await _db.query(
      ResumeVersionsTable.name,
      where: '${ResumeVersionsTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ResumeVersion.fromMap(rows.first);
  }

  @override
  Future<List<ResumeVersion>> getForResume(int resumeId) async {
    final rows = await _db.query(
      ResumeVersionsTable.name,
      where: '${ResumeVersionsTable.resumeId} = ?',
      whereArgs: [resumeId],
      orderBy: '${ResumeVersionsTable.createdAt} DESC',
    );
    return rows.map(ResumeVersion.fromMap).toList();
  }
}
