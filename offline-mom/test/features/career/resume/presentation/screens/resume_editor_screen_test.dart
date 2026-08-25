// Tests ResumeEditorScreen's AppBar (Physical-Mobile-First Validation
// phase - the AppBar previously carried 6 separate action widgets, which
// crowded out the resume title on a narrow phone; see
// resume_editor_screen.dart's own doc comment on _ResumeMenuAction). No
// dedicated test file existed for this screen before this one. Mirrors
// resume_template_detail_screen_test.dart's own pattern: real Sqflite
// repositories against a throwaway in-memory database, a minimal
// self-contained GoRouter with stand-in destination screens, no mocks.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/resume_editor_screen.dart';
import 'package:offline_mom/features/career/resume/save_resume_version_use_case.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/resume_version_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/repositories/suggested_edit_repository.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:offline_mom/services/resume/resume_pdf_export_service.dart';
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
  late Directory tempDir;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    tempDir = await Directory.systemTemp.createTemp('resume_editor_screen_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> insertResume() {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: 'Backend-Focused', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, int resumeId) async {
    final experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    final educationBlockRepository = SqfliteEducationBlockRepository(db);
    final projectBlockRepository = SqfliteProjectBlockRepository(db);
    final certificationBlockRepository = SqfliteCertificationBlockRepository(db);
    final skillEntryRepository = SqfliteSkillEntryRepository(db);
    final customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    final resumeVersionRepository = SqfliteResumeVersionRepository(db);

    final router = GoRouter(
      initialLocation: '/resume/$resumeId',
      routes: [
        GoRoute(
          path: '/resume/:resumeId',
          builder: (context, state) => ResumeEditorScreen(resumeId: resumeId),
        ),
        GoRoute(
          path: '/resume/:resumeId/templates',
          builder: (context, state) => const Scaffold(body: Text('TEMPLATES SCREEN')),
        ),
        GoRoute(
          path: '/resume/:resumeId/preview',
          builder: (context, state) => const Scaffold(body: Text('PREVIEW SCREEN')),
        ),
        GoRoute(
          path: '/resume/:resumeId/versions',
          builder: (context, state) => const Scaffold(body: Text('VERSIONS SCREEN')),
        ),
        GoRoute(
          path: '/resume/:resumeId/suggestions',
          builder: (context, state) => const Scaffold(body: Text('SUGGESTIONS SCREEN')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resumeRepositoryProvider.overrideWithValue(resumeRepository),
          resumeBlockRepositoryProvider.overrideWithValue(SqfliteResumeBlockRepository(db)),
          experienceBlockRepositoryProvider.overrideWithValue(experienceBlockRepository),
          educationBlockRepositoryProvider.overrideWithValue(educationBlockRepository),
          projectBlockRepositoryProvider.overrideWithValue(projectBlockRepository),
          certificationBlockRepositoryProvider.overrideWithValue(certificationBlockRepository),
          skillEntryRepositoryProvider.overrideWithValue(skillEntryRepository),
          customSectionBlockRepositoryProvider.overrideWithValue(customSectionBlockRepository),
          resumeVersionRepositoryProvider.overrideWithValue(resumeVersionRepository),
          suggestedEditRepositoryProvider.overrideWithValue(SqfliteSuggestedEditRepository(db)),
          saveResumeVersionUseCaseProvider.overrideWithValue(
            SaveResumeVersionUseCase(
              compilerService: ResumeCompilerService(
                experienceBlockRepository: experienceBlockRepository,
                educationBlockRepository: educationBlockRepository,
                projectBlockRepository: projectBlockRepository,
                certificationBlockRepository: certificationBlockRepository,
                skillEntryRepository: skillEntryRepository,
                customSectionBlockRepository: customSectionBlockRepository,
              ),
              resumeVersionRepository: resumeVersionRepository,
              pdfExportService: const PwResumePdfExportService(),
              outputPathProvider: (ext) async =>
                  '${tempDir.path}/resume_${DateTime.now().microsecondsSinceEpoch}.$ext',
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets(
      'the AppBar shows only 2 standalone action icons (Choose a template, Preview) plus one '
      'overflow menu - Versions/Export/Save version/AI suggestions no longer crowd the title as '
      'their own icons', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      expect(find.byTooltip('Choose a template'), findsOneWidget);
      expect(find.byTooltip('Preview'), findsOneWidget);
      expect(find.byTooltip('More'), findsOneWidget);
      expect(find.byTooltip('Versions'), findsNothing);
      expect(find.byTooltip('Export'), findsNothing);
      expect(find.byTooltip('Save version'), findsNothing);
      expect(find.byTooltip('AI suggestions'), findsNothing);
    });
  });

  testWidgets('opening the overflow menu reveals Versions, Export (text/Markdown), Save version, '
      'and AI suggestions - nothing lost, just consolidated', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);

      expect(find.text('Versions'), findsOneWidget);
      expect(find.text('Export as text'), findsOneWidget);
      expect(find.text('Export as Markdown'), findsOneWidget);
      expect(find.text('Save version'), findsOneWidget);
      expect(find.text('AI suggestions'), findsOneWidget);
    });
  });

  testWidgets('tapping "Versions" inside the overflow menu still navigates correctly', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Versions'));
      await settle(tester);

      expect(find.text('VERSIONS SCREEN'), findsOneWidget);
    });
  });

  testWidgets('"Choose a template" still navigates correctly as its own standalone icon', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      await tester.tap(find.byTooltip('Choose a template'));
      await settle(tester);

      expect(find.text('TEMPLATES SCREEN'), findsOneWidget);
    });
  });

  group('progressive wizard (R-7 §2)', () {
    // The step bar scrolls horizontally (8 step chips) - wide enough that
    // every chip is actually built, not just the ones fitting the default
    // 800px-wide test surface (mirrors resume_jd_analysis_screen_test.dart's
    // own tall-surface fix for the same "sliver cache extent" reason, on
    // the horizontal axis instead of vertical).
    Future<void> useWideSurface(WidgetTester tester) async {
      // Tall too, not just wide: the Review step stacks every section
      // vertically (same "sliver cache extent" reasoning as the width fix
      // above, now on the vertical axis for that one step).
      await tester.binding.setSurfaceSize(const Size(1600, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    testWidgets('starts on the Profile step, showing progress and step labels', (tester) async {
      await tester.runAsync(() async {
        await useWideSurface(tester);
        final resumeId = await insertResume();
        await pumpScreen(tester, resumeId);
        await settle(tester);

        expect(find.text('Step 1 of 8 · Profile'), findsOneWidget);
        // Only the Profile step's own content is on screen yet - every
        // other step's label appears exactly once (its step chip only),
        // not a second time as that step's own section heading.
        expect(find.text('Experience'), findsOneWidget);
      });
    });

    testWidgets('"Next" advances exactly one step at a time, showing that step\'s content',
        (tester) async {
      await tester.runAsync(() async {
        await useWideSurface(tester);
        final resumeId = await insertResume();
        await pumpScreen(tester, resumeId);
        await settle(tester);

        await tester.tap(find.text('Next'));
        await settle(tester);

        expect(find.text('Step 2 of 8 · Experience'), findsOneWidget);
        // Now on the Experience step: the "Experience" label appears
        // twice (step chip + this step's own section heading).
        expect(find.text('Experience'), findsNWidgets(2));
      });
    });

    testWidgets('tapping a step chip jumps straight to that step - useful for editing one '
        'section without paging through every other one first', (tester) async {
      await tester.runAsync(() async {
        await useWideSurface(tester);
        final resumeId = await insertResume();
        await pumpScreen(tester, resumeId);
        await settle(tester);

        await tester.tap(find.byKey(const ValueKey('resumeWizardStep_skills')));
        await settle(tester);

        expect(find.text('Step 6 of 8 · Skills'), findsOneWidget);
      });
    });

    testWidgets('the final "Review" step shows every section together, exactly like the '
        'original single-scroll layout - nothing is hidden at the end', (tester) async {
      await tester.runAsync(() async {
        await useWideSurface(tester);
        final resumeId = await insertResume();
        await pumpScreen(tester, resumeId);
        await settle(tester);

        await tester.tap(find.byKey(const ValueKey('resumeWizardStep_review')));
        await settle(tester);

        expect(find.text('Step 8 of 8 · Review'), findsOneWidget);
        expect(find.text('All set'), findsOneWidget);
        expect(find.text('Next'), findsNothing);
        // Every section's heading is visible together on Review, each
        // appearing twice (step chip + this step's own heading), same as
        // "Experience" did on its own dedicated step above.
        for (final label in ['Experience', 'Education', 'Projects', 'Certifications', 'Skills']) {
          expect(find.text(label), findsNWidgets(2));
        }
      });
    });

    testWidgets('"Back" is disabled on the first step and re-enabled after moving forward',
        (tester) async {
      await tester.runAsync(() async {
        final resumeId = await insertResume();
        await pumpScreen(tester, resumeId);
        await settle(tester);

        final backButtonOnFirstStep = tester.widget<TextButton>(
          find.ancestor(of: find.text('Back'), matching: find.byType(TextButton)),
        );
        expect(backButtonOnFirstStep.onPressed, isNull);

        await tester.tap(find.text('Next'));
        await settle(tester);

        final backButtonAfterNext = tester.widget<TextButton>(
          find.ancestor(of: find.text('Back'), matching: find.byType(TextButton)),
        );
        expect(backButtonAfterNext.onPressed, isNotNull);
      });
    });
  });
}
