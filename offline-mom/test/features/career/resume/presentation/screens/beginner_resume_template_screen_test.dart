// Tests BeginnerResumeTemplateScreen (R-10 §10) - real Sqflite repositories
// against a throwaway in-memory database, mirrors
// resume_editor_screen_test.dart's own pattern. `Printing.raster` (the real
// thumbnail rendering) has no implementation under `flutter test` - every
// thumbnail degrades to the same neutral placeholder every PDF-tool test
// already expects, which is fine here since this screen's own logic under
// test is "exactly these 3 templates, selecting one persists templateId and
// navigates," not the rendering pipeline itself.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/beginner_resume_template_screen.dart';
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
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/features/career/resume/save_resume_version_use_case.dart';
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
    tempDir = await Directory.systemTemp.createTemp('beginner_resume_template_screen_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> insertResume() {
    final now = DateTime.now();
    return resumeRepository.insert(
      Resume(id: null, title: 'General Fresher Resume', fullName: 'Test User', createdAt: now, updatedAt: now),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, int resumeId, {GoRouter? router}) async {
    // Tall enough that all 3 grid cards are actually laid out/hit-testable
    // - same "sliver viewport" reasoning used throughout this suite (see
    // resume_jd_analysis_screen_test.dart's identical fix).
    await tester.binding.setSurfaceSize(const Size(412, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final experienceBlockRepository = SqfliteExperienceBlockRepository(db);
    final educationBlockRepository = SqfliteEducationBlockRepository(db);
    final projectBlockRepository = SqfliteProjectBlockRepository(db);
    final certificationBlockRepository = SqfliteCertificationBlockRepository(db);
    final skillEntryRepository = SqfliteSkillEntryRepository(db);
    final customSectionBlockRepository = SqfliteCustomSectionBlockRepository(db);
    final resumeVersionRepository = SqfliteResumeVersionRepository(db);

    final effectiveRouter = router ??
        GoRouter(
          initialLocation: '/resume/$resumeId/beginner-template',
          routes: [
            GoRoute(
              path: '/resume/:resumeId/beginner-template',
              builder: (context, state) => BeginnerResumeTemplateScreen(resumeId: resumeId),
            ),
            GoRoute(
              path: '/resume/:resumeId',
              builder: (context, state) => Scaffold(body: Text('EDITOR SCREEN for resume $resumeId')),
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
          // `Printing.raster` (the real thumbnail rasterizer) has no
          // implementation under `flutter test` - same fake every PDF Tool
          // test already uses (see pdf_page_rendering_service.dart).
          pdfPageRenderingServiceProvider.overrideWithValue(FakePdfPageRenderingService()),
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
        child: MaterialApp.router(routerConfig: effectiveRouter),
      ),
    );
  }

  testWidgets('shows exactly the 3 curated templates, including Entry-Level/Student '
      '(not offered in the main gallery)', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      expect(find.text('Entry-Level / Student'), findsOneWidget);
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Modern Accent'), findsOneWidget);
      // Nothing from the other 7 archetypes leaks in.
      expect(find.text('Two-Column Sidebar'), findsNothing);
      expect(find.text('Minimalist Monochrome'), findsNothing);
    });
  });

  testWidgets('selecting a template persists Resume.templateId and opens the standard editor',
      (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      await tester.tap(find.text('Entry-Level / Student'));
      await settle(tester);

      final resume = (await resumeRepository.getById(resumeId))!;
      expect(resume.templateId, 'entry-level-student-warm');
      expect(find.text('EDITOR SCREEN for resume $resumeId'), findsOneWidget);
    });
  });

  testWidgets(
      'R-11 P0/P1 regression: selecting a template does not destroy the back stack - '
      'the real-device report was "trapped inside Resume creation, no way back to Home". '
      'Root cause: this screen used context.go(...) instead of context.pushReplacement(...), '
      'which replaces the ENTIRE navigation stack rather than swapping just this one screen',
      (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();

      final router = GoRouter(
        initialLocation: '/list',
        routes: [
          GoRoute(
            path: '/list',
            builder: (context, state) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => context.push('/resume/$resumeId/beginner-template'),
                  child: const Text('go to template chooser'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/resume/:resumeId/beginner-template',
            builder: (context, state) => BeginnerResumeTemplateScreen(resumeId: resumeId),
          ),
          GoRoute(
            path: '/resume/:resumeId',
            builder: (context, state) => Scaffold(
              appBar: AppBar(),
              body: Text('EDITOR SCREEN for resume ${state.pathParameters['resumeId']}'),
            ),
          ),
        ],
      );

      await pumpScreen(tester, resumeId, router: router);
      await settle(tester);

      // Starts at the fake "Resume List" screen, pushes into the template
      // chooser - mirrors the real app's Home -> Resume List -> Beginner
      // Resume -> Template Chooser stack shape.
      await tester.tap(find.text('go to template chooser'));
      await settle(tester);
      expect(find.text('Entry-Level / Student'), findsOneWidget);

      await tester.tap(find.text('Entry-Level / Student'));
      await settle(tester);
      expect(find.text('EDITOR SCREEN for resume $resumeId'), findsOneWidget);

      // The real regression: with context.go(), the stack beneath the
      // Editor would be gone entirely and this would be false, leaving
      // the system/app-bar back button with nothing to return to.
      final editorContext = tester.element(find.text('EDITOR SCREEN for resume $resumeId'));
      expect(Navigator.of(editorContext).canPop(), isTrue);

      Navigator.of(editorContext).pop();
      await settle(tester);
      expect(find.text('go to template chooser'), findsOneWidget);
    });
  });
}
