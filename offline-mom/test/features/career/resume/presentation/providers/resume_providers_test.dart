import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/resume_providers.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

/// Throws on every call - used only to force resumeListProvider/
/// resumeByIdProvider into an error state, which the real repository
/// cannot be made to produce deterministically.
class _ThrowingResumeRepository implements ResumeRepository {
  @override
  Future<List<Resume>> getAll() => throw StateError('simulated repository failure');
  @override
  Future<Resume?> getById(int id) => throw StateError('simulated repository failure');
  @override
  Future<int> insert(Resume resume) => throw UnimplementedError();
  @override
  Future<void> update(Resume resume) => throw UnimplementedError();
  @override
  Future<void> delete(int id) => throw UnimplementedError();
  @override
  Future<Resume?> getProfile() => throw UnimplementedError();
  @override
  Future<void> setAsProfile(int id) => throw UnimplementedError();
}

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    container = ProviderContainer(
      overrides: [resumeRepositoryProvider.overrideWithValue(resumeRepository)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> insertResume({String title = 'Backend-Focused'}) {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: title, fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
  }

  group('resumeListProvider', () {
    test('starts in a loading state before the repository call resolves', () {
      final asyncValue = container.read(resumeListProvider);
      expect(asyncValue, isA<AsyncLoading<List<Resume>>>());
    });

    test('resolves to an empty list when there are no resumes', () async {
      final resumes = await container.read(resumeListProvider.future);
      expect(resumes, isEmpty);
    });

    test('resolves to every resume once populated', () async {
      await insertResume(title: 'Backend-Focused');
      await insertResume(title: 'Full-Stack');

      final resumes = await container.read(resumeListProvider.future);

      expect(resumes.map((r) => r.title).toSet(), {'Backend-Focused', 'Full-Stack'});
    });

    test('surfaces a repository failure as an AsyncError, not an uncaught exception', () async {
      final failingContainer = ProviderContainer(
        overrides: [resumeRepositoryProvider.overrideWithValue(_ThrowingResumeRepository())],
      );
      addTearDown(failingContainer.dispose);

      await expectLater(
        failingContainer.read(resumeListProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(failingContainer.read(resumeListProvider), isA<AsyncError>());
    });

    test('invalidation contract: refetches and reflects a resume inserted directly through the '
        'repository after the provider already resolved once - proves the provider is not stuck '
        'on stale cached data once invalidated, the same refresh a future controller\'s '
        'ref.invalidate(resumeListProvider) call will rely on', () async {
      final firstRead = await container.read(resumeListProvider.future);
      expect(firstRead, isEmpty);

      await insertResume(title: 'Newly Added');
      container.invalidate(resumeListProvider);

      final secondRead = await container.read(resumeListProvider.future);
      expect(secondRead.map((r) => r.title), contains('Newly Added'));
    });
  });

  group('resumeByIdProvider', () {
    test('resolves to the matching resume', () async {
      final id = await insertResume(title: 'Backend-Focused');

      final resume = await container.read(resumeByIdProvider(id).future);

      expect(resume, isNotNull);
      expect(resume!.title, 'Backend-Focused');
    });

    test('resolves to null for an unknown id', () async {
      final resume = await container.read(resumeByIdProvider(999999).future);
      expect(resume, isNull);
    });

    test('is scoped independently per id - reading one id\'s provider does not affect another\'s',
        () async {
      final idA = await insertResume(title: 'Resume A');
      final idB = await insertResume(title: 'Resume B');

      final resumeA = await container.read(resumeByIdProvider(idA).future);
      final resumeB = await container.read(resumeByIdProvider(idB).future);

      expect(resumeA!.title, 'Resume A');
      expect(resumeB!.title, 'Resume B');
    });
  });
}
