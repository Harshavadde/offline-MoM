// Tests ResumeTemplateGalleryScreen - every card shows a REAL PDF-rendered
// thumbnail of the actual current resume (real-device beta fix, Phase 7:
// previously a fixed sample resume), built from the same
// ResumeTemplateRenderer the final export uses, never a hand-drawn mock;
// see resume_template_providers.dart's own doc comments on
// templateResumePdfBytesProvider/templateResumeThumbnailProvider.
// FakePdfPageRenderingService stands in for the real Printing.raster-backed
// service, the same fake every PDF Tool test already uses, since
// rasterization has no implementation under `flutter test`. Mirrors
// resume_suggestion_review_screen_test.dart's precedent of real,
// Sqflite-backed repositories run inside tester.runAsync().
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/resume_editor_providers.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/resume_template_providers.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/resume_template_gallery_screen.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';
import 'package:offline_mom/services/resume/template/resume_template_spec.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

/// [FakePdfPageRenderingService] still calls the real `newToolkitTempFilePath`
/// (`lib/core/utils/toolkit_paths.dart`), which resolves the app's
/// documents directory via `path_provider` - a platform channel with no
/// implementation under `flutter test`. Mirrors
/// `pdf_compress_controller_test.dart`'s own identical fake exactly.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Beta Product Validation phase: the gallery now renders real PDFs via
  // ResumeTemplateRenderer, which loads the bundled Inter font via
  // rootBundle - requires the Flutter services binding even for the
  // plain (non-widget) test below.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory docsDir;
  late ResumeRepository resumeRepository;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    docsDir = await Directory.systemTemp.createTemp('resume_template_gallery_screen_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  List<Override> baseOverrides() {
    return [
      resumeRepositoryProvider.overrideWithValue(resumeRepository),
      resumeBlockRepositoryProvider.overrideWithValue(SqfliteResumeBlockRepository(db)),
      experienceBlockRepositoryProvider.overrideWithValue(SqfliteExperienceBlockRepository(db)),
      educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
      projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
      certificationBlockRepositoryProvider.overrideWithValue(SqfliteCertificationBlockRepository(db)),
      skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
      customSectionBlockRepositoryProvider.overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
      pdfPageRenderingServiceProvider.overrideWithValue(FakePdfPageRenderingService()),
    ];
  }

  Future<int> insertResume() {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, int resumeId) async {
    // The gallery is a lazy GridView - a default test surface only builds
    // the first couple of rows. All 5 beta templates need to actually
    // exist in the widget tree for this file's assertions, so the test
    // surface is made tall enough that nothing needs scrolling.
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: MaterialApp(home: ResumeTemplateGalleryScreen(resumeId: resumeId)),
      ),
    );
  }

  testWidgets('shows exactly one card per beta catalog template, each with a name, a candidate '
      'description, and an explicit ATS-confidence text label (never color alone)', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      for (final spec in ResumeTemplateCatalog.enabled) {
        expect(find.text(spec.displayName), findsOneWidget, reason: spec.id);
      }
      // Explicit text labels, never color alone (docs/v3/01-prd.md §20) -
      // checked by exact label text (not a "contains ATS" substring
      // search, which would also match Classic's own prose description
      // mentioning "ATS-gated pipeline").
      final maximumCount =
          ResumeTemplateCatalog.enabled.where((s) => s.atsConfidence == AtsConfidence.maximum).length;
      final highCount =
          ResumeTemplateCatalog.enabled.where((s) => s.atsConfidence == AtsConfidence.high).length;
      expect(find.text('Maximum ATS'), findsNWidgets(maximumCount));
      expect(find.text('High ATS'), findsNWidgets(highCount));
    });
  });

  testWidgets('no displayName carries a leftover preset suffix visible to the user - the beta '
      'catalog ships one preset per archetype, not a warm/cool choice', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      expect(find.textContaining('Warm'), findsNothing);
      expect(find.textContaining('Cool'), findsNothing);
    });
  });

  testWidgets(
      'selecting a template (via the underlying controller - the same call the '
      'confirm screen\'s "Use This Template" button makes) persists it as the '
      'resume\'s templateId - the gallery card itself only triggers navigation '
      '(context.push to the detail screen), which needs a real GoRouter to test '
      'safely and is covered separately by resume_template_detail_screen_test.dart',
      (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId);
      await settle(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ResumeTemplateGalleryScreen)),
      );
      final target = ResumeTemplateCatalog.specById('two-column-sidebar-cool');
      await container
          .read(resumeTemplateSelectionControllerProvider(resumeId).notifier)
          .select(target);

      final refetched = await resumeRepository.getById(resumeId);
      expect(refetched!.templateId, target.id);
    });
  });

  group('real preview architecture (no fake preview implementation)', () {
    test(
      'templateResumePdfBytesProvider renders a genuine, non-empty PDF of the actual current '
      'resume for every beta template, via the same ResumeTemplateRenderer the final export '
      'uses - real-device beta fix (Phase 7): previously rendered a fixed sample resume, not '
      'the resume the user is actually editing',
      () async {
        final container = ProviderContainer(overrides: baseOverrides());
        addTearDown(container.dispose);

        final resumeId = await insertResume();
        // autoDispose providers need a listener pinning them alive across
        // event-loop turns while `_load()` resolves - see
        // resume_editor_controller_test.dart's own `waitForReady` for the
        // identical reasoning.
        container.listen(resumeEditorControllerProvider(resumeId), (previous, next) {});
        while (container.read(resumeEditorControllerProvider(resumeId)) is ResumeEditorLoading) {
          await Future<void>.delayed(Duration.zero);
        }

        for (final spec in ResumeTemplateCatalog.enabled) {
          final bytes = await container
              .read(templateResumePdfBytesProvider((resumeId: resumeId, templateId: spec.id)).future);
          expect(bytes, isNotEmpty, reason: spec.id);
          expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: spec.id);
        }
      },
    );

    testWidgets('once the (fake) rasterizer resolves, the grid card renders the real '
        'thumbnail image, not just a placeholder icon', (tester) async {
      await tester.runAsync(() async {
        final resumeId = await insertResume();
        await pumpScreen(tester, resumeId);
        // Rendering 5 real PDFs plus rasterizing each (even via the fast
        // fake rasterizer) is genuinely slower than every other test in
        // this file, which never exercises the real render pipeline -
        // needs longer than the default settle() budget.
        await settle(tester, iterations: 100);

        expect(find.byType(Image), findsWidgets);
      });
    });
  });
}
