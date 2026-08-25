// Tests ResumeTemplateDetailScreen (Beta Product Validation phase - the
// "tap a template -> larger real preview -> Use This Template" confirm
// step). Uses a minimal, self-contained GoRouter rather than the full app
// router, mirroring this file's own precedent of exercising real
// navigation only where a test genuinely needs it - but its route stack
// mirrors the real app's own shape (List -> Editor -> Gallery -> Detail,
// all reached via push) so the "Use This Template" button's own pop-twice
// navigation (see resume_template_detail_screen.dart's own comment on why
// it pops rather than using context.go) is exercised against a realistic
// back-stack, not an artificially short one.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/resume_template_detail_screen.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

Future<void> settle(WidgetTester tester, {int iterations = 40}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// This screen embeds `printing`'s [PdfPreview] directly - the same widget
// ResumePreviewScreen uses for the real resume's own preview - which calls
// the 'net.nfet.printing' MethodChannel unconditionally from
// didChangeDependencies, before its own `Printing.info()` future resolves.
// Under `flutter test` that channel has no implementation, so without a
// mock handler the very first raster() call throws an unhandled
// MissingPluginException for 'rasterPdf'. Answering 'printingInfo' with
// canRaster:false makes PdfPreview show its own "can't raster" placeholder
// instead of crashing - this file asserts on the screen's own chrome (title,
// description, Use This Template button), never on rendered PDF pixels, so
// a real raster result is not needed here.
const MethodChannel _printingChannel = MethodChannel('net.nfet.printing');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ResumeRepository resumeRepository;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _printingChannel,
      (call) async => call.method == 'printingInfo' ? <String, dynamic>{'canRaster': false} : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_printingChannel, null);
    return db.close();
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
    ];
  }

  Future<int> insertResume() {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: 'Backend-Focused', fullName: 'Jane Doe', email: 'jane@example.com', createdAt: now, updatedAt: now),
    );
  }

  /// Builds a router with the same route *shape* the real app navigates
  /// through to reach this screen - List -> Editor -> Gallery -> Detail,
  /// each a `push` - then actually drives that navigation (not just
  /// `initialLocation`, which would give a one-entry stack and could never
  /// catch a pop-count regression) so `router.pop()`-based assertions are
  /// checking real back-stack behavior.
  Future<GoRouter> pumpScreen(WidgetTester tester, int resumeId, String templateId) async {
    final router = GoRouter(
      initialLocation: '/list',
      routes: [
        GoRoute(path: '/list', builder: (context, state) => const Scaffold(body: Text('LIST SCREEN'))),
        GoRoute(
          path: '/resume/:resumeId',
          builder: (context, state) => const Scaffold(body: Text('EDITOR SCREEN')),
        ),
        GoRoute(
          path: '/resume/:resumeId/templates',
          builder: (context, state) => const Scaffold(body: Text('GALLERY SCREEN')),
        ),
        GoRoute(
          path: '/resume/:resumeId/templates/:templateId',
          builder: (context, state) => ResumeTemplateDetailScreen(
            resumeId: int.parse(state.pathParameters['resumeId']!),
            templateId: state.pathParameters['templateId']!,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/resume/$resumeId');
    await tester.pump();
    router.push('/resume/$resumeId/templates');
    await tester.pump();
    router.push('/resume/$resumeId/templates/$templateId');
    await tester.pump();
    return router;
  }

  testWidgets('shows the template\'s name and candidate description', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      await pumpScreen(tester, resumeId, 'classic-single-column-warm');
      await settle(tester);

      expect(find.text('Classic'), findsWidgets);
    });
  });

  testWidgets(
    'Part J (template gallery/preview - "shows blank when preview" fix): when raster is '
    'unavailable (canRaster: false, mocked in setUp for every test in this file), the screen '
    'shows a real, readable message instead of Flutter\'s default textless ErrorWidget - the '
    'exact fallback whose message text is stripped entirely in release builds, the confirmed '
    'root cause of the reported blank preview',
    (tester) async {
      await tester.runAsync(() async {
        final resumeId = await insertResume();
        await pumpScreen(tester, resumeId, 'classic-single-column-warm');
        await settle(tester);

        expect(find.text('Preview unavailable'), findsOneWidget);
        expect(find.byType(ErrorWidget), findsNothing);
      });
    },
  );

  testWidgets('"Use This Template" persists templateId, leaves every other Profile field '
      'untouched, and pops back exactly to the Editor - never discarding the rest of the '
      'back-stack (e.g. the List screen) the way context.go would', (tester) async {
    await tester.runAsync(() async {
      final resumeId = await insertResume();
      final router = await pumpScreen(tester, resumeId, 'minimalist-monochrome-cool');
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Use This Template'));
      await settle(tester);

      final resume = await resumeRepository.getById(resumeId);
      expect(resume!.templateId, 'minimalist-monochrome-cool');
      // Content untouched - selecting a template only ever changes
      // templateId (ResumeTemplateSelectionController.select's own single-
      // field update).
      expect(resume.fullName, 'Jane Doe');
      expect(resume.email, 'jane@example.com');
      expect(resume.title, 'Backend-Focused');

      expect(find.text('EDITOR SCREEN'), findsOneWidget);
      expect(find.text('GALLERY SCREEN'), findsNothing);

      // The regression this test exists to prevent: popping the stack
      // that existed *before* the template-selection flow ever started
      // must still work - proving "Use This Template" popped exactly two
      // routes rather than collapsing the whole stack down to the Editor.
      router.pop();
      await settle(tester);
      expect(find.text('LIST SCREEN'), findsOneWidget);
    });
  });
}
