import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/resume.dart';

/// Contract for reading/writing [Resume] identity rows - mirrors
/// [DocumentRepository]'s exact shape (lib/repositories/document_repository.dart).
abstract class ResumeRepository {
  /// Create a new Resume identity (Profile fields + title).
  Future<int> insert(Resume resume);

  /// Edit Profile fields / title.
  Future<void> update(Resume resume);

  /// Removes the Resume - cascades its `resume_blocks` and
  /// `resume_versions` rows (application-level, orchestrated by
  /// `DeleteResumeUseCase`, not this repository).
  Future<void> delete(int id);

  /// Full Resume row, for the Editor.
  Future<Resume?> getById(int id);

  /// Every Resume, most recently updated first - for the list screen.
  Future<List<Resume>> getAll();

  /// The single resume with `is_profile = 1`, or `null` if the user
  /// hasn't set one up yet - "My Profile" (Product Validation phase).
  Future<Resume?> getProfile();

  /// Designates [id] as "My Profile", atomically unsetting any previous
  /// profile first - enforces the "at most one profile at a time"
  /// invariant, the same pattern `InstalledModelRepository.setActive`
  /// already uses for its own "one active model per kind" rule. Throws if
  /// no resume with [id] exists.
  Future<void> setAsProfile(int id);
}

class SqfliteResumeRepository implements ResumeRepository {
  SqfliteResumeRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Resume resume) {
    final map = resume.toMap()..remove(ResumesTable.id);
    return _db.insert(ResumesTable.name, map);
  }

  @override
  Future<void> update(Resume resume) async {
    await _db.update(
      ResumesTable.name,
      resume.toMap(),
      where: '${ResumesTable.id} = ?',
      whereArgs: [resume.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      ResumesTable.name,
      where: '${ResumesTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Resume?> getById(int id) async {
    final rows = await _db.query(
      ResumesTable.name,
      where: '${ResumesTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Resume.fromMap(rows.first);
  }

  @override
  Future<List<Resume>> getAll() async {
    final rows = await _db.query(
      ResumesTable.name,
      orderBy: '${ResumesTable.updatedAt} DESC',
    );
    return rows.map(Resume.fromMap).toList();
  }

  @override
  Future<Resume?> getProfile() async {
    final rows = await _db.query(
      ResumesTable.name,
      where: '${ResumesTable.isProfile} = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Resume.fromMap(rows.first);
  }

  @override
  Future<void> setAsProfile(int id) async {
    await _db.transaction((txn) async {
      await txn.update(ResumesTable.name, {ResumesTable.isProfile: 0});
      final updated = await txn.update(
        ResumesTable.name,
        {ResumesTable.isProfile: 1},
        where: '${ResumesTable.id} = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        throw StateError('Cannot set resume $id as profile - it does not exist.');
      }
    });
  }
}
