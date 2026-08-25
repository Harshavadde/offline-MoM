import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/services/resume/resume_pdf_export_service.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

void main() {
  // Post-Milestone-5 visual-quality redesign pass: the renderer now loads
  // the bundled Inter font via rootBundle, which requires the Flutter
  // services binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PwResumePdfExportService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resume_pdf_export_service_test_');
    service = const PwResumePdfExportService();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ResumeSnapshot buildSnapshot({String fullName = 'Jane Doe'}) {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: ResumeSnapshotProfile(fullName: fullName, email: 'jane@example.com'),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Senior Engineer',
          company: 'Acme Corp',
          startDate: '2022-01',
          bullets: ['Shipped the thing'],
        ),
      ],
      skills: const [],
    );
  }

  group('render', () {
    test('produces non-empty bytes that are a real PDF document', () async {
      final bytes = await service.render(buildSnapshot());

      expect(bytes, isNotEmpty);
      // Every valid PDF file begins with this magic header.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders successfully for a snapshot with every section populated', () async {
      final snapshot = ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
        experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Engineer',
            company: 'Acme',
            startDate: '2022-01',
            bullets: ['A bullet'],
          ),
        ],
        education: const [
          ResolvedEducationEntry(
            sourceBlockId: 2,
            institution: 'State University',
            degree: 'B.Sc',
            startDate: '2015-09',
          ),
        ],
        projects: const [ResolvedProjectEntry(sourceBlockId: 3, name: 'Project')],
        certifications: const [
          ResolvedCertificationEntry(sourceBlockId: 4, name: 'Cert', issuer: 'Issuer'),
        ],
        skills: const [ResolvedSkillEntry(sourceBlockId: 5, name: 'Flutter', category: SkillCategory.technical)],
      );

      final bytes = await service.render(snapshot);

      expect(bytes, isNotEmpty);
    });

    test('renders successfully for a snapshot with no sections populated at all', () async {
      final snapshot = ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      );

      final bytes = await service.render(snapshot);

      expect(bytes, isNotEmpty);
    });

    test('non-Latin characters in the full name and content never cause an uncaught exception - '
        'either they render, or a ResumePdfRenderException is thrown, never a raw/uncaught error',
        () async {
      final snapshot = ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'José François Müller García'),
        experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Ingénieur',
            company: 'Müller & Söhne',
            startDate: '2022-01',
            bullets: ['Diseñó y construyó un sistema completo'],
          ),
        ],
      );

      try {
        final bytes = await service.render(snapshot);
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      } on ResumePdfRenderException catch (e) {
        // The approved fallback - a typed, catchable failure, not a raw
        // exception and not silently corrupt output.
        expect(e.message, isNotEmpty);
      }
    });
  });

  group('exportToFile', () {
    test('writes the PDF to the destination path, which exists and is non-empty afterward',
        () async {
      final destinationPath = '${tempDir.path}/resume.pdf';

      final resultPath = await service.exportToFile(buildSnapshot(), destinationPath);

      expect(resultPath, destinationPath);
      final file = File(destinationPath);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));
    });

    test('the final file starts with a valid PDF header - never a partial/corrupt write', () async {
      final destinationPath = '${tempDir.path}/resume.pdf';

      await service.exportToFile(buildSnapshot(), destinationPath);

      final bytes = await File(destinationPath).readAsBytes();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('no .tmp file is left behind after a successful export - temp-then-rename completed '
        'cleanly', () async {
      final destinationPath = '${tempDir.path}/resume.pdf';

      await service.exportToFile(buildSnapshot(), destinationPath);

      expect(await File('$destinationPath.tmp').exists(), isFalse);
    });

    test('returns only the final destination path, never a temporary one', () async {
      final destinationPath = '${tempDir.path}/resume.pdf';

      final resultPath = await service.exportToFile(buildSnapshot(), destinationPath);

      expect(resultPath, isNot(contains('.tmp')));
    });

    test('on a write failure, the destination path is never created and the temp file is cleaned '
        'up - the caller never sees a partially-written file at the final path', () async {
      // Force a write failure: the "directory" the destination lives in is
      // actually an existing file, so creating it must fail.
      final blockerPath = '${tempDir.path}/blocker';
      await File(blockerPath).writeAsString('not a directory');
      final destinationPath = '$blockerPath/resume.pdf';

      await expectLater(
        service.exportToFile(buildSnapshot(), destinationPath),
        throwsA(anything),
      );

      expect(
        await File(destinationPath).exists(),
        isFalse,
        reason: 'a failed export must never leave a file at the final destination',
      );
      expect(await File('$destinationPath.tmp').exists(), isFalse);
    });

    test('re-exporting to the same destination path overwrites it cleanly, still ending with a '
        'valid, complete file', () async {
      final destinationPath = '${tempDir.path}/resume.pdf';

      await service.exportToFile(buildSnapshot(fullName: 'First Version'), destinationPath);
      await service.exportToFile(buildSnapshot(fullName: 'Second Version'), destinationPath);

      final file = File(destinationPath);
      expect(await file.exists(), isTrue);
      final bytes = await file.readAsBytes();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test(
      'atomic-write regression (V3 Milestone 1): the temp-then-rename discipline is preserved '
      'when an explicit, non-default templateSpec is used, not just the default template',
      () async {
        final destinationPath = '${tempDir.path}/resume.pdf';
        final spec = ResumeTemplateCatalog.specById('two-column-sidebar-cool');

        final resultPath = await service.exportToFile(buildSnapshot(), destinationPath, templateSpec: spec);

        expect(resultPath, destinationPath);
        expect(await File(destinationPath).exists(), isTrue);
        expect(await File('$destinationPath.tmp').exists(), isFalse);
        final bytes = await File(destinationPath).readAsBytes();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      },
    );
  });
}
