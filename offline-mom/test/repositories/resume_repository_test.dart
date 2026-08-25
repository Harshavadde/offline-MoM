import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_link.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteResumeRepository(db);
  });

  tearDown(() => db.close());

  Resume buildResume({String title = 'Backend-Focused', DateTime? at, List<ResumeLink> links = const []}) {
    final now = at ?? DateTime(2026, 1, 1);
    return Resume(
      id: null,
      title: title,
      fullName: 'Jane Doe',
      links: links,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same resume', () async {
    final id = await repository.insert(buildResume(title: 'Backend-Focused'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.title, 'Backend-Focused');
    expect(fetched.fullName, 'Jane Doe');
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('optional Profile fields round-trip as null when never set', () async {
    final id = await repository.insert(buildResume());
    final fetched = (await repository.getById(id))!;

    expect(fetched.targetRole, isNull);
    expect(fetched.email, isNull);
    expect(fetched.phone, isNull);
    expect(fetched.location, isNull);
    expect(fetched.links, isEmpty);
  });

  test('links_json round-trips a list of ResumeLinks correctly', () async {
    final id = await repository.insert(buildResume(links: const [
      ResumeLink(label: 'Portfolio', url: 'https://example.com'),
      ResumeLink(label: 'GitHub', url: 'https://github.com/example'),
    ]));

    final fetched = (await repository.getById(id))!;

    expect(fetched.links, hasLength(2));
    expect(fetched.links[0].label, 'Portfolio');
    expect(fetched.links[1].url, 'https://github.com/example');
  });

  test('update edits Profile fields', () async {
    final id = await repository.insert(buildResume(title: 'Old title'));
    final resume = (await repository.getById(id))!;

    await repository.update(resume.copyWith(title: 'New title', email: 'jane@example.com'));

    final fetched = (await repository.getById(id))!;
    expect(fetched.title, 'New title');
    expect(fetched.email, 'jane@example.com');
  });

  test('delete removes the resume', () async {
    final id = await repository.insert(buildResume());
    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('getAll orders by most recently updated first', () async {
    await repository.insert(buildResume(title: 'Oldest', at: DateTime(2026, 1, 1)));
    await repository.insert(buildResume(title: 'Newest', at: DateTime(2026, 1, 3)));
    await repository.insert(buildResume(title: 'Middle', at: DateTime(2026, 1, 2)));

    final all = await repository.getAll();

    expect(all.map((r) => r.title).toList(), ['Newest', 'Middle', 'Oldest']);
  });

  group('My Profile (Product Validation phase)', () {
    test('isProfile defaults to false and round-trips as true when set', () async {
      final id = await repository.insert(buildResume());
      expect((await repository.getById(id))!.isProfile, isFalse);

      final resume = (await repository.getById(id))!;
      await repository.update(resume.copyWith(isProfile: true));

      expect((await repository.getById(id))!.isProfile, isTrue);
    });

    test('getProfile returns null when no resume is marked as profile', () async {
      await repository.insert(buildResume());
      expect(await repository.getProfile(), isNull);
    });

    test('setAsProfile designates the resume and getProfile finds it', () async {
      final id = await repository.insert(buildResume(title: 'My Profile'));
      await repository.setAsProfile(id);

      final profile = await repository.getProfile();
      expect(profile, isNotNull);
      expect(profile!.id, id);
      expect(profile.isProfile, isTrue);
    });

    test('setAsProfile enforces at most one profile - designating a second '
        'resume unsets the first', () async {
      final idA = await repository.insert(buildResume(title: 'First'));
      final idB = await repository.insert(buildResume(title: 'Second'));

      await repository.setAsProfile(idA);
      expect((await repository.getById(idA))!.isProfile, isTrue);

      await repository.setAsProfile(idB);

      expect((await repository.getById(idA))!.isProfile, isFalse);
      expect((await repository.getById(idB))!.isProfile, isTrue);
      final all = await repository.getAll();
      expect(all.where((r) => r.isProfile), hasLength(1));
    });

    test('setAsProfile throws for a non-existent resume id', () async {
      await expectLater(repository.setAsProfile(999999), throwsA(isA<StateError>()));
    });
  });
}
