import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ExperienceBlockRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteExperienceBlockRepository(db);
  });

  tearDown(() => db.close());

  ExperienceBlock buildBlock({String role = 'Engineer', DateTime? at, List<String> bullets = const []}) {
    final now = at ?? DateTime(2026, 1, 1);
    return ExperienceBlock(
      id: null,
      role: role,
      company: 'Acme Corp',
      startDate: '2022-01',
      bullets: bullets,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same block', () async {
    final id = await repository.insert(buildBlock(role: 'Senior Engineer'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.role, 'Senior Engineer');
    expect(fetched.company, 'Acme Corp');
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('endDate null means Present and round-trips as null', () async {
    final id = await repository.insert(buildBlock());
    final fetched = (await repository.getById(id))!;

    expect(fetched.endDate, isNull);
  });

  test('bullets_json round-trips an ordered list of strings correctly', () async {
    final id = await repository.insert(
      buildBlock(bullets: const ['Shipped the thing', 'Fixed the other thing']),
    );

    final fetched = (await repository.getById(id))!;

    expect(fetched.bullets, ['Shipped the thing', 'Fixed the other thing']);
  });

  test('an empty bullet list round-trips as an empty list, not null', () async {
    final id = await repository.insert(buildBlock(bullets: const []));
    final fetched = (await repository.getById(id))!;

    expect(fetched.bullets, isEmpty);
  });

  test('update edits fields, including bullets', () async {
    final id = await repository.insert(buildBlock(role: 'Old role'));
    final block = (await repository.getById(id))!;

    await repository.update(block.copyWith(role: 'New role', bullets: ['New bullet']));

    final fetched = (await repository.getById(id))!;
    expect(fetched.role, 'New role');
    expect(fetched.bullets, ['New bullet']);
  });

  test('subProjects round-trips - name, bullets, and nesting under the parent entry (migration v20)', () async {
    final id = await repository.insert(buildBlock(bullets: const ['Top-level bullet']).copyWith(
      subProjects: const [
        ExperienceSubProject(name: 'SciLab (Web & Android)', bullets: ['Built SciLab.', 'Shipped it.']),
        ExperienceSubProject(name: 'ByHeart (Web & Android)', bullets: ['Built ByHeart.']),
      ],
    ));

    final fetched = (await repository.getById(id))!;

    expect(fetched.bullets, ['Top-level bullet']);
    expect(fetched.subProjects, hasLength(2));
    expect(fetched.subProjects[0].name, 'SciLab (Web & Android)');
    expect(fetched.subProjects[0].bullets, ['Built SciLab.', 'Shipped it.']);
    expect(fetched.subProjects[1].name, 'ByHeart (Web & Android)');
  });

  test('an empty subProjects list round-trips as an empty list, not null', () async {
    final id = await repository.insert(buildBlock());
    final fetched = (await repository.getById(id))!;

    expect(fetched.subProjects, isEmpty);
  });

  test(
    'updating an entry\'s own fields without touching subProjects preserves them unchanged - the exact '
    'scenario the experience block editor screen must not silently regress on save',
    () async {
      final id = await repository.insert(buildBlock(role: 'Old role').copyWith(
        subProjects: const [ExperienceSubProject(name: 'Crossword App', bullets: ['Built it.'])],
      ));
      final block = (await repository.getById(id))!;

      await repository.update(block.copyWith(role: 'New role'));

      final fetched = (await repository.getById(id))!;
      expect(fetched.role, 'New role');
      expect(fetched.subProjects, hasLength(1));
      expect(fetched.subProjects.single.name, 'Crossword App');
    },
  );

  test('delete removes the block', () async {
    final id = await repository.insert(buildBlock());
    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('getAll returns every block, most recently created first', () async {
    await repository.insert(buildBlock(role: 'Oldest', at: DateTime(2026, 1, 1)));
    await repository.insert(buildBlock(role: 'Newest', at: DateTime(2026, 1, 3)));
    await repository.insert(buildBlock(role: 'Middle', at: DateTime(2026, 1, 2)));

    final all = await repository.getAll();

    expect(all.map((b) => b.role).toList(), ['Newest', 'Middle', 'Oldest']);
  });
}
