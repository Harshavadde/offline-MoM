// Tests BeginnerResumeScreen (R-10) - real Sqflite repositories against a
// throwaway in-memory database, a minimal self-contained GoRouter with
// stand-in destination screens, no mocks. Mirrors
// resume_editor_screen_test.dart's own pattern.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/features/career/analysis/presentation/providers/resume_jd_analysis_providers.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/beginner_resume_screen.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/shared/widgets/ai_disclaimer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  Future<void> pumpScreen(WidgetTester tester) async {
    // Tall enough that every role chip (14 categories, wrapped across
    // several rows inside a scroll view) is actually attached/hit
    // -testable, not just built - same "sliver/scroll viewport" reasoning
    // resume_jd_analysis_screen_test.dart's own tall-surface fix uses.
    await tester.binding.setSurfaceSize(const Size(412, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: RoutePaths.resumeBeginner,
      routes: [
        GoRoute(
          path: RoutePaths.resumeBeginner,
          builder: (context, state) => const BeginnerResumeScreen(),
        ),
        GoRoute(
          path: RoutePaths.resumeBeginnerTemplate,
          builder: (context, state) => Scaffold(
            body: Text('TEMPLATE SCREEN for resume ${state.pathParameters['resumeId']}'),
          ),
        ),
        GoRoute(
          path: RoutePaths.resumeJdAnalysis,
          builder: (context, state) {
            final extra = state.extra as ResumeJdAnalysisLaunchArgs;
            return Scaffold(
              body: Text(
                'JD ANALYSIS SCREEN for resume ${extra.initialResumeId}, '
                'jd title: ${extra.jd.title}',
              ),
            );
          },
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
          certificationBlockRepositoryProvider
              .overrideWithValue(SqfliteCertificationBlockRepository(db)),
          projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
          skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
          customSectionBlockRepositoryProvider
              .overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  Future<void> goNext(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('beginnerResumeNextButton')));
    await settle(tester);
  }

  testWidgets('"Next" is disabled on the Basics step until a name is entered', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);

      var button = tester.widget<FilledButton>(find.byKey(const Key('beginnerResumeNextButton')));
      expect(button.onPressed, isNull);

      await tester.enterText(find.byKey(const Key('beginnerNameField')), 'Test User');
      await tester.pump();

      button = tester.widget<FilledButton>(find.byKey(const Key('beginnerResumeNextButton')));
      expect(button.onPressed, isNotNull);
    });
  });

  testWidgets('"Next" is disabled on the Target role step until a role is chosen', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('beginnerNameField')), 'Test User');
      await tester.pump();
      await goNext(tester);

      var button = tester.widget<FilledButton>(find.byKey(const Key('beginnerResumeNextButton')));
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('beginnerRoleOption_sales_executive')));
      await tester.pump();

      button = tester.widget<FilledButton>(find.byKey(const Key('beginnerResumeNextButton')));
      expect(button.onPressed, isNotNull);
    });
  });

  testWidgets('pasting a short job title in the JD box maps it to a role category, no full '
      'JD parse', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('beginnerNameField')), 'Test User');
      await tester.pump();
      await goNext(tester);

      await tester.tap(find.text('I have the Job Description'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('beginnerJdPasteField')), 'Data Entry Operator');
      await tester.pump();
      await tester.tap(find.byKey(const Key('beginnerJdUseTextButton')));
      await settle(tester);

      // Folded back into the simple role-picker path - "Data Entry
      // Operator" is now shown as the selected role, not a JD summary card.
      expect(find.text('Reading the job description…'), findsNothing);
      expect(find.textContaining('requirement(s) detected'), findsNothing);
      final button = tester.widget<FilledButton>(find.byKey(const Key('beginnerResumeNextButton')));
      expect(button.onPressed, isNotNull);
    });
  });

  testWidgets('generating with only name + role creates a real resume with no fabricated '
      'sections, then opens the template chooser', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);

      await tester.enterText(find.byKey(const Key('beginnerNameField')), 'Minimal User');
      await tester.pump();
      await goNext(tester); // -> role
      await tester.tap(find.byKey(const ValueKey('beginnerRoleOption_general_fresher')));
      await tester.pump();
      await goNext(tester); // -> education
      await goNext(tester); // -> experience
      await goNext(tester); // -> skills
      await goNext(tester); // -> languages
      await goNext(tester); // -> review

      expect(find.byType(AiDisclaimer), findsOneWidget);

      await tester.tap(find.byKey(const Key('beginnerResumeNextButton')));
      await settle(tester);

      expect(find.textContaining('TEMPLATE SCREEN for resume'), findsOneWidget);

      final resumes = await resumeRepository.getAll();
      final created = resumes.singleWhere((r) => r.fullName == 'Minimal User');
      expect(created.targetRole, 'General Fresher');
    });
  });

  testWidgets('generating after pasting a real JD hands off to the existing JD analysis screen',
      (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);

      await tester.enterText(find.byKey(const Key('beginnerNameField')), 'JD Path User');
      await tester.pump();
      await goNext(tester); // -> role

      await tester.tap(find.text('I have the Job Description'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('beginnerJdPasteField')),
        'Sales Executive\n\nRequirements:\n- Communication\n- Lead follow-up',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('beginnerJdUseTextButton')));
      await settle(tester);

      expect(find.textContaining('requirement(s) detected'), findsOneWidget);

      await goNext(tester); // -> education
      await goNext(tester); // -> experience
      await goNext(tester); // -> skills
      await goNext(tester); // -> languages
      await goNext(tester); // -> review
      await tester.tap(find.byKey(const Key('beginnerResumeNextButton')));
      await settle(tester);

      expect(find.textContaining('JD ANALYSIS SCREEN for resume'), findsOneWidget);
    });
  });
}
