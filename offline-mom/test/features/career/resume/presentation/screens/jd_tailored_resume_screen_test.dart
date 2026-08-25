// Tests JdTailoredResumeScreen ("Create Resume for a Job") - real Sqflite
// repositories against a throwaway in-memory database, a minimal
// self-contained GoRouter with a stand-in template-gallery destination, a
// FakeLlmEngine for the bounded AI calls (never a real on-device model
// under `flutter test`). Mirrors beginner_resume_screen_test.dart's own
// pattern closely, since this screen mirrors that one's structure.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/jd_tailored_resume_screen.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/fake_ai_engines.dart';
import '../../../../../test_helpers/test_database.dart';

Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ResumeRepository resumeRepository;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester, {String? summaryResponse, String? ideaResponse}) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: RoutePaths.resumeJdTailored,
      routes: [
        GoRoute(
          path: RoutePaths.resumeJdTailored,
          builder: (context, state) => const JdTailoredResumeScreen(),
        ),
        GoRoute(
          path: RoutePaths.resumeTemplates,
          builder: (context, state) => Scaffold(
            body: Text('TEMPLATE GALLERY for resume ${state.pathParameters['resumeId']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resumeRepositoryProvider.overrideWithValue(resumeRepository),
          resumeBlockRepositoryProvider.overrideWithValue(SqfliteResumeBlockRepository(db)),
          educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
          experienceBlockRepositoryProvider.overrideWithValue(SqfliteExperienceBlockRepository(db)),
          projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
          skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
          customSectionBlockRepositoryProvider
              .overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
          llmRequestQueueProvider.overrideWithValue(DefaultLlmRequestQueue()),
          // Never a real on-device model under `flutter test` - see
          // chat_screen_test.dart's identical override for why.
          llmEngineProvider.overrideWithValue(
            FakeLlmEngine(
              responseFromPrompt: (systemPrompt, userPrompt) {
                if (systemPrompt.contains('professional summary')) {
                  return summaryResponse ?? 'A fake generated summary.';
                }
                return ideaResponse ?? 'Title: A Project Idea\nTechnologies: X\nFeatures: Y';
              },
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  Future<void> goNext(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('jdTailoredResumeNextButton')));
    await settle(tester);
  }

  testWidgets('"Next" is disabled on the basics step until a name is entered', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);

      var button = tester.widget<FilledButton>(find.byKey(const Key('jdTailoredResumeNextButton')));
      expect(button.onPressed, isNull);

      await tester.enterText(find.byKey(const Key('jdTailoredNameField')), 'Rahul Kumar');
      await tester.pump();

      button = tester.widget<FilledButton>(find.byKey(const Key('jdTailoredResumeNextButton')));
      expect(button.onPressed, isNotNull);
    });
  });

  testWidgets('"Next" stays disabled on the job description step until a JD is parsed', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('jdTailoredNameField')), 'Rahul Kumar');
      await tester.pump();
      await goNext(tester); // -> job description

      var button = tester.widget<FilledButton>(find.byKey(const Key('jdTailoredResumeNextButton')));
      expect(button.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('jdTailoredJdPasteField')),
        'Data Entry Operator\n\nRequirements:\n- MS Excel\n- Attention to detail',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('jdTailoredJdUseTextButton')));
      await settle(tester);

      expect(find.textContaining('requirement(s) detected'), findsOneWidget);
      button = tester.widget<FilledButton>(find.byKey(const Key('jdTailoredResumeNextButton')));
      expect(button.onPressed, isNotNull);
    });
  });

  testWidgets(
    'an empty/malformed JD (no requirements detected) still lets the wizard proceed gracefully',
    (tester) async {
      await tester.runAsync(() async {
        await pumpScreen(tester);
        await settle(tester);
        await tester.enterText(find.byKey(const Key('jdTailoredNameField')), 'Rahul Kumar');
        await tester.pump();
        await goNext(tester); // -> job description

        // A short, unstructured blob the deterministic JdParser can't
        // extract any labeled requirements from - still a non-empty JD
        // (real requirement: an empty JD must not be treated as ready).
        await tester.enterText(find.byKey(const Key('jdTailoredJdPasteField')), 'hello');
        await tester.pump();
        await tester.tap(find.byKey(const Key('jdTailoredJdUseTextButton')));
        await settle(tester);

        final button = tester.widget<FilledButton>(find.byKey(const Key('jdTailoredResumeNextButton')));
        expect(button.onPressed, isNotNull);

        await goNext(tester); // -> education
        await goNext(tester); // -> experience
        await goNext(tester); // -> projects
        await goNext(tester); // -> skills
        await goNext(tester); // -> review
        await settle(tester);

        // No crash, no stuck spinner - the review step renders with
        // whatever the (possibly empty) draft produced.
        expect(find.text('Review your tailored resume'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'full round-trip: basics + a real JD + no optional steps -> Create Resume reaches the template gallery',
    (tester) async {
      await tester.runAsync(() async {
        await pumpScreen(tester);
        await settle(tester);

        await tester.enterText(find.byKey(const Key('jdTailoredNameField')), 'Rahul Kumar');
        await tester.pump();
        await goNext(tester); // -> job description

        await tester.enterText(
          find.byKey(const Key('jdTailoredJdPasteField')),
          'Data Entry Operator\n\nRequirements:\n- MS Excel\n- Data management\n- Attention to detail',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('jdTailoredJdUseTextButton')));
        await settle(tester);

        await goNext(tester); // -> education
        await goNext(tester); // -> experience
        await goNext(tester); // -> projects
        await goNext(tester); // -> skills
        await goNext(tester); // -> review
        await settle(tester);

        expect(find.text('Review your tailored resume'), findsOneWidget);

        await tester.tap(find.byKey(const Key('jdTailoredResumeNextButton')));
        await settle(tester);

        expect(find.textContaining('TEMPLATE GALLERY for resume'), findsOneWidget);

        final resumes = await resumeRepository.getAll();
        final created = resumes.singleWhere((r) => r.fullName == 'Rahul Kumar');
        expect(created.targetRole, 'Data Entry Operator');
      });
    },
  );
}
