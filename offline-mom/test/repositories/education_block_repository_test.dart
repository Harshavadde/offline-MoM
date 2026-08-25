import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/education_block.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late EducationBlockRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteEducationBlockRepository(db);
  });

  tearDown(() => db.close());

  EducationBlock buildBlock({
    String institution = 'State University',
    DateTime? at,
    List<String> details = const [],
  }) {
    final now = at ?? DateTime(2026, 1, 1);
    return EducationBlock(
      id: null,
      institution: institution,
      degree: 'B.Sc Computer Science',
      startDate: '2018-09',
      endDate: '2022-06',
      details: details,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same block', () async {
    final id = await repository.insert(buildBlock(institution: 'State University'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.institution, 'State University');
    expect(fetched.degree, 'B.Sc Computer Science');
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('fieldOfStudy is nullable and round-trips as null when never set', () async {
    final id = await repository.insert(buildBlock());
    final fetched = (await repository.getById(id))!;

    expect(fetched.fieldOfStudy, isNull);
  });

  test('an empty details list round-trips as an empty list (stored as NULL), not lost', () async {
    final id = await repository.insert(buildBlock(details: const []));
    final fetched = (await repository.getById(id))!;

    expect(fetched.details, isEmpty);
  });

  test('details_json round-trips honors/coursework bullets correctly', () async {
    final id = await repository.insert(buildBlock(details: const ['Magna Cum Laude', 'GPA 3.9']));
    final fetched = (await repository.getById(id))!;

    expect(fetched.details, ['Magna Cum Laude', 'GPA 3.9']);
  });

  test('update edits fields', () async {
    final id = await repository.insert(buildBlock(institution: 'Old University'));
    final block = (await repository.getById(id))!;

    await repository.update(block.copyWith(institution: 'New University'));

    expect((await repository.getById(id))!.institution, 'New University');
  });

  test('delete removes the block', () async {
    final id = await repository.insert(buildBlock());
    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('getAll returns every block, most recently created first', () async {
    await repository.insert(buildBlock(institution: 'Oldest', at: DateTime(2026, 1, 1)));
    await repository.insert(buildBlock(institution: 'Newest', at: DateTime(2026, 1, 3)));

    final all = await repository.getAll();

    expect(all.first.institution, 'Newest');
  });
}
