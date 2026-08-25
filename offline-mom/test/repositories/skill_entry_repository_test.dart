import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late SkillEntryRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteSkillEntryRepository(db);
  });

  tearDown(() => db.close());

  SkillEntry buildSkill({String name = 'Flutter', SkillCategory category = SkillCategory.technical}) {
    return SkillEntry(id: null, name: name, category: category, createdAt: DateTime(2026, 1, 1));
  }

  test('insert then getAll returns the same skill, including the name column', () async {
    await repository.insert(buildSkill(name: 'Dart', category: SkillCategory.technical));

    final all = await repository.getAll();

    expect(all, hasLength(1));
    expect(all.single.name, 'Dart');
    expect(all.single.category, SkillCategory.technical);
  });

  test('category round-trips correctly for each value', () async {
    await repository.insert(buildSkill(name: 'Flutter', category: SkillCategory.technical));
    await repository.insert(buildSkill(name: 'Figma', category: SkillCategory.tool));
    await repository.insert(buildSkill(name: 'Communication', category: SkillCategory.soft));

    final all = await repository.getAll();

    expect(
      all.map((s) => s.category).toSet(),
      {SkillCategory.technical, SkillCategory.tool, SkillCategory.soft},
    );
  });

  test('delete removes the skill', () async {
    final id = await repository.insert(buildSkill());
    await repository.delete(id);

    expect(await repository.getAll(), isEmpty);
  });

  test('getAll orders alphabetically, case-insensitively', () async {
    await repository.insert(buildSkill(name: 'zsh'));
    await repository.insert(buildSkill(name: 'Angular'));
    await repository.insert(buildSkill(name: 'bash'));

    final all = await repository.getAll();

    expect(all.map((s) => s.name).toList(), ['Angular', 'bash', 'zsh']);
  });
}
