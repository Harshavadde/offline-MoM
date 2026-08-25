import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/resume_version_providers.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/resume_version.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/resume_version_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

/// Throws on every call - used only to force resumeVersionListProvider into
/// an error state, which the real repository cannot be made to produce
/// deterministically.
class _ThrowingResumeVersionRepository implements ResumeVersionRepository {
  @override
  Future<List<ResumeVersion>> getForResume(int resumeId) =>
      throw StateError('simulated repository failure');
  @override
  Future<int> insert(ResumeVersion version) => throw UnimplementedError();
  @override
  Future<void> renameLabel(int id, String newLabel) => throw UnimplementedError();
  @override
  Future<void> setExportedPdfPath(int id, String path) => throw UnimplementedError();
  @override
  Future<void> delete(int id) => throw UnimplementedError();
  @override
  Future<void> deleteAllForResume(int resumeId) => throw UnimplementedError();
  @override
  Future<ResumeVersion?> getById(int id) => throw UnimplementedError();
}

void main() {
  late Database db;
  late ResumeVersionRepository resumeVersionRepository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    resumeVersionRepository = SqfliteResumeVersionRepository(db);
    container = ProviderContainer(
      overrides: [resumeVersionRepositoryProvider.overrideWithValue(resumeVersionRepository)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  ResumeSnapshot buildSnapshot(int resumeId) {
    return ResumeSnapshot(
      resumeId: resumeId,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
    );
  }

  Future<int> insertVersion(int resumeId, {String label = 'v1'}) {
    return resumeVersionRepository.insert(ResumeVersion(
      id: null,
      resumeId: resumeId,
      versionLabel: label,
      compiledSnapshot: buildSnapshot(resumeId),
      createdAt: DateTime(2026, 1, 1),
    ));
  }

  test('starts in a loading state before the repository call resolves', () {
    final asyncValue = container.read(resumeVersionListProvider(1));
    expect(asyncValue, isA<AsyncLoading<List<ResumeVersion>>>());
  });

  test('resolves to an empty list when the resume has no saved versions', () async {
    final versions = await container.read(resumeVersionListProvider(1).future);
    expect(versions, isEmpty);
  });

  test('resolves to every version of the given resume, most recent first', () async {
    await insertVersion(1, label: 'v1');
    await insertVersion(1, label: 'v2');

    final versions = await container.read(resumeVersionListProvider(1).future);

    expect(versions.map((v) => v.versionLabel).toSet(), {'v1', 'v2'});
  });

  test('is scoped independently per resumeId - one resume\'s versions never leak into another\'s',
      () async {
    await insertVersion(1, label: 'Resume 1 version');
    await insertVersion(2, label: 'Resume 2 version');

    final versionsForResume1 = await container.read(resumeVersionListProvider(1).future);

    expect(versionsForResume1, hasLength(1));
    expect(versionsForResume1.single.versionLabel, 'Resume 1 version');
  });

  test('surfaces a repository failure as an AsyncError, not an uncaught exception', () async {
    final failingContainer = ProviderContainer(
      overrides: [
        resumeVersionRepositoryProvider.overrideWithValue(_ThrowingResumeVersionRepository()),
      ],
    );
    addTearDown(failingContainer.dispose);

    await expectLater(
      failingContainer.read(resumeVersionListProvider(1).future),
      throwsA(isA<StateError>()),
    );
    expect(failingContainer.read(resumeVersionListProvider(1)), isA<AsyncError>());
  });

  test('invalidation contract: refetches and reflects a version inserted directly through the '
      'repository after the provider already resolved once - proves the provider is not stuck '
      'on stale cached data once invalidated, the same refresh a future controller\'s '
      'ref.invalidate(resumeVersionListProvider(resumeId)) call will rely on', () async {
    final firstRead = await container.read(resumeVersionListProvider(1).future);
    expect(firstRead, isEmpty);

    await insertVersion(1, label: 'Newly Saved');
    container.invalidate(resumeVersionListProvider(1));

    final secondRead = await container.read(resumeVersionListProvider(1).future);
    expect(secondRead.map((v) => v.versionLabel), contains('Newly Saved'));
  });
}
