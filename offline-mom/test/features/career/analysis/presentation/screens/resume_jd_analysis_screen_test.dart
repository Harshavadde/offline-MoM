// Tests ResumeJdAnalysisScreen's "Go to editor" action
// (docs/v3/01-prd.md §25 Milestone 2, hard requirement 6) - every analysis
// finding must have a tested path back into the resume editor. Mirrors
// home_screen_test.dart's "minimal router with placeholder destinations"
// pattern to prove the button actually calls context.push with the right
// path, without needing a real navigation target.
//
// The controller provider is overridden with a small, file-local fake
// Notifier (this codebase's own established "local fake for precise
// control" precedent) that starts already in the Succeeded state, so this
// test is isolated to the results screen's own rendering/navigation
// behavior - the analysis pipeline itself is already covered by
// analyze_resume_against_jd_use_case_test.dart and resume_jd_analyzer_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/features/career/analysis/presentation/providers/resume_jd_analysis_providers.dart';
import 'package:offline_mom/features/career/analysis/presentation/screens/resume_jd_analysis_screen.dart';
import 'package:offline_mom/models/job_description.dart';
import 'package:offline_mom/models/resume_jd_analysis_result.dart';

class _FixedSucceededController extends ResumeJdAnalysisController {
  _FixedSucceededController(this._fixedState);

  final ResumeJdAnalysisUiState _fixedState;

  @override
  ResumeJdAnalysisUiState build(ParsedJobDescription jd) => _fixedState;
}

/// Stays in `SelectingResume` forever (never actually transitions state on
/// [analyze]) - isolates the R-7 §3 `initialResumeId` test to
/// `ResumeJdAnalysisScreen`'s own UI branch ("still SelectingResume, but a
/// resume was already chosen for us -> show the loading body, not the
/// picker") deterministically, without racing the real analysis pipeline's
/// timing (which, with no repository/use-case overrides in a plain test
/// container, can fail synchronously before any frame renders).
class _StubSelectingController extends ResumeJdAnalysisController {
  bool analyzeCalled = false;
  int? analyzedResumeId;

  @override
  ResumeJdAnalysisUiState build(ParsedJobDescription jd) => ResumeJdAnalysisSelectingResume(jd: jd);

  @override
  Future<void> analyze(int resumeId) async {
    analyzeCalled = true;
    analyzedResumeId = resumeId;
  }
}

void main() {
  const jd = ParsedJobDescription(
    rawText: 'raw jd text',
    title: 'Backend Engineer',
    requirements: ['Kubernetes', 'Django', 'Terraform'],
    educationRequirements: ["Bachelor's degree required"],
    certificationRequirements: ['AWS Certified Developer'],
  );

  const resumeId = 42;

  const result = ResumeJdAnalysisResult(
    skillMatches: [
      SkillMatchResult(
        jdRequirement: 'Kubernetes',
        level: MatchLevel.exact,
        resumeEvidence: 'Kubernetes',
        matchSource: MatchSource.exactKeyword,
      ),
      SkillMatchResult(
        jdRequirement: 'Django',
        level: MatchLevel.partial,
        resumeEvidence: 'Flask',
        matchSource: MatchSource.tokenOverlap,
      ),
      SkillMatchResult(jdRequirement: 'Terraform', level: MatchLevel.missing),
    ],
    experienceCheck: ExperienceCheckResult(
      summary: 'The resume shows approximately 5 year(s) of experience.',
    ),
    educationChecks: [
      RequirementCheckResult(
        jdRequirement: "Bachelor's degree required",
        level: MatchLevel.exact,
        resumeEvidence: 'B.Sc',
        matchSource: MatchSource.exactKeyword,
      ),
    ],
    certificationChecks: [
      RequirementCheckResult(jdRequirement: 'AWS Certified Developer', level: MatchLevel.missing),
    ],
  );

  Future<void> pumpAnalysisScreen(WidgetTester tester, {ResumeJdAnalysisResult? withResult}) async {
    // Tall enough that every card in the results ListView is actually
    // built (not just the viewport's visible extent) - the screen renders
    // six "Go to editor" actions across cards that don't all fit on a
    // phone-sized viewport, and Flutter's sliver lists only build
    // children near the viewport/cache extent.
    await tester.binding.setSurfaceSize(const Size(412, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: RoutePaths.resumeJdAnalysis,
      routes: [
        GoRoute(path: RoutePaths.resumeJdAnalysis, builder: (_, __) => const ResumeJdAnalysisScreen(jd: jd)),
        GoRoute(
          path: RoutePaths.resumeEditor,
          builder: (_, state) => Scaffold(
            body: Center(child: Text('editor-route-${state.pathParameters['resumeId']}')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // `overrideWith` lives on the family itself (not on a specific
          // `provider(arg)` instance) for `NotifierProvider.autoDispose.family`
          // in riverpod 2.6.1 - the override's `create` factory is
          // argument-agnostic, so the fixed state is captured directly
          // rather than looked up per-arg. Safe here since this test only
          // ever uses one `jd` instance.
          resumeJdAnalysisControllerProvider.overrideWith(
            () => _FixedSucceededController(
              ResumeJdAnalysisSucceeded(jd: jd, resumeId: resumeId, result: withResult ?? result),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('R-7 §3/§4', () {
    testWidgets('names both the resume and the job description together, unmistakably',
        (tester) async {
      await pumpAnalysisScreen(tester);

      expect(find.text('RESUME'), findsOneWidget);
      expect(find.text('JOB DESCRIPTION'), findsOneWidget);
    });

    testWidgets('with an initialResumeId, skips resume selection and starts analysis '
        'automatically (R-7 §3\'s "Create resume from a Job Description" flow)',
        (tester) async {
      final stubController = _StubSelectingController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [resumeJdAnalysisControllerProvider.overrideWith(() => stubController)],
          child: const MaterialApp(
            home: ResumeJdAnalysisScreen(jd: jd, initialResumeId: resumeId),
          ),
        ),
      );
      // Not `pumpAndSettle()`: `_RunningBody`'s `CircularProgressIndicator`
      // animates indefinitely (this stub deliberately never leaves
      // `SelectingResume`/never stops "loading"), so settling would time
      // out waiting for animation frames that never stop being scheduled.
      await tester.pump();
      await tester.pump();

      expect(find.text('Select a resume to analyze'), findsNothing);
      expect(find.text('Analyzing locally on this device…'), findsOneWidget);
      expect(stubController.analyzeCalled, isTrue);
      expect(stubController.analyzedResumeId, resumeId);
    });
  });

  group('Go to editor', () {
    testWidgets('renders a "Go to editor" action for every skill match, including missing ones',
        (tester) async {
      await pumpAnalysisScreen(tester);

      // One per skill match (exact + partial + missing) + one for the
      // experience check + one for the single education check + one for
      // the single certification check.
      expect(find.text('Go to editor'), findsNWidgets(6));
    });

    testWidgets('tapping a "Go to editor" action navigates to this exact resume\'s editor',
        (tester) async {
      await pumpAnalysisScreen(tester);

      await tester.tap(find.text('Go to editor').first);
      await tester.pumpAndSettle();

      expect(find.text('editor-route-$resumeId'), findsOneWidget);
    });

    testWidgets('the missing-requirement "Go to editor" action also navigates correctly - a '
        'finding needs no existing evidence to still link back to the editor', (tester) async {
      await pumpAnalysisScreen(tester);

      // "Terraform" is the only missing skill match, rendered inside the
      // "Missing from resume" section - its row's action is the last
      // among the three skill-match rows.
      await tester.tap(find.text('Go to editor').at(2));
      await tester.pumpAndSettle();

      expect(find.text('editor-route-$resumeId'), findsOneWidget);
    });
  });

  group('Generate AI suggestions availability (R-11 P0 fix)', () {
    const noPartialMatchesResult = ResumeJdAnalysisResult(
      skillMatches: [
        SkillMatchResult(
          jdRequirement: 'Kubernetes',
          level: MatchLevel.exact,
          resumeEvidence: 'Kubernetes',
          matchSource: MatchSource.exactKeyword,
        ),
        SkillMatchResult(jdRequirement: 'Terraform', level: MatchLevel.missing),
      ],
      experienceCheck: ExperienceCheckResult(
        summary: 'The resume shows approximately 5 year(s) of experience.',
      ),
    );

    testWidgets(
        'with zero partial skill matches, explains why instead of silently hiding the button '
        '(regression for the real-device "no best resume points" report)', (tester) async {
      await pumpAnalysisScreen(tester, withResult: noPartialMatchesResult);

      expect(find.text('Generate AI suggestions'), findsNothing);
      expect(find.textContaining('No AI rewrite suggestions are available'), findsOneWidget);
    });

    testWidgets('with at least one partial skill match, shows the button and no explanatory card',
        (tester) async {
      await pumpAnalysisScreen(tester);

      expect(find.text('Generate AI suggestions'), findsOneWidget);
      expect(find.textContaining('No AI rewrite suggestions are available'), findsNothing);
    });
  });
}
