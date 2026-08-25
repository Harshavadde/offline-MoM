// Manual verification script (Part I, import completeness stress-testing
// pass) - NOT part of the regular regression suite. Combines every Part I
// edge case into one synthetic resume - multi-role-same-company, named
// sub-projects (D-M9-01), a bullet-free experience entry, an international
// (non-Indian curated) location, and a mix of bullet marker styles - runs it
// through the REAL, unmodified ResumeImportParser, assembles a
// ResumeSnapshot from the parsed draft exactly the way
// ResumeCompilerService would, then renders it through the real,
// unmodified ResumeTemplateRenderer for all 5 templates, so the completeness
// unit tests' claims can also be visually inspected in an actual PDF.
//
// Run with: flutter test test/manual/generate_part_i_stress_pdfs_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

const _resumeText = '''
Jane Doe
London, UK | jane.doe@example.com | (206) 555-0113

EXPERIENCE

Senior Engineer - Acme Corp
2022 - Present
- Led the platform team through a major migration.
* Owned the on-call rotation for three services.
• Mentored two junior engineers.
1. Shipped the v2 payments pipeline.
SciLab (Web & Android) — Godot, AWS S3
- Built the mobile client for the internal science-learning tool.
- Integrated cloud storage for offline-first sync.
ByHeart — Flashcards app
- Built the spaced-repetition scheduling engine.

Software Engineer - Acme Corp
2019 - 2022

EDUCATION

B.Tech Computer Science
State University
2015 - 2019

AWARDS

Employee of the Year, 2021
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render a Part I combined-edge-case resume through the real import + render pipeline for all 5 templates', () async {
    final draft = const ResumeImportParser().parse(_resumeText);

    // ignore: avoid_print
    print('completeness: ${draft.completeness.toReportString()}');
    // ignore: avoid_print
    print('location: ${draft.location}');
    // ignore: avoid_print
    print('experience entries: ${draft.experience.length}');
    for (final e in draft.experience) {
      // ignore: avoid_print
      print('  - ${e.role} | ${e.company} (${e.startDate}-${e.endDate}): ${e.bullets.length} bullets');
      for (final sub in e.subProjects) {
        // ignore: avoid_print
        print('      sub-project: ${sub.name} (${sub.bullets.length} bullets)');
      }
    }
    // ignore: avoid_print
    print('warnings: ${draft.warnings}');
    // ignore: avoid_print
    print('unclassified blocks: ${draft.unclassifiedText.length}');

    // These mirror resume_import_completeness_test.dart's own Part I
    // assertions - re-confirmed here against the exact same document that
    // gets rendered below, so the visual PDF inspection and the unit-test
    // claims are provably about the same parse.
    expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
    expect(draft.location, 'London, UK');
    expect(draft.experience, hasLength(2));
    expect(draft.experience.map((e) => e.company), ['Acme Corp', 'Acme Corp']);
    expect(draft.experience[0].bullets, hasLength(4));
    expect(draft.experience[0].subProjects, hasLength(2));
    expect(draft.experience[1].bullets, isEmpty);

    var id = 1;
    final snapshot = ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime.now(),
      profile: ResumeSnapshotProfile(
        fullName: draft.fullName ?? '',
        email: draft.email,
        phone: draft.phone,
        location: draft.location,
        links: draft.links,
      ),
      experience: draft.experience
          .map((e) => ResolvedExperienceEntry(
                sourceBlockId: id++,
                role: e.role,
                company: e.company,
                location: e.location,
                startDate: e.startDate,
                endDate: e.endDate,
                bullets: e.bullets,
                subProjects: e.subProjects,
              ))
          .toList(),
      education: draft.education
          .map((e) => ResolvedEducationEntry(
                sourceBlockId: id++,
                institution: e.institution,
                degree: e.degree,
                fieldOfStudy: e.fieldOfStudy,
                startDate: e.startDate,
                endDate: e.endDate,
                details: e.details,
              ))
          .toList(),
      projects: draft.projects
          .map((p) => ResolvedProjectEntry(sourceBlockId: id++, name: p.name, link: p.link, bullets: p.bullets))
          .toList(),
      certifications: draft.certifications
          .map((c) => ResolvedCertificationEntry(
                sourceBlockId: id++,
                name: c.name,
                issuer: c.issuer,
                issuedDate: c.issuedDate,
                credentialUrl: c.credentialUrl,
              ))
          .toList(),
      skills: draft.skills
          .map((s) => ResolvedSkillEntry(sourceBlockId: id++, name: s.name, category: s.category))
          .toList(),
      customSections: draft.customSections
          .map((c) => ResolvedCustomSectionEntry(sourceBlockId: id++, title: c.title, entries: c.entries))
          .toList(),
    );

    const renderer = ResumeTemplateRenderer();
    final outDir = Directory(_outputDir)..createSync(recursive: true);

    for (final spec in ResumeTemplateCatalog.enabled) {
      try {
        final bytes = await renderer.render(snapshot, spec);
        final safeName = spec.displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
        final file = File('${outDir.path}/part_i_stress_$safeName.pdf');
        await file.writeAsBytes(bytes);
        // ignore: avoid_print
        print('OK   ${spec.displayName}: wrote ${file.path} (${bytes.length} bytes)');
      } catch (e) {
        // ignore: avoid_print
        print('FAIL ${spec.displayName}: $e');
        fail('${spec.displayName} threw during render: $e');
      }
    }
  });
}
