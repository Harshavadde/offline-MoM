import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/skill_entry.dart';

/// Contract for reading/writing the flat, categorized [SkillEntry] library -
/// attached to resumes the same way experience blocks are (via
/// [ResumeBlockRepository] with `blockType = skill`).
abstract class SkillEntryRepository {
  /// Add a new skill to the library (typically inline, via
  /// `showTextInputDialog`, from the Editor).
  Future<int> insert(SkillEntry entry);

  /// Remove a skill from the library. Assumes the caller has already
  /// confirmed the skill is unreferenced - performs no reference check
  /// itself.
  Future<void> delete(int id);

  /// Every skill, optionally grouped by category client-side.
  Future<List<SkillEntry>> getAll();
}

class SqfliteSkillEntryRepository implements SkillEntryRepository {
  SqfliteSkillEntryRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(SkillEntry entry) {
    final map = entry.toMap()..remove(SkillEntriesTable.id);
    return _db.insert(SkillEntriesTable.name, map);
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      SkillEntriesTable.name,
      where: '${SkillEntriesTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<SkillEntry>> getAll() async {
    final rows = await _db.query(
      SkillEntriesTable.name,
      orderBy: '${SkillEntriesTable.skillName} COLLATE NOCASE ASC',
    );
    return rows.map(SkillEntry.fromMap).toList();
  }
}
