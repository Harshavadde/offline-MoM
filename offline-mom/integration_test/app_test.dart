// On-device integration test: exercises the real app (real sqflite/Hive,
// real navigation) rather than fakes. Unlike test/widget_test.dart, this
// needs an actual Android device or emulator - it isn't run as part of
// `flutter test` and can't be exercised in this build environment.
//
// Run with a device/emulator attached:
//   flutter test integration_test/app_test.dart -d <device-id>
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_mom/core/constants/app_constants.dart';
import 'package:offline_mom/database/app_database.dart';
import 'package:offline_mom/main.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/services/documents/parsers/pdf_parser.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots to Home and navigates through the bottom tabs',
      (tester) async {
    await Hive.initFlutter();
    final settingsBox = await Hive.openBox(AppConstants.hiveSettingsBoxName);
    final database = await AppDatabase.open();
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          settingsBoxProvider.overrideWithValue(settingsBox),
        ],
        child: const OfflineMomApp(),
      ),
    );

    // Splash -> Home.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('No meetings yet'), findsOneWidget);

    // Home -> History -> Search -> Settings via the bottom nav bar.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No meeting history'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search your meetings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
  });

  // Milestone 5 (docs/v3/01-prd.md §9/§23, RV3-05/RV3-13,
  // docs/v3/implementation/04-risk-register.md) - the real ATS round-trip
  // the PRD's own test-strategy §23 literally describes: render a PDF ->
  // extract it back out through the *actual* native `PdfParser`
  // (`read_pdf_text`, a platform-channel wrapper around Android's
  // PDFBox-Android / iOS's PDFKit) -> assert expected headings/reading
  // order survive. `test/services/resume/resume_template_renderer_test.dart`
  // cannot do this (no platform channel under `flutter test` - D-M1-01);
  // this file is the one place in the repo that genuinely can, since it
  // already requires a real device/emulator for every other test in it.
  // This test could not be run in this implementation environment (no
  // Android device/emulator attached) and its result is therefore
  // unverified here - it is added so the next real-device run (`flutter
  // test integration_test/app_test.dart -d <device-id>`) closes RV3-13 for
  // real, rather than leaving the gap open with nothing written toward it.
  testWidgets('ATS round-trip: every beta template survives real native PDF text extraction '
      'with every expected section heading present', (tester) async {
    const renderer = ResumeTemplateRenderer();
    final snapshot = ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Jane Doe', email: 'jane@example.com'),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Senior Engineer',
          company: 'Acme Corp',
          startDate: '2022-01',
          bullets: ['Shipped the thing.'],
        ),
      ],
      education: const [
        ResolvedEducationEntry(
          sourceBlockId: 2,
          institution: 'State University',
          degree: 'B.Sc Computer Science',
          startDate: '2015-09',
          endDate: '2019-05',
        ),
      ],
      projects: const [ResolvedProjectEntry(sourceBlockId: 3, name: 'Side Project')],
      certifications: const [
        ResolvedCertificationEntry(sourceBlockId: 4, name: 'AWS Certified', issuer: 'Amazon'),
      ],
      skills: const [ResolvedSkillEntry(sourceBlockId: 5, name: 'Dart', category: SkillCategory.technical)],
    );

    final tempDir = await Directory.systemTemp.createTemp('ats_roundtrip_');
    addTearDown(() => tempDir.delete(recursive: true));
    final parser = PdfParser();

    for (final spec in ResumeTemplateCatalog.all) {
      final bytes = await renderer.render(snapshot, spec);
      final file = File('${tempDir.path}/${spec.id}.pdf');
      await file.writeAsBytes(bytes);

      final extracted = await parser.extractText(file.path);
      expect(extracted, isNotNull, reason: '${spec.id}: PDF produced no extractable text layer');

      for (final heading in ['Experience', 'Education', 'Skills', 'Projects', 'Certifications']) {
        expect(extracted, contains(heading), reason: '${spec.id} missing "$heading" in extracted text');
      }
    }
  });

  // The specific higher-risk property PRD §9 calls out by name: a
  // multi-column archetype's visual layout must not silently scramble the
  // underlying text's reading order. Verified here against the real
  // extraction pipeline, not `ResumeContentPlan` (RV3-05).
  testWidgets(
      'ATS round-trip: two-column-sidebar places sidebar content before the main column in '
      'real extracted text; two-column-right places it after', (tester) async {
    const renderer = ResumeTemplateRenderer();
    final snapshot = ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Senior Engineer',
          company: 'Acme Corp',
          startDate: '2022-01',
        ),
      ],
      skills: const [ResolvedSkillEntry(sourceBlockId: 2, name: 'Dart', category: SkillCategory.technical)],
    );

    final tempDir = await Directory.systemTemp.createTemp('ats_roundtrip_order_');
    addTearDown(() => tempDir.delete(recursive: true));
    final parser = PdfParser();

    Future<String> extractedTextFor(String templateId) async {
      final spec = ResumeTemplateCatalog.specById(templateId);
      final bytes = await renderer.render(snapshot, spec);
      final file = File('${tempDir.path}/$templateId.pdf');
      await file.writeAsBytes(bytes);
      final extracted = await parser.extractText(file.path);
      expect(extracted, isNotNull, reason: templateId);
      return extracted!;
    }

    final sidebarLeftText = await extractedTextFor('two-column-sidebar-cool');
    expect(
      sidebarLeftText.indexOf('Skills'),
      lessThan(sidebarLeftText.indexOf('Experience')),
      reason: 'two-column-sidebar-cool: sidebar (Skills) should extract before the main column',
    );

    final sidebarRightText = await extractedTextFor('two-column-right-warm');
    expect(
      sidebarRightText.indexOf('Skills'),
      greaterThan(sidebarRightText.indexOf('Experience')),
      reason: 'two-column-right-warm: sidebar (Skills) should extract after the main column',
    );
  });
}
