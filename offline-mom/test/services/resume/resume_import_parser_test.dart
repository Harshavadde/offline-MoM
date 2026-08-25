// Tests ResumeImportParser (lib/services/resume/resume_import_parser.dart) -
// a pure, offline, deterministic text->draft heuristic with no I/O and no
// AI model of any kind. Mirrors chat_export_service_test.dart's style: a
// const service instance, plain string fixtures, no database.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_link.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';

void main() {
  const parser = ResumeImportParser();

  group('profile/contact detection', () {
    test('detects a name-like first line, email, and phone', () {
      final draft = parser.parse(
        'Jane Doe\n'
        'jane.doe@example.com | 555-123-4567\n'
        'Austin, TX\n',
      );

      expect(draft.fullName, 'Jane Doe');
      expect(draft.email, 'jane.doe@example.com');
      expect(draft.phone, isNotNull);
    });

    test('does not guess a name from a line that does not look like one', () {
      final draft = parser.parse('RESUME OF A CANDIDATE\nSome text.\n');
      expect(draft.fullName, isNull);
    });

    test(
      'detects the name even with a trailing parenthetical role tagline on the same line - '
      'real-device beta bug: the header line "VADDE HARSHAVARDHAN (Python Developer)" '
      'previously matched no name pattern at all, and _detectName gave up after that one '
      'line, so the name was completely absent from the imported resume',
      () {
        final draft = parser.parse('VADDE HARSHAVARDHAN (Python Developer)\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n');
        expect(draft.fullName, 'VADDE HARSHAVARDHAN');
      },
    );

    test(
      'tries every preamble line for a name, not just the first eligible one - a first '
      'line that fails the name pattern no longer permanently gives up',
      () {
        final draft = parser.parse('resume of jane doe\nJane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n');
        expect(draft.fullName, 'Jane Doe');
      },
    );

    test('does not fabricate an email/phone when none is present', () {
      final draft = parser.parse('Jane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n');
      expect(draft.email, isNull);
      expect(draft.phone, isNull);
    });

    test(
      'Part I (import completeness stress-testing pass): a single "|"-joined contact line whose '
      'every segment (location, email, phone) was individually extracted is not ALSO flagged as '
      'unclassified content still needing manual review - confirmed reproducible with this '
      'codebase\'s own existing Harshavardhan header fixture, not a hypothetical shape',
      () {
        final draft = parser.parse(
          'Jane Doe\n'
          'London, UK | jane.doe@example.com | (206) 555-0113\n\n'
          'EXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n',
        );

        expect(draft.location, 'London, UK');
        expect(draft.email, 'jane.doe@example.com');
        expect(draft.phone, '(206) 555-0113');
        expect(
          draft.unclassifiedText,
          isNot(contains('London, UK | jane.doe@example.com | (206) 555-0113')),
        );
      },
    );

    test(
      'Part I: a "|"-joined contact line with one genuinely unrecognized segment alongside '
      'recognized ones still falls through to unclassifiedText, unchanged - only a line where '
      'EVERY segment was accounted for is skipped',
      () {
        final draft = parser.parse(
          'Jane Doe\n'
          'jane.doe@example.com | Aspiring Backend Engineer\n\n'
          'EXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n',
        );

        expect(
          draft.unclassifiedText,
          contains('jane.doe@example.com | Aspiring Backend Engineer'),
        );
      },
    );

    test('detects and labels LinkedIn/GitHub links found anywhere in the text', () {
      final draft = parser.parse(
        'Jane Doe\n'
        'https://linkedin.com/in/janedoe https://github.com/janedoe\n',
      );

      expect(draft.links, contains(isA<ResumeLink>().having((l) => l.label, 'label', 'LinkedIn')));
      expect(draft.links, contains(isA<ResumeLink>().having((l) => l.label, 'label', 'GitHub')));
    });

    test(
      'also detects a bare github.com/linkedin.com link with no "http(s)://" or "www." prefix - '
      'real-device beta fix: a real resume\'s header used "github.com/Harshavadde" bare, which '
      'previously matched no URL pattern at all and was silently absent from the imported resume, '
      'even though a "www."-prefixed LinkedIn link on the very same line was preserved',
      () {
        final draft = parser.parse(
          'Jane Doe\n'
          'Hyderabad, TS | jane@example.com | www.linkedin.com/in/janedoe | github.com/janedoe\n',
        );

        expect(draft.links, contains(isA<ResumeLink>().having((l) => l.label, 'label', 'LinkedIn')));
        expect(draft.links, contains(isA<ResumeLink>().having((l) => l.label, 'label', 'GitHub')));
      },
    );

    test(
      'does not pull a project\'s own repo link into the profile links - real-device beta fix: '
      'a project-specific "GitHub: github.com/x/y" line (already captured as that project\'s own '
      'link by project structuring) was previously ALSO added here since link extraction scanned '
      'the whole document, rendering the same GitHub link twice - once correctly on the project, '
      'once wrongly in the header',
      () {
        final draft = parser.parse(
          'Jane Doe\n'
          'jane@example.com | github.com/janedoe\n\n'
          'PROJECTS\n\n'
          'Side Project — FastAPI\n'
          'GitHub: github.com/janedoe/side-project\n'
          '- Built a thing.\n',
        );

        final githubLinks = draft.links.where((l) => l.label == 'GitHub');
        expect(githubLinks, hasLength(1));
        expect(githubLinks.single.url, 'github.com/janedoe');
        expect(draft.projects.single.link, 'github.com/janedoe/side-project');
      },
    );
  });

  group('location detection (Physical-Mobile-First Validation phase)', () {
    test('detects a "City, ST" preamble line', () {
      final draft = parser.parse(
        'Jane Doe\n'
        'jane.doe@example.com\n'
        'Austin, TX\n',
      );

      expect(draft.location, 'Austin, TX');
      expect(draft.unclassifiedText, isNot(contains('Austin, TX')));
    });

    test('detects a "City, ST ZIP" preamble line', () {
      final draft = parser.parse('Jane Doe\njane.doe@example.com\nAustin, TX 78701\n');
      expect(draft.location, 'Austin, TX 78701');
    });

    test('is not confused by position - still finds the location line when contact info comes first', () {
      final draft = parser.parse(
        'Jane Doe\n'
        'jane.doe@example.com | (206) 555-0113\n'
        'https://linkedin.com/in/janedoe\n'
        'Seattle, WA\n',
      );

      expect(draft.location, 'Seattle, WA');
    });

    test('does not fabricate a location when no "City, ST"-shaped line is present - falls through to '
        'unclassifiedText like any other unrecognized preamble content, never guessed', () {
      final draft = parser.parse('Jane Doe\njane.doe@example.com\nBackend Engineer\n');
      expect(draft.location, isNull);
      expect(draft.unclassifiedText, contains('Backend Engineer'));
    });

    test('does not misread a role tagline as a location', () {
      final draft = parser.parse('Jane Doe\nSenior Backend Engineer\njane.doe@example.com\n');
      expect(draft.location, isNull);
    });

    test('does not misread an unlisted spelled-out state/country as a location - deliberately '
        'narrow, a curated closed list, disclosed via unclassifiedText rather than guessed at', () {
      final draft = parser.parse('Jane Doe\njane.doe@example.com\nAustin, Texas\n');
      expect(draft.location, isNull);
      expect(draft.unclassifiedText, contains('Austin, Texas'));
    });

    test(
      'recognizes "City, Indian State" and "City, Indian State, Country" formats - real-device beta '
      'fix: "Hyderabad, Telangana" (a real resume\'s actual location line) previously matched no '
      'location pattern at all (India has no 2-letter-state-code convention) and was silently absent',
      () {
        for (final line in [
          'Hyderabad, Telangana',
          'Hyderabad, Telangana, India',
          'Bengaluru, Karnataka',
          'Bangalore, Karnataka',
          'Chennai, Tamil Nadu',
          'Pune, Maharashtra',
          'Mumbai, Maharashtra',
        ]) {
          final draft = parser.parse('Jane Doe\njane.doe@example.com\n$line\n');
          expect(draft.location, line, reason: line);
        }
      },
    );

    test('recognizes a bare "City, Country" line for the small, curated country list', () {
      final draft = parser.parse('Jane Doe\njane.doe@example.com\nDelhi, India\n');
      expect(draft.location, 'Delhi, India');
    });

    test(
      'recognizes a location embedded as one "|"-joined segment of a combined contact line - '
      'real-device beta fix: a real resume\'s header was one single line '
      '"Hyderabad, Telangana | email | phone | links", not a dedicated location line, so the '
      'whole-line-anchored location patterns never matched it at all',
      () {
        final draft = parser.parse(
          'VADDE HARSHAVARDHAN\n'
          'Hyderabad, Telangana | iamharsha.vadde@gmail.com | 9035759795 | www.linkedin.com/in/x\n',
        );
        expect(draft.location, 'Hyderabad, Telangana');
      },
    );
  });

  group('section detection', () {
    test('recognizes common section header variants case-insensitively', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'WORK EXPERIENCE\n\n'
        'Engineer - Acme Corp\n2020 - 2022\n- Did the thing.\n\n'
        'education\n\n'
        'B.S. Computer Science - State University\n2016 - 2020\n\n'
        'Skills\n\nDart, Flutter, SQL\n',
      );

      expect(draft.experience, hasLength(1));
      expect(draft.education, hasLength(1));
      expect(draft.skills.map((s) => s.name), containsAll(['Dart', 'Flutter', 'SQL']));
    });

    test('warns when no sections could be detected at all', () {
      final draft = parser.parse('Just a plain paragraph with no structure whatsoever.');
      expect(draft.warnings, isNotEmpty);
      expect(draft.experience, isEmpty);
    });

    test('Physical-Mobile-First Validation phase: a Summary/Objective section is imported as a '
        '"Summary" custom section (reusing the existing custom-section mechanism, not a new field) '
        '- it survives confirmImport for real now, unlike unclassifiedText which is never persisted', () {
      final draft = parser.parse(
        'Jane Doe\n\nSUMMARY\n\nResults-driven engineer with 5 years of experience.\n',
      );

      expect(draft.customSections, hasLength(1));
      expect(draft.customSections.single.title, 'Summary');
      expect(draft.customSections.single.entries, ['Results-driven engineer with 5 years of experience.']);
      expect(draft.unclassifiedText, isNot(contains('Results-driven engineer with 5 years of experience.')));
    });

    test('an "Objective" heading collapses into the same "Summary" custom section title as '
        '"Summary" would - this parser already treats them as the same section kind, so a single '
        'fixed title is used rather than trying to recover which literal heading the document used',
        () {
      final draft = parser.parse('Jane Doe\n\nOBJECTIVE\n\nSeeking a senior backend role.\n');

      expect(draft.customSections, hasLength(1));
      expect(draft.customSections.single.title, 'Summary');
    });

    test(
      'a multi-line Summary that word-wraps across several extracted lines is joined into '
      'one flowing paragraph entry - real-device beta fix: previously each wrapped line '
      'became its own bullet fragment, which rendered as several disconnected bullet '
      'points instead of one paragraph',
      () {
        final draft = parser.parse(
          'Jane Doe\n\nSUMMARY\n\n'
          'Results-driven engineer with 5 years of experience.\n'
          'Specializes in distributed systems and developer tooling.\n',
        );

        expect(draft.customSections.single.entries, [
          'Results-driven engineer with 5 years of experience. '
              'Specializes in distributed systems and developer tooling.',
        ]);
      },
    );

    test(
      'a Summary that genuinely uses its own bullet markers keeps each item as a separate '
      'entry, not joined into one run-on paragraph',
      () {
        final draft = parser.parse(
          'Jane Doe\n\nSUMMARY\n\n'
          '- Led cross-functional teams of 8+ engineers.\n'
          '- Shipped 3 major platform migrations with zero downtime.\n',
        );

        expect(draft.customSections.single.entries, [
          'Led cross-functional teams of 8+ engineers.',
          'Shipped 3 major platform migrations with zero downtime.',
        ]);
      },
    );
  });

  group('Experience structuring', () {
    test('a well-formed entry with role, company, dates, and bullets is fully structured', () {
      final draft = parser.parse(
        'EXPERIENCE\n\n'
        'Senior Engineer - Acme Corp\n'
        '2020 - 2022\n'
        '- Shipped the payments pipeline.\n'
        '- Mentored two engineers.\n',
      );

      expect(draft.experience, hasLength(1));
      final entry = draft.experience.single;
      expect(entry.role, 'Senior Engineer');
      expect(entry.company, 'Acme Corp');
      expect(entry.startDate, '2020');
      expect(entry.endDate, '2022');
      expect(entry.bullets, ['Shipped the payments pipeline.', 'Mentored two engineers.']);
    });

    test('an open-ended "Present" range leaves endDate null, not a fabricated date', () {
      final draft = parser.parse('EXPERIENCE\n\nEngineer - Acme\n2021 - Present\n');
      expect(draft.experience.single.endDate, isNull);
    });

    test(
      'a title, "Month YYYY" date range, and location all combined on ONE line - a '
      'real-device beta bug: this extremely common right-aligned-date resume layout '
      'previously made the date match cover well under half the line, which caused '
      'the entire entry (and every other entry using the same layout) to be dropped to '
      'unclassifiedText - not merely mis-parsed, entirely absent from the imported resume',
      () {
        final draft = parser.parse(
          'EXPERIENCE\n\n'
          'Software Engineer | Pranakshit IT Solutions December 2025 - Present | Hyderabad, India\n'
          '- Developed and maintained Python-based data pipelines.\n'
          '- Designed database schemas and analytics pipelines.\n',
        );

        expect(draft.experience, hasLength(1));
        final entry = draft.experience.single;
        expect(entry.role, 'Software Engineer');
        expect(entry.company, 'Pranakshit IT Solutions');
        expect(entry.startDate, '2025');
        expect(entry.endDate, isNull);
        expect(entry.location, 'Hyderabad, India');
        expect(entry.bullets, [
          'Developed and maintained Python-based data pipelines.',
          'Designed database schemas and analytics pipelines.',
        ]);
      },
    );

    test('a combined title+date line using a bare "YYYY - YYYY" range (no month name) still structures', () {
      final draft = parser.parse(
        'EXPERIENCE\n\nSoftware Developer Intern | Acme Analytics June 2022 - November 2022 | Remote\n'
        '- Built dashboards.\n',
      );

      expect(draft.experience, hasLength(1));
      final entry = draft.experience.single;
      expect(entry.role, 'Software Developer Intern');
      expect(entry.company, 'Acme Analytics');
      expect(entry.startDate, '2022');
      expect(entry.endDate, '2022');
      expect(entry.location, 'Remote');
      expect(entry.bullets, ['Built dashboards.']);
    });

    test(
      'a non-bullet line nested under an entry (e.g. an italic sub-project header with no '
      'bullet marker of its own) is structured as a named sub-project rather than silently '
      'dropped or flattened into the parent entry\'s own bullets - migration v20, '
      'reliability-overhaul pass (Resume -> Experience -> Project -> Project bullets)',
      () {
        final draft = parser.parse(
          'EXPERIENCE\n\n'
          'Software Engineer - Acme Corp\n2022 - Present\n'
          'SubProject (Web & Android) — Godot, AWS S3\n'
          '- Built the sub-project.\n',
        );

        expect(draft.experience, hasLength(1));
        final entry = draft.experience.single;
        // The sub-project header is no longer flattened into the parent
        // entry's own bullets - it is structurally distinct content, so
        // the parent entry's own bullets stay empty here (it has none of
        // its own, only a nested sub-project).
        expect(entry.bullets, isEmpty);
        expect(entry.subProjects, hasLength(1));
        expect(entry.subProjects.single.name, 'SubProject (Web & Android) — Godot, AWS S3');
        expect(entry.subProjects.single.bullets, ['Built the sub-project.']);
      },
    );

    test(
      'a bullet that word-wraps across two physical lines (no bullet marker on the second '
      'line, no trailing punctuation on the first) is rejoined into one bullet, not left as '
      'two disconnected fragments - real-device beta fix: this exact pattern, multiplied '
      'across a real resume\'s bullet-heavy entry, inflated one entry to 29 "bullets" and '
      'separately triggered a Balanced Two-Column pagination crash (PdfTooBigPageException)',
      () {
        final draft = parser.parse(
          'EXPERIENCE\n\n'
          'Software Engineer - Acme Corp\n2022 - Present\n'
          '- Developed and maintained Python-based data pipelines to extract, validate, and deploy content to\n'
          'AWS S3, reducing manual QA effort by ~70% through Linux CLI automation.\n'
          '- A second, short, self-contained bullet.\n',
        );

        expect(draft.experience.single.bullets, [
          'Developed and maintained Python-based data pipelines to extract, validate, and deploy content to '
              'AWS S3, reducing manual QA effort by ~70% through Linux CLI automation.',
          'A second, short, self-contained bullet.',
        ]);
      },
    );

    test('preserves the order of multiple entries and their bullets', () {
      final draft = parser.parse(
        'EXPERIENCE\n\n'
        'First Role - First Co\n2018 - 2019\n- Bullet A.\n- Bullet B.\n\n'
        'Second Role - Second Co\n2019 - 2020\n- Bullet C.\n',
      );

      expect(draft.experience, hasLength(2));
      expect(draft.experience[0].role, 'First Role');
      expect(draft.experience[1].role, 'Second Role');
      expect(draft.experience[0].bullets, ['Bullet A.', 'Bullet B.']);
    });

    test('an entry with no discernible role/company split is never forced into '
        'a structured block with invented values - it is left unclassified', () {
      final draft = parser.parse(
        'EXPERIENCE\n\n'
        'This is just a paragraph of prose with no clear title line at all '
        'and no separators to split on whatsoever in this sentence.\n',
      );

      expect(draft.experience, isEmpty);
      expect(draft.unclassifiedText, isNotEmpty);
      expect(draft.warnings.any((w) => w.contains('Experience')), isTrue);
    });

    test('an entry with a role/company split but no date is left unclassified '
        'rather than inventing a start date', () {
      final draft = parser.parse('EXPERIENCE\n\nEngineer - Acme Corp\n- Did some work.\n');
      expect(draft.experience, isEmpty);
      expect(draft.unclassifiedText, isNotEmpty);
    });
  });

  group('Education structuring', () {
    test('splits a well-formed entry into degree/institution/dates', () {
      final draft = parser.parse(
        'EDUCATION\n\n'
        'B.S. Computer Science - State University\n'
        '2016 - 2020\n'
        'GPA 3.9\n',
      );

      expect(draft.education, hasLength(1));
      final entry = draft.education.single;
      expect(entry.degree, 'B.S. Computer Science');
      expect(entry.institution, 'State University');
      expect(entry.startDate, '2016');
      expect(entry.endDate, '2020');
      expect(entry.details, contains('GPA 3.9'));
    });

    test(
      'an institution+"Month YYYY - Month YYYY"+location combined on ONE line - real-device '
      'beta bug: the whole EDUCATION section was silently lost with a real resume using '
      'this layout, since the previous date pattern only ever recognized a bare year and '
      'the whole-line-coverage heuristic rejected even that once matched',
      () {
        final draft = parser.parse(
          'EDUCATION\n\n'
          'Sri Venkateshwara College of Engineering August 2020 - June 2024 | Tirupathi, India\n'
          'Bachelor of Technology - Electrical and Electronics Engineering\n',
        );

        expect(draft.education, hasLength(1));
        final entry = draft.education.single;
        expect(entry.institution, 'Sri Venkateshwara College of Engineering');
        expect(entry.startDate, '2020');
        expect(entry.endDate, '2024');
        expect(entry.details, contains('Tirupathi, India'));
      },
    );

    test('extracts a field of study from "Degree in Field" phrasing', () {
      final draft = parser.parse(
        'EDUCATION\n\nBachelor of Science in Data Science - Tech University\n2018 - 2022\n',
      );

      final entry = draft.education.single;
      expect(entry.fieldOfStudy, 'Data Science');
    });
  });

  group('Projects structuring', () {
    test('a name-only entry is structured with empty bullets/link, never invented', () {
      final draft = parser.parse('PROJECTS\n\nOffline Notes App\n');
      expect(draft.projects, hasLength(1));
      expect(draft.projects.single.name, 'Offline Notes App');
      expect(draft.projects.single.link, isNull);
      expect(draft.projects.single.bullets, isEmpty);
    });

    test('captures a link and bullets alongside the name', () {
      final draft = parser.parse(
        'PROJECTS\n\n'
        'Offline Notes App\n'
        'https://github.com/janedoe/notes\n'
        '- Built a fully offline sync engine.\n',
      );

      final entry = draft.projects.single;
      expect(entry.link, 'https://github.com/janedoe/notes');
      expect(entry.bullets, ['Built a fully offline sync engine.']);
    });

    test(
      'a "GitHub: <url>" labeled link line does not also survive as a duplicate bullet - '
      'real-device beta fix: only an exact bare-URL line was excluded before, so this common '
      'real-resume convention (a label prefix on the link line) rendered the project\'s own '
      'link twice - once as its dedicated link field, once again as a plain bullet',
      () {
        final draft = parser.parse(
          'PROJECTS\n\n'
          'AI Medical Emergency System\n'
          'GitHub: github.com/janedoe/ai-med\n'
          '- Built a full-stack GenAI healthcare platform.\n',
        );

        final entry = draft.projects.single;
        expect(entry.link, 'github.com/janedoe/ai-med');
        expect(entry.bullets, ['Built a full-stack GenAI healthcare platform.']);
      },
    );

    test('an entry with only bullet lines and no name line is left unclassified '
        'rather than inventing a project name', () {
      final draft = parser.parse('PROJECTS\n\n- Just a bullet with no name line above it.\n');
      expect(draft.projects, isEmpty);
      expect(draft.unclassifiedText, isNotEmpty);
    });

    test('preserves every project - 1, 3, 5, and 10 consecutive entries, none '
        'lost or truncated (beta data-fidelity requirement)', () {
      for (final count in [1, 3, 5, 10]) {
        final body = StringBuffer('PROJECTS\n\n');
        for (var i = 1; i <= count; i++) {
          body.writeln('Project Number $i');
          body.writeln('- Bullet for project $i.');
          body.writeln();
        }
        final draft = parser.parse(body.toString());
        expect(draft.projects, hasLength(count), reason: 'count=$count');
        for (var i = 1; i <= count; i++) {
          expect(draft.projects[i - 1].name, 'Project Number $i', reason: 'count=$count');
        }
      }
    });
  });

  group('custom/generic section detection', () {
    test('preserves a section with no dedicated typed field as a titled '
        'custom section instead of merging it into the previous section', () {
      final draft = parser.parse(
        'Jane Doe\n\n'
        'EXPERIENCE\n\n'
        'Engineer - Acme Corp\n2020 - 2022\n- Did the thing.\n\n'
        'AWARDS\n\n'
        'Employee of the Year, 2021\n'
        'Top Performer Award, 2020\n',
      );

      expect(draft.customSections, hasLength(1));
      final section = draft.customSections.single;
      expect(section.title, 'AWARDS');
      // Also a regression guard for the wrapped-continuation-join fix
      // (real-device beta bug): neither line here has a bullet marker or
      // trailing punctuation, and an earlier version of that fix wrongly
      // merged them into one run-on entry, "Employee of the Year, 2021
      // Top Performer Award, 2020" - joining is only ever safe for a line
      // that follows a genuine bullet-marked item, never a standalone,
      // unmarked one-item-per-line section like this one.
      expect(section.entries, ['Employee of the Year, 2021', 'Top Performer Award, 2020']);
      // The known Experience section above stays intact - its content was
      // not contaminated by the unrecognized header that followed it.
      expect(draft.experience, hasLength(1));
    });

    test('preserves multiple distinct custom sections, each with its own title', () {
      final draft = parser.parse(
        'EXPERIENCE\n\n'
        'Engineer - Acme Corp\n2020 - 2022\n- Did the thing.\n\n'
        'PUBLICATIONS\n\n'
        'A Paper About Something\n\n'
        'VOLUNTEER EXPERIENCE\n\n'
        'Local Food Bank, 2019\n',
      );

      expect(draft.customSections.map((s) => s.title), ['PUBLICATIONS', 'VOLUNTEER EXPERIENCE']);
    });

    test('an all-caps custom header with connector words is also recognized', () {
      final draft = parser.parse(
        'EXPERIENCE\n\n'
        'Engineer - Acme Corp\n2020 - 2022\n- Did the thing.\n\n'
        'AWARDS AND RECOGNITION\n\n'
        'Employee of the Year\n',
      );

      expect(draft.customSections.single.title, 'AWARDS AND RECOGNITION');
    });

    test('does not mistake an entry title line ("Role - Company") or a bare '
        'project/certification name inside an already-open known section for '
        'a new custom section header', () {
      final draft = parser.parse(
        'EXPERIENCE\n\n'
        'Engineer - Acme Corp\n2020 - 2022\n- Did the thing.\n\n'
        'PROJECTS\n\n'
        'Offline Notes App\n- Built a fully offline sync engine.\n\n'
        'CERTIFICATIONS\n\n'
        'AWS Certified Developer - Amazon\nIssued 2023\n',
      );

      expect(draft.customSections, isEmpty);
      expect(draft.experience, hasLength(1));
      expect(draft.projects, hasLength(1));
      expect(draft.certifications, hasLength(1));
    });

    test('never applies custom-header detection before the first known section '
        '- the candidate\'s own name is not misread as a section header', () {
      final draft = parser.parse(
        'Arjun Mehta\n'
        'arjun@example.com\n\n'
        'EXPERIENCE\n\n'
        'Engineer - Acme Corp\n2020 - 2022\n- Did the thing.\n',
      );

      expect(draft.fullName, 'Arjun Mehta');
      expect(draft.customSections, isEmpty);
    });

    test('a header with nothing but blank lines under it contributes no empty section', () {
      final draft = parser.parse(
        'EXPERIENCE\n\n'
        'Engineer - Acme Corp\n2020 - 2022\n- Did the thing.\n\n'
        'LANGUAGES\n\n',
      );

      expect(draft.customSections, isEmpty);
    });
  });

  group('Certifications structuring', () {
    test('splits name/issuer and captures an issued date', () {
      final draft = parser.parse(
        'CERTIFICATIONS\n\nAWS Certified Developer - Amazon\nIssued 2023\n',
      );

      final entry = draft.certifications.single;
      expect(entry.name, 'AWS Certified Developer');
      expect(entry.issuer, 'Amazon');
      expect(entry.issuedDate, '2023');
    });

    test('an entry with no name/issuer split is left unclassified', () {
      final draft = parser.parse('CERTIFICATIONS\n\nJust a certification name with no issuer split.\n');
      expect(draft.certifications, isEmpty);
      expect(draft.unclassifiedText, isNotEmpty);
    });
  });

  group('Skills structuring', () {
    test('splits a comma-separated skills line into individual entries', () {
      final draft = parser.parse('SKILLS\n\nDart, Flutter, SQL, Python\n');
      expect(draft.skills.map((s) => s.name), ['Dart', 'Flutter', 'SQL', 'Python']);
    });

    test(
      '"SKILLS SUMMARY" is also recognized as the Skills section - real-device beta fix: '
      'a real resume used this exact heading and it previously fell through to a generic '
      'custom section, so its individual skills were preserved as raw text but never as '
      'real Skills entries the JD-tailoring pipeline can actually match against',
      () {
        final draft = parser.parse('SKILLS SUMMARY\n\nDart, Flutter, SQL\n');
        expect(draft.skills.map((s) => s.name), ['Dart', 'Flutter', 'SQL']);
        expect(draft.customSections, isEmpty);
      },
    );

    test('splits bulleted, one-per-line skills', () {
      final draft = parser.parse('SKILLS\n\n- Dart\n- Flutter\n- SQL\n');
      expect(draft.skills.map((s) => s.name), ['Dart', 'Flutter', 'SQL']);
    });

    test('deduplicates case-insensitively, keeping first-seen casing', () {
      final draft = parser.parse('SKILLS\n\nDart, dart, DART\n');
      expect(draft.skills, hasLength(1));
      expect(draft.skills.single.name, 'Dart');
    });
  });

  group('purity and non-fabrication', () {
    test('an empty string produces an empty, non-fabricated draft', () {
      final draft = parser.parse('');
      expect(draft.hasAnyStructuredContent, isFalse);
      expect(draft.experience, isEmpty);
      expect(draft.skills, isEmpty);
    });

    test('repeated parses of the same text produce structurally equivalent results', () {
      const text = 'Jane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n';
      final first = parser.parse(text);
      final second = parser.parse(text);
      expect(first.experience.single.role, second.experience.single.role);
      expect(first.experience.single.bullets, second.experience.single.bullets);
    });

    test('preserves the exact original text of unclassified content, not a '
        'summary or paraphrase of it', () {
      const original = 'A very specific unstructured sentence that must survive verbatim.';
      final draft = parser.parse(original);
      expect(draft.unclassifiedText, contains(original));
    });
  });
}
