// Manual PDF-generation script (Beta Product Validation phase, pagination
// classification) - NOT part of the regular regression suite. Renders a
// realistic resume with 8 custom sections (well beyond the 5-6 typed
// sections every other fixture in this repo exercises) through Classic
// (single column - the clearest place to see an orphaned section heading)
// and Balanced Two-Column (the archetype already known, from
// generate_beta_template_pdfs_test.dart's own long-career fixture, to
// desynchronize its two columns once one side overflows to a second page),
// so real page-break behavior can be visually inspected rather than assumed.
//
// Run with: flutter test test/manual/generate_pagination_stress_pdfs_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

String _buildManyCustomSectionsText() {
  final buffer = StringBuffer()
    ..writeln('Priya Natarajan')
    ..writeln('priya.natarajan@example.com | (415) 555-0166')
    ..writeln('San Jose, CA')
    ..writeln()
    ..writeln('EXPERIENCE')
    ..writeln()
    ..writeln('Staff Software Engineer - Horizon Systems')
    ..writeln('2019 - Present')
    ..writeln('- Led the platform team\'s migration to a service mesh architecture.')
    ..writeln('- Reduced deployment failures by 60 percent through automated canary analysis.')
    ..writeln()
    ..writeln('Software Engineer - Horizon Systems')
    ..writeln('2016 - 2019')
    ..writeln('- Built the first version of the internal feature-flagging platform.')
    ..writeln()
    ..writeln('EDUCATION')
    ..writeln()
    ..writeln('B.S. in Computer Science - San Jose State University')
    ..writeln('2012 - 2016');

  const customSections = [
    ('AWARDS', ['Employee of the Year, 2022', 'Hackathon Winner, 2021', 'Spot Bonus for Incident Response, 2020']),
    (
      'PUBLICATIONS',
      [
        '"Service Mesh at Scale," Platform Engineering Quarterly, 2023',
        '"Feature Flags Done Right," Internal Engineering Blog, 2021',
      ]
    ),
    ('VOLUNTEER EXPERIENCE', ['Code mentor, Bay Area Coding Bootcamp, 2018 - Present']),
    ('LANGUAGES', ['English (native)', 'Tamil (native)', 'Spanish (conversational)']),
    ('INTERESTS', ['Rock climbing', 'Amateur astronomy', 'Woodworking']),
    ('REFERENCES', ['Available upon request']),
    (
      'PATENTS AND INVENTIONS',
      ['Co-inventor, "Distributed Rate Limiting Method," US Patent App. 2022/0123456']
    ),
    ('SPEAKING ENGAGEMENTS', ['Keynote, Platform Engineering Summit 2023', 'Panelist, Women in Tech Bay Area 2022']),
  ];

  for (final (title, entries) in customSections) {
    buffer.writeln(title);
    buffer.writeln();
    for (final entry in entries) {
      buffer.writeln(entry);
    }
    buffer.writeln();
  }

  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a resume with 8 custom sections plus Experience/Education renders through Classic and '
      'Balanced Two-Column for pagination inspection', () async {
    const parser = ResumeImportParser();
    final draft = parser.parse(_buildManyCustomSectionsText());

    expect(draft.experience, hasLength(2));
    expect(draft.education, hasLength(1));
    expect(draft.customSections, hasLength(8), reason: 'all 8 custom sections must survive import');

    final snapshot = ResumeSnapshot(
      resumeId: 3,
      compiledAt: DateTime(2026, 1, 1),
      profile: ResumeSnapshotProfile(
        fullName: draft.fullName!,
        email: draft.email,
        phone: draft.phone,
        location: draft.location,
        roleTagline: 'Staff Software Engineer',
      ),
      experience: [
        for (var i = 0; i < draft.experience.length; i++)
          ResolvedExperienceEntry(
            sourceBlockId: i,
            role: draft.experience[i].role,
            company: draft.experience[i].company,
            startDate: draft.experience[i].startDate,
            endDate: draft.experience[i].endDate,
            bullets: draft.experience[i].bullets,
          ),
      ],
      education: [
        for (var i = 0; i < draft.education.length; i++)
          ResolvedEducationEntry(
            sourceBlockId: i,
            institution: draft.education[i].institution,
            degree: draft.education[i].degree,
            fieldOfStudy: draft.education[i].fieldOfStudy,
            startDate: draft.education[i].startDate,
            endDate: draft.education[i].endDate,
          ),
      ],
      customSections: [
        for (var i = 0; i < draft.customSections.length; i++)
          ResolvedCustomSectionEntry(
            sourceBlockId: i,
            title: draft.customSections[i].title,
            entries: draft.customSections[i].entries,
          ),
      ],
    );

    const renderer = ResumeTemplateRenderer();
    final outDir = Directory(_outputDir)..createSync(recursive: true);

    const specIdsToFileNames = {
      'classic-single-column-warm': 'pagination_stress_classic_many_custom_sections.pdf',
      'two-column-right-warm': 'pagination_stress_balanced_two_column_many_custom_sections.pdf',
    };

    for (final entry in specIdsToFileNames.entries) {
      final spec = ResumeTemplateCatalog.specById(entry.key);
      final bytes = await renderer.render(snapshot, spec);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

      final file = File('${outDir.path}/${entry.value}');
      await file.writeAsBytes(bytes);
      // ignore: avoid_print
      print('Wrote ${file.path} (${bytes.length} bytes) - ${spec.displayName}');
    }
  });
}
