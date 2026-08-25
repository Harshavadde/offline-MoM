// Tests RejectSuggestedEditUseCase against a real repository
// (openTestDatabase()) - a much smaller surface than accept, since reject
// never touches resume content at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/accept_suggested_edit_use_case.dart'
    show SuggestedEditNotFoundException, SuggestedEditNotPendingException;
import 'package:offline_mom/features/career/resume/reject_suggested_edit_use_case.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/suggested_edit.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/suggested_edit_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late SuggestedEditRepository suggestedEditRepository;
  late RejectSuggestedEditUseCase useCase;
  late int resumeId;
  late int experienceId;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    suggestedEditRepository = SqfliteSuggestedEditRepository(db);
    useCase = RejectSuggestedEditUseCase(suggestedEditRepository: suggestedEditRepository);

    final now = DateTime(2026, 1, 1);
    resumeId = await resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
    experienceId = await experienceBlockRepository.insert(ExperienceBlock(
      id: null,
      role: 'Backend Engineer',
      company: 'Acme Corp',
      startDate: '2020-01',
      endDate: '2023-01',
      bullets: const ['Deployed services using Docker containers.'],
      createdAt: now,
      updatedAt: now,
    ));
    await resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, experienceId);
  });

  tearDown(() => db.close());

  Future<int> insertPendingSuggestion() {
    return suggestedEditRepository.insert(
      SuggestedEdit(
        id: null,
        resumeId: resumeId,
        targetBlockType: ResumeBlockType.experience,
        targetBlockId: experienceId,
        fieldName: 'bullets',
        originalValue: 'Deployed services using Docker containers.',
        suggestedValue: 'Orchestrated Docker container deployments.',
        sourceRequirement: 'Docker orchestration',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  }

  group('rejection persists', () {
    test('the suggestion is marked rejected with resolvedAt set, re-fetched independently',
        () async {
      final editId = await insertPendingSuggestion();

      final result = await useCase.call(editId);

      expect(result.status, SuggestedEditStatus.rejected);
      expect(result.resolvedAt, isNotNull);
      final refetched = await suggestedEditRepository.getById(editId);
      expect(refetched!.status, SuggestedEditStatus.rejected);
    });

    test('a rejected suggestion is not deleted - it remains retrievable for audit/history',
        () async {
      final editId = await insertPendingSuggestion();

      await useCase.call(editId);

      final forResume = await suggestedEditRepository.getForResume(resumeId);
      expect(forResume.map((e) => e.id), contains(editId));
    });
  });

  group('resume remains unchanged', () {
    test('rejecting never modifies the underlying library block content', () async {
      final editId = await insertPendingSuggestion();

      await useCase.call(editId);

      final block = await experienceBlockRepository.getById(experienceId);
      expect(block!.bullets, ['Deployed services using Docker containers.']);
    });

    test('rejecting never sets a per-resume override', () async {
      final editId = await insertPendingSuggestion();

      await useCase.call(editId);

      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.single.overrideJson, isNull);
    });
  });

  group('repeated rejection behaves safely', () {
    test('rejecting an already-rejected suggestion is idempotent - returns the same result '
        'without throwing', () async {
      final editId = await insertPendingSuggestion();
      final first = await useCase.call(editId);

      final second = await useCase.call(editId);

      expect(second.status, SuggestedEditStatus.rejected);
      expect(second.resolvedAt, first.resolvedAt);
    });
  });

  group('invalid state handling', () {
    test('an unknown suggestion id throws SuggestedEditNotFoundException', () async {
      await expectLater(
        useCase.call(999999),
        throwsA(isA<SuggestedEditNotFoundException>()),
      );
    });

    test('rejecting an already-accepted suggestion throws rather than silently changing its '
        'state', () async {
      final editId = await insertPendingSuggestion();
      await suggestedEditRepository.resolve(editId, SuggestedEditStatus.accepted, DateTime.now());

      await expectLater(
        useCase.call(editId),
        throwsA(isA<SuggestedEditNotPendingException>()),
      );
    });
  });
}
