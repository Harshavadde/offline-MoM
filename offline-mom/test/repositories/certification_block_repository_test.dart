import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/certification_block.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late CertificationBlockRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteCertificationBlockRepository(db);
  });

  tearDown(() => db.close());

  CertificationBlock buildBlock({String name = 'AWS Certified', DateTime? at}) {
    final now = at ?? DateTime(2026, 1, 1);
    return CertificationBlock(
      id: null,
      name: name,
      issuer: 'Amazon',
      issuedDate: '2024-05',
      credentialUrl: 'https://example.com/cred/123',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same block, including the name column', () async {
    final id = await repository.insert(buildBlock(name: 'AWS Solutions Architect'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.name, 'AWS Solutions Architect');
    expect(fetched.issuer, 'Amazon');
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('issuedDate and credentialUrl are nullable and round-trip as null when never set', () async {
    final now = DateTime(2026, 1, 1);
    final id = await repository.insert(
      CertificationBlock(id: null, name: 'Cert', issuer: 'Issuer', createdAt: now, updatedAt: now),
    );

    final fetched = (await repository.getById(id))!;
    expect(fetched.issuedDate, isNull);
    expect(fetched.credentialUrl, isNull);
  });

  test('update edits fields', () async {
    final id = await repository.insert(buildBlock(name: 'Old cert'));
    final block = (await repository.getById(id))!;

    await repository.update(block.copyWith(name: 'New cert'));

    expect((await repository.getById(id))!.name, 'New cert');
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
