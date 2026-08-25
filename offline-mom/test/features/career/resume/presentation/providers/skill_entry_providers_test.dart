import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/skill_entry_providers.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

/// Throws on every call - used only to force skillEntryListProvider into an
/// error state, which the real repository cannot be made to produce
/// deterministically.
class _ThrowingSkillEntryRepository implements SkillEntryRepository {
  @override
  Future<List<SkillEntry>> getAll() => throw StateError('simulated repository failure');
  @override
  Future<int> insert(SkillEntry entry) => throw UnimplementedError();
  @override
  Future<void> delete(int id) => throw UnimplementedError();
}

void main() {
  late Database db;
  late SkillEntryRepository skillEntryRepository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    skillEntryRepository = SqfliteSkillEntryRepository(db);
    container = ProviderContainer(
      overrides: [skillEntryRepositoryProvider.overrideWithValue(skillEntryRepository)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> insertSkill(String name) {
    return skillEntryRepository.insert(
      SkillEntry(id: null, name: name, category: SkillCategory.technical, createdAt: DateTime(2026, 1, 1)),
    );
  }

  test('starts in a loading state before the repository call resolves', () {
    final asyncValue = container.read(skillEntryListProvider);
    expect(asyncValue, isA<AsyncLoading<List<SkillEntry>>>());
  });

  test('resolves to an empty list when the library has no skills yet', () async {
    final skills = await container.read(skillEntryListProvider.future);
    expect(skills, isEmpty);
  });

  test('resolves to every skill once populated', () async {
    await insertSkill('Flutter');
    await insertSkill('Dart');

    final skills = await container.read(skillEntryListProvider.future);

    expect(skills.map((s) => s.name).toSet(), {'Flutter', 'Dart'});
  });

  test('surfaces a repository failure as an AsyncError, not an uncaught exception', () async {
    final failingContainer = ProviderContainer(
      overrides: [skillEntryRepositoryProvider.overrideWithValue(_ThrowingSkillEntryRepository())],
    );
    addTearDown(failingContainer.dispose);

    await expectLater(
      failingContainer.read(skillEntryListProvider.future),
      throwsA(isA<StateError>()),
    );
    expect(failingContainer.read(skillEntryListProvider), isA<AsyncError>());
  });

  test('invalidation contract: refetches and reflects a skill inserted directly through the '
      'repository after the provider already resolved once - proves the provider is not stuck on '
      'stale cached data once invalidated, the same refresh the inline "+ New skill" action\'s '
      'future ref.invalidate(skillEntryListProvider) call will rely on', () async {
    final firstRead = await container.read(skillEntryListProvider.future);
    expect(firstRead, isEmpty);

    await insertSkill('Newly Added Skill');
    container.invalidate(skillEntryListProvider);

    final secondRead = await container.read(skillEntryListProvider.future);
    expect(secondRead.map((s) => s.name), contains('Newly Added Skill'));
  });
}
