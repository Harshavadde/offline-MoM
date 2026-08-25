// Tests ResumeSuggestionReviewScreen against real repositories
// (openTestDatabase()) - mirrors documents_screen_test.dart's/
// chat_screen_test.dart's precedent of overriding leaf repository
// providers with real, Sqflite-backed instances and running every real-I/O
// step inside `tester.runAsync()`, since real sqflite_common_ffi I/O
// cannot run inside `flutter_test`'s default FakeAsync zone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/resume_suggestion_review_screen.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/suggested_edit.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/repositories/suggested_edit_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

/// Throws on every read - a small, local, test-scoped fake used only for
/// the dedicated error-state test, where a real repository has no natural
/// way to fail on demand.
class _ThrowingSuggestedEditRepository implements SuggestedEditRepository {
  @override
  Future<int> insert(SuggestedEdit edit) => throw UnimplementedError();
  @override
  Future<void> resolve(int id, SuggestedEditStatus status, DateTime resolvedAt) =>
      throw UnimplementedError();
  @override
  Future<void> delete(int id) => throw UnimplementedError();
  @override
  Future<SuggestedEdit?> getById(int id) => throw UnimplementedError();
  @override
  Future<List<SuggestedEdit>> getForResume(int resumeId) => throw UnimplementedError();
  @override
  Future<List<SuggestedEdit>> getPendingForResume(int resumeId) =>
      throw StateError('simulated repository failure');
}

Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceBlockRepository;
  late SuggestedEditRepository suggestedEditRepository;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    suggestedEditRepository = SqfliteSuggestedEditRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertResumeWithExperience() async {
    final now = DateTime(2026, 1, 1);
    final resumeId = await resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
    final experienceId = await experienceBlockRepository.insert(ExperienceBlock(
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
    return resumeId;
  }

  Future<int> insertPendingSuggestion(int resumeId, int experienceId) {
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

  List<Override> baseOverrides() {
    return [
      resumeRepositoryProvider.overrideWithValue(resumeRepository),
      resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
      experienceBlockRepositoryProvider.overrideWithValue(experienceBlockRepository),
      educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
      projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
      certificationBlockRepositoryProvider.overrideWithValue(SqfliteCertificationBlockRepository(db)),
      skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
      customSectionBlockRepositoryProvider.overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
      suggestedEditRepositoryProvider.overrideWithValue(suggestedEditRepository),
    ];
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    int resumeId, {
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...baseOverrides(), ...extraOverrides],
        child: MaterialApp(home: ResumeSuggestionReviewScreen(resumeId: resumeId)),
      ),
    );
  }

  testWidgets('suggestions displayed: shows original text, suggested text, and JD requirement',
      (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResumeWithExperience();
      final experienceId = (await resumeBlockRepository.getForResume(resumeId)).single.blockId;
      await insertPendingSuggestion(resumeId, experienceId);

      await pumpScreen(tester, resumeId);
      await settle(tester);

      expect(find.text('Deployed services using Docker containers.'), findsOneWidget);
      expect(find.text('Orchestrated Docker container deployments.'), findsOneWidget);
      expect(find.textContaining('Docker orchestration'), findsOneWidget);
      expect(find.text('Experience'), findsOneWidget);
    });
  });

  testWidgets('suggestions displayed: a fabrication-flagged suggestion shows a warning',
      (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResumeWithExperience();
      final experienceId = (await resumeBlockRepository.getForResume(resumeId)).single.blockId;
      await suggestedEditRepository.insert(
        SuggestedEdit(
          id: null,
          resumeId: resumeId,
          targetBlockType: ResumeBlockType.experience,
          targetBlockId: experienceId,
          fieldName: 'bullets',
          originalValue: 'Deployed services using Docker containers.',
          suggestedValue: 'Orchestrated Kubernetes deployments, improving uptime by 40%.',
          sourceRequirement: 'Docker orchestration',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      await pumpScreen(tester, resumeId);
      await settle(tester);

      expect(find.textContaining('Review carefully'), findsOneWidget);
    });
  });

  testWidgets('suggestions displayed: a safe suggestion shows no warning', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResumeWithExperience();
      final experienceId = (await resumeBlockRepository.getForResume(resumeId)).single.blockId;
      await insertPendingSuggestion(resumeId, experienceId);

      await pumpScreen(tester, resumeId);
      await settle(tester);

      expect(find.textContaining('Review carefully'), findsNothing);
    });
  });

  testWidgets('accept action: merges the suggestion into the live draft and removes it from '
      'the pending list', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResumeWithExperience();
      final experienceId = (await resumeBlockRepository.getForResume(resumeId)).single.blockId;
      await insertPendingSuggestion(resumeId, experienceId);

      await pumpScreen(tester, resumeId);
      await settle(tester);

      await tester.tap(find.text('Accept'));
      await settle(tester);

      expect(find.text('No suggestions right now'), findsOneWidget);
      final block = await experienceBlockRepository.getById(experienceId);
      expect(block!.bullets, ['Deployed services using Docker containers.']);
      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.single.overrideJson, isNotNull);
    });
  });

  testWidgets('reject action: removes the suggestion from the pending list without changing '
      'resume content', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResumeWithExperience();
      final experienceId = (await resumeBlockRepository.getForResume(resumeId)).single.blockId;
      await insertPendingSuggestion(resumeId, experienceId);

      await pumpScreen(tester, resumeId);
      await settle(tester);

      await tester.tap(find.text('Reject'));
      await settle(tester);

      expect(find.text('No suggestions right now'), findsOneWidget);
      final block = await experienceBlockRepository.getById(experienceId);
      expect(block!.bullets, ['Deployed services using Docker containers.']);
      final refs = await resumeBlockRepository.getForResume(resumeId);
      expect(refs.single.overrideJson, isNull);
    });
  });

  testWidgets('empty state: shows an empty state when there are no pending suggestions',
      (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResumeWithExperience();

      await pumpScreen(tester, resumeId);
      await settle(tester);

      expect(find.text('No suggestions right now'), findsOneWidget);
    });
  });

  testWidgets('error state: shows an error state when the suggestion list fails to load',
      (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResumeWithExperience();

      await pumpScreen(
        tester,
        resumeId,
        extraOverrides: [
          suggestedEditRepositoryProvider.overrideWithValue(_ThrowingSuggestedEditRepository()),
        ],
      );
      await settle(tester);

      expect(find.text("Couldn't load suggestions"), findsOneWidget);
    });
  });
}
