// Tests JdToResumeScreen (R-7 §3, "Create resume from a Job Description") -
// the paste-first entry point, distinct from JdImportScreen's existing
// file-first "analyze an existing resume" flow. Real Sqflite repositories
// against a throwaway in-memory database, no mocks - mirrors
// create_resume_from_profile_use_case_test.dart's style.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/features/career/analysis/presentation/providers/resume_jd_analysis_providers.dart';
import 'package:offline_mom/features/career/jd/create_resume_from_jd_use_case.dart';
import 'package:offline_mom/features/career/jd/presentation/screens/jd_to_resume_screen.dart';
import 'package:offline_mom/features/career/resume/create_resume_from_profile_use_case.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Database db;
  late ResumeRepository resumeRepository;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    final resumeBlockRepository = SqfliteResumeBlockRepository(db);
    final createResumeFromJdUseCase = CreateResumeFromJdUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      createResumeFromProfileUseCase: CreateResumeFromProfileUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
      ),
    );

    final router = GoRouter(
      initialLocation: RoutePaths.jdToResume,
      routes: [
        GoRoute(path: RoutePaths.jdToResume, builder: (_, __) => const JdToResumeScreen()),
        GoRoute(
          path: RoutePaths.resumeJdAnalysis,
          builder: (_, state) {
            final extra = state.extra as ResumeJdAnalysisLaunchArgs;
            return Scaffold(
              body: Center(child: Text('ANALYSIS SCREEN for resume ${extra.initialResumeId}')),
            );
          },
        ),
        GoRoute(
          path: RoutePaths.resumeEditor,
          builder: (_, state) => Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('EDITOR SCREEN for resume ${state.pathParameters['resumeId']}')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resumeRepositoryProvider.overrideWithValue(resumeRepository),
          resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
          createResumeFromJdUseCaseProvider.overrideWithValue(createResumeFromJdUseCase),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('pasting JD text shows a review step with the parsed JD, before creating anything',
      (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);

      await tester.enterText(
        find.byKey(const Key('jdPasteField')),
        'Backend Engineer at Acme Corp\n\nREQUIREMENTS\n\n- Kubernetes\n- Python\n',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('jdUseTextButton')));
      await settle(tester);

      expect(find.text('Backend Engineer at Acme Corp'), findsOneWidget);
      expect(find.textContaining('requirement(s) detected'), findsOneWidget);
      // Nothing created yet - only reviewing so far.
      expect(await resumeRepository.getAll(), isEmpty);
    });
  });

  testWidgets(
      'creating a resume with no Profile set up shows a clear message and a way forward '
      '(R-11 P0 fix - regression for the real-device "JD flow looks broken" report)',
      (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);

      await tester.enterText(find.byKey(const Key('jdPasteField')), 'REQUIREMENTS\n\n- SQL\n');
      await tester.pump();
      await tester.tap(find.byKey(const Key('jdUseTextButton')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('jdCreateResumeButton')));
      await settle(tester);

      expect(find.textContaining('Set up My Profile first'), findsOneWidget);
      // Previously this was a dead end - no button, no way forward, the
      // user's only option was to leave the screen entirely.
      expect(find.byKey(const Key('jdSetUpProfileButton')), findsOneWidget);
    });
  });

  testWidgets(
      'tapping "Set up My Profile" creates the profile and returning retries '
      'successfully with the same JD still in place (R-11 P0 fix)', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await settle(tester);

      await tester.enterText(
        find.byKey(const Key('jdPasteField')),
        'Backend Engineer at Acme Corp\n\nREQUIREMENTS\n\n- SQL\n',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('jdUseTextButton')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('jdCreateResumeButton')));
      await settle(tester);
      expect(find.byKey(const Key('jdSetUpProfileButton')), findsOneWidget);
      expect(await resumeRepository.getProfile(), isNull);

      await tester.tap(find.byKey(const Key('jdSetUpProfileButton')));
      await settle(tester);

      // Landed on the Editor for the newly-created profile.
      final profile = await resumeRepository.getProfile();
      expect(profile, isNotNull);
      expect(find.text('EDITOR SCREEN for resume ${profile!.id}'), findsOneWidget);

      // Popping back returns to JdToResumeScreen with the JD still reviewed
      // (same widget instance, same jdImportControllerProvider state) -
      // "Create my resume" now succeeds without re-pasting anything.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await settle(tester);

      expect(find.text('Backend Engineer at Acme Corp'), findsOneWidget);
      await tester.tap(find.byKey(const Key('jdCreateResumeButton')));
      await settle(tester);

      final resumes = await resumeRepository.getAll();
      final created = resumes.singleWhere((r) => !r.isProfile);
      expect(created.title, 'Backend Engineer at Acme Corp');
      expect(find.text('ANALYSIS SCREEN for resume ${created.id}'), findsOneWidget);
    });
  });

  testWidgets('creating a resume from a pasted JD builds it from Profile and hands off to '
      'analysis pre-selected - no picker, no fabricated content', (tester) async {
    await tester.runAsync(() async {
      final now = DateTime(2026, 1, 1);
      final profileId = await resumeRepository.insert(Resume(
        id: null,
        title: 'My Profile',
        fullName: 'Jane Doe',
        isProfile: true,
        createdAt: now,
        updatedAt: now,
      ));
      await resumeRepository.setAsProfile(profileId);

      await pumpScreen(tester);
      await settle(tester);

      await tester.enterText(
        find.byKey(const Key('jdPasteField')),
        'Backend Engineer at Acme Corp\n\nREQUIREMENTS\n\n- Kubernetes\n',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('jdUseTextButton')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('jdCreateResumeButton')));
      await settle(tester);

      final resumes = await resumeRepository.getAll();
      final created = resumes.singleWhere((r) => !r.isProfile);
      expect(created.title, 'Backend Engineer at Acme Corp');
      expect(created.fullName, 'Jane Doe');
      expect(find.text('ANALYSIS SCREEN for resume ${created.id}'), findsOneWidget);
    });
  });
}
