import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/project_block.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ProjectBlockRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteProjectBlockRepository(db);
  });

  tearDown(() => db.close());

  ProjectBlock buildBlock({String name = 'Side Project', DateTime? at, List<String> bullets = const []}) {
    final now = at ?? DateTime(2026, 1, 1);
    return ProjectBlock(
      id: null,
      name: name,
      link: 'https://github.com/example/project',
      bullets: bullets,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same block, including the name column', () async {
    final id = await repository.insert(buildBlock(name: 'Resume Builder'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.name, 'Resume Builder');
    expect(fetched.link, 'https://github.com/example/project');
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('link is nullable and round-trips as null when never set', () async {
    final now = DateTime(2026, 1, 1);
    final id = await repository.insert(
      ProjectBlock(id: null, name: 'No link project', createdAt: now, updatedAt: now),
    );

    expect((await repository.getById(id))!.link, isNull);
  });

  test('bullets_json round-trips correctly', () async {
    final id = await repository.insert(buildBlock(bullets: const ['Built X', 'Deployed Y']));
    final fetched = (await repository.getById(id))!;

    expect(fetched.bullets, ['Built X', 'Deployed Y']);
  });

  test('update edits fields', () async {
    final id = await repository.insert(buildBlock(name: 'Old name'));
    final block = (await repository.getById(id))!;

    await repository.update(block.copyWith(name: 'New name'));

    expect((await repository.getById(id))!.name, 'New name');
  });

  test('delete removes the block', () async {
    final id = await repository.insert(buildBlock());
    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('getAll returns every block, most recently created first', () async {
    await repository.insert(buildBlock(name: 'Oldest', at: DateTime(2026, 1, 1)));
    await repository.insert(buildBlock(name: 'Newest', at: DateTime(2026, 1, 3)));

    final all = await repository.getAll();

    expect(all.first.name, 'Newest');
  });
}
