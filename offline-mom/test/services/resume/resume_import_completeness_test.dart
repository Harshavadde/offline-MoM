// Reliability-overhaul pass, Phase 1/20/21: proves ResumeImportParser is
// genuinely lossless across a range of realistic resume shapes, using the
// machine-checkable ResumeImportCompletenessReport rather than eyeballing
// entry counts by hand. Every dataset here is deliberately distinct from
// resume_import_parser_test.dart's per-bug regression fixtures - these are
// whole-resume, end-to-end acceptance datasets (1/2/4+ experiences,
// multi-project entries, custom sections, reordered sections, missing
// sections, wrapped bullets, links, Indian locations, mixed date formats).
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';

void main() {
  const parser = ResumeImportParser();

  group('ResumeImportCompletenessReport - isComplete invariant', () {
    test('a single-experience resume is reported complete with 1 experience', () {
      final draft = parser.parse(
        'Jane Doe\n'
        'jane@example.com\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        'Jan 2022 - Present\n'
        '- Built the thing\n'
        '- Shipped the other thing\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      final experience = draft.completeness.sections.firstWhere((s) => s.label == 'Experience');
      expect(experience.sourceCount, 1);
      expect(experience.importedCount, 1);
      expect(draft.experience, hasLength(1));
    });

    test('a two-experience resume imports both entries, reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        'Jan 2022 - Present\n'
        '- Did a thing\n\n'
        'Junior Developer - Beta Inc\n'
        'Jun 2020 - Dec 2021\n'
        '- Did an earlier thing\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      expect(draft.experience, hasLength(2));
      expect(draft.experience.map((e) => e.company), containsAll(['Acme Corp', 'Beta Inc']));
    });

    // Phase 20: "Create a regression resume with at least 4 employment
    // entries... 4 imported, 4 displayed in editor, 4 available to
    // templates, 4 present in generated PDF. Do not stop at one or two
    // entries." This test covers the import side of that chain; the
    // renderer/PDF side is covered separately by the acceptance-matrix
    // and content-completeness tests.
    test('a 4+ experience resume imports every single entry, reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Staff Engineer - Fifth Co\n'
        'Mar 2023 - Present\n'
        '- Led the platform team\n\n'
        'Senior Engineer - Fourth Co\n'
        'Jan 2021 - Feb 2023\n'
        '- Owned the payments service\n\n'
        'Software Engineer - Third Co\n'
        '2019 - 2020\n'
        '- Built internal tools\n\n'
        'Software Engineer - Second Co\n'
        '2017 - 2019\n'
        '- Shipped the mobile app\n\n'
        'Junior Developer - First Co\n'
        '2015 - 2017\n'
        '- Learned the ropes\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      expect(draft.experience, hasLength(5));
      expect(
        draft.experience.map((e) => e.company),
        containsAll(['Fifth Co', 'Fourth Co', 'Third Co', 'Second Co', 'First Co']),
      );
    });

    test('multiple projects listed under Projects all import, reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'PROJECTS\n\n'
        'Offline Notes App\n'
        '- Built a local-first notes app\n'
        '- github.com/janedoe/notes\n\n'
        'Weather Dashboard\n'
        '- A small React weather dashboard\n\n'
        'CLI Task Runner\n'
        '- A Rust CLI for running dev tasks\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      expect(draft.projects, hasLength(3));
      expect(
        draft.projects.map((p) => p.name),
        containsAll(['Offline Notes App', 'Weather Dashboard', 'CLI Task Runner']),
      );
    });

    test('custom (non-standard) sections all import as titled sections, reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        '2020 - 2021\n'
        '- Did a thing\n\n'
        'AWARDS\n\n'
        'Employee of the Year, 2021\n'
        'Top Performer Award, 2020\n\n'
        'PUBLICATIONS\n\n'
        'Offline-First Architecture Patterns, 2022\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      final customSections = draft.completeness.sections.firstWhere((s) => s.label == 'Custom sections');
      expect(customSections.sourceCount, 2);
      expect(customSections.importedCount, 2);
      expect(draft.customSections.map((s) => s.title), containsAll(['AWARDS', 'PUBLICATIONS']));
    });

    test('sections in a non-standard order (Education before Experience) still all import', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EDUCATION\n\n'
        'B.Tech Computer Science\n'
        'State University\n'
        '2016 - 2020\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        '2020 - 2021\n'
        '- Did a thing\n\n'
        'SKILLS\n\n'
        'Python, Dart, SQL\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      expect(draft.education, hasLength(1));
      expect(draft.experience, hasLength(1));
      expect(draft.skills, hasLength(3));
    });

    test('a resume missing optional sections (no Education, no Projects) is still reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        '2020 - 2021\n'
        '- Did a thing\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      final education = draft.completeness.sections.firstWhere((s) => s.label == 'Education');
      expect(education.sourceCount, 0);
      expect(education.importedCount, 0);
      expect(draft.education, isEmpty);
    });

    test('a long, word-wrapped bullet imports as one bullet, not several fragments, reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        '2020 - 2021\n'
        '- Developed and maintained Python-based data pipelines to extract, validate, and\n'
        'deploy multilingual educational content to AWS S3, reducing manual QA effort by ~70%\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      expect(draft.experience, hasLength(1));
      expect(draft.experience.single.bullets, hasLength(1));
      expect(draft.experience.single.bullets.single, contains('reducing manual QA effort by ~70%'));
    });

    test(
      'links appearing anywhere (header, custom section, unclassified) are all reported complete',
      () {
        final draft = parser.parse(
          'Jane Doe\n'
          'linkedin.com/in/janedoe | github.com/janedoe\n\n'
          'EXPERIENCE\n\n'
          'Software Engineer - Acme Corp\n'
          '2020 - 2021\n'
          '- Did a thing\n\n'
          'LINKS\n\n'
          'Stack Overflow: stackoverflow.com/users/12345/janedoe\n'
          'Portfolio: https://janedoe.dev\n',
        );

        expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
        final links = draft.completeness.sections.firstWhere((s) => s.label == 'Links');
        expect(links.sourceCount, 4);
        expect(links.importedCount, 4);
        expect(
          draft.links.map((l) => l.label),
          containsAll(['LinkedIn', 'GitHub', 'Stack Overflow', 'janedoe.dev']),
        );
      },
    );

    test('Indian "City, State" locations are detected and reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n'
        'Hyderabad, Telangana\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        '2020 - 2021\n'
        '- Did a thing\n',
      );

      expect(draft.location, 'Hyderabad, Telangana');
      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
    });

    test('mixed date formats (bare years, month+year, Present) all import, reported complete', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Staff Engineer - Fourth Co\n'
        'March 2023 - Present\n'
        '- Bare month+year, open-ended\n\n'
        'Senior Engineer - Third Co\n'
        '2021 - 2023\n'
        '- Bare years\n\n'
        'Engineer - Second Co\n'
        'Jan 2019 - Dec 2020\n'
        '- Month+year on both sides\n\n'
        'Junior Engineer - First Co\n'
        '2017 - 2019\n'
        '- Bare years again\n',
      );

      expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
      expect(draft.experience, hasLength(4));
      expect(draft.experience.map((e) => e.endDate), containsAll([null, '2023', '2020', '2019']));
    });

    test(
      'Part I (import completeness stress pass): two roles at the same company are imported '
      'as two distinct entries, in document order, reported complete',
      () {
        final draft = parser.parse(
          'Jane Doe\n\n'
          'EXPERIENCE\n\n'
          'Senior Engineer - Acme Corp\n'
          '2022 - Present\n'
          '- Led the platform team\n\n'
          'Software Engineer - Acme Corp\n'
          '2019 - 2022\n'
          '- Shipped the payments pipeline\n',
        );

        expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
        expect(draft.experience, hasLength(2));
        expect(draft.experience.map((e) => e.company), ['Acme Corp', 'Acme Corp']);
        expect(draft.experience.map((e) => e.role), ['Senior Engineer', 'Software Engineer']);
        expect(draft.experience[0].bullets, ['Led the platform team']);
        expect(draft.experience[1].bullets, ['Shipped the payments pipeline']);
      },
    );

    test(
      'Part I (import completeness stress pass): named sub-projects nested under a role '
      '(D-M9-01) are reported complete - not lost, not double-counted against the parent '
      'Experience entry',
      () {
        final draft = parser.parse(
          'Jane Doe\n\n'
          'EXPERIENCE\n\n'
          'Software Engineer - Acme Corp\n'
          '2022 - Present\n'
          'SciLab (Web & Android) — Godot, AWS S3\n'
          '- Built the mobile client.\n'
          'ByHeart — Flashcards app\n'
          '- Built the spaced-repetition engine.\n',
        );

        expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
        expect(draft.experience, hasLength(1));
        final entry = draft.experience.single;
        expect(entry.subProjects, hasLength(2));
        expect(entry.subProjects.map((s) => s.name), ['SciLab (Web & Android) — Godot, AWS S3', 'ByHeart — Flashcards app']);
      },
    );

    test(
      'Part I (import completeness stress pass): an experience entry with role/company/dates '
      'but no bullets at all is reported complete, not silently dropped',
      () {
        final draft = parser.parse(
          'Jane Doe\n\n'
          'EXPERIENCE\n\n'
          'Software Engineer - Acme Corp\n'
          '2020 - 2021\n\n'
          'EDUCATION\n\n'
          'B.Tech Computer Science\n'
          'State University\n'
          '2016 - 2020\n',
        );

        expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
        expect(draft.experience, hasLength(1));
        expect(draft.experience.single.role, 'Software Engineer');
        expect(draft.experience.single.bullets, isEmpty);
      },
    );

    test(
      'Part I (import completeness stress pass): curated non-Indian international locations '
      '(UK, Canada, Australia, Singapore, UAE) are detected and reported complete',
      () {
        for (final line in [
          'London, UK',
          'Toronto, Canada',
          'Sydney, Australia',
          'Singapore, Singapore',
          'Dubai, UAE',
        ]) {
          final draft = parser.parse(
            'Jane Doe\n$line\n\n'
            'EXPERIENCE\n\n'
            'Software Engineer - Acme Corp\n'
            '2020 - 2021\n'
            '- Did a thing\n',
          );

          expect(draft.location, line, reason: line);
          expect(draft.completeness.isComplete, isTrue, reason: '$line: ${draft.completeness.toReportString()}');
        }
      },
    );

    test(
      'Part I (import completeness stress pass): a mix of bullet marker styles (-, *, •, '
      'numbered) in one entry all import as distinct bullets, in order, reported complete',
      () {
        final draft = parser.parse(
          'Jane Doe\n\n'
          'EXPERIENCE\n\n'
          'Software Engineer - Acme Corp\n'
          '2020 - 2021\n'
          '- Dash bullet.\n'
          '* Asterisk bullet.\n'
          '• Filled-circle bullet.\n'
          '1. Numbered bullet.\n',
        );

        expect(draft.completeness.isComplete, isTrue, reason: draft.completeness.toReportString());
        expect(draft.experience.single.bullets, [
          'Dash bullet.',
          'Asterisk bullet.',
          'Filled-circle bullet.',
          'Numbered bullet.',
        ]);
      },
    );

    test('an empty document produces a vacuously complete (all-zero) report, never throws', () {
      final draft = parser.parse('');
      expect(draft.completeness.isComplete, isTrue);
      expect(draft.completeness.totalMissing, 0);
    });

    test('toReportString() renders a readable Source/Imported/Missing summary', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Software Engineer - Acme Corp\n'
        '2020 - 2021\n'
        '- Did a thing\n',
      );
      final report = draft.completeness.toReportString();
      expect(report, contains('Source:'));
      expect(report, contains('Imported:'));
      expect(report, contains('Missing: 0'));
      expect(report, contains('Experience = 1'));
    });
  });
}
