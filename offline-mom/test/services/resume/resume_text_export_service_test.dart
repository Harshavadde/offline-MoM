// Tests ResumeTextExportService (lib/services/resume/resume_text_export_service.dart)
// - a pure function of an already-compiled ResumeSnapshot, mirroring
// chat_export_service_test.dart's exact style: a const service instance,
// plain factory helpers, no database and no file I/O anywhere in this file.
// This service never writes a file (it mirrors ChatExportService's
// TXT/Markdown half, which shares text directly rather than saving it) -
// see the final Batch 6 report for why the "file-writing failure" scenario
// from the batch's test checklist does not apply to this format.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_link.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/services/resume/resume_text_export_service.dart';

void main() {
  const service = ResumeTextExportService();

  ResumeSnapshot fullSnapshot() {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        phone: '555-1234',
        location: 'Austin, TX',
        links: [ResumeLink(label: 'GitHub', url: 'github.com/janedoe')],
      ),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Senior Engineer',
          company: 'Acme Corp',
          location: 'Remote',
          startDate: '2022-01',
          endDate: '2024-06',
          bullets: ['Shipped the payments pipeline.', 'Mentored two engineers.'],
        ),
        ResolvedExperienceEntry(
          sourceBlockId: 2,
          role: 'Engineer',
          company: 'Startup Inc',
          startDate: '2020-01',
          bullets: ['Built the first API.'],
        ),
      ],
      education: const [
        ResolvedEducationEntry(
          sourceBlockId: 3,
          institution: 'State University',
          degree: 'B.S. Computer Science',
          fieldOfStudy: 'Machine Learning',
          startDate: '2016-08',
          endDate: '2020-05',
          details: ['GPA 3.9', 'Dean\'s List'],
        ),
      ],
      projects: const [
        ResolvedProjectEntry(
          sourceBlockId: 4,
          name: 'Offline Notes App',
          link: 'github.com/janedoe/notes',
          bullets: ['Built a fully offline sync engine.'],
        ),
      ],
      certifications: const [
        ResolvedCertificationEntry(
          sourceBlockId: 5,
          name: 'AWS Certified Developer',
          issuer: 'Amazon',
          issuedDate: '2023-03',
          credentialUrl: 'https://aws.example.com/cert/123',
        ),
      ],
      skills: const [
        ResolvedSkillEntry(sourceBlockId: 6, name: 'Dart', category: SkillCategory.technical),
        ResolvedSkillEntry(sourceBlockId: 7, name: 'Leadership', category: SkillCategory.soft),
      ],
    );
  }

  ResumeSnapshot minimalSnapshot() {
    return ResumeSnapshot(
      resumeId: 2,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Empty Resume'),
    );
  }

  group('buildPlainText - complete snapshot', () {
    test('includes the full name and contact line', () {
      final text = service.buildPlainText(fullSnapshot());
      expect(text, contains('Jane Doe'));
      expect(text, contains('jane@example.com | 555-1234 | Austin, TX'));
    });

    test('includes the links line', () {
      final text = service.buildPlainText(fullSnapshot());
      expect(text, contains('GitHub: github.com/janedoe'));
    });

    test('exports every section present in the snapshot', () {
      final text = service.buildPlainText(fullSnapshot());
      expect(text, contains('EXPERIENCE'));
      expect(text, contains('Senior Engineer - Acme Corp'));
      expect(text, contains('EDUCATION'));
      expect(text, contains('B.S. Computer Science, Machine Learning - State University'));
      expect(text, contains('PROJECTS'));
      expect(text, contains('Offline Notes App'));
      expect(text, contains('CERTIFICATIONS'));
      expect(text, contains('AWS Certified Developer - Amazon (2023-03)'));
      expect(text, contains('SKILLS'));
      expect(text, contains('Dart, Leadership'));
    });

    test('section ordering is deterministic: profile, experience, education, '
        'projects, certifications, skills', () {
      final text = service.buildPlainText(fullSnapshot());
      final order = [
        'Jane Doe',
        'EXPERIENCE',
        'EDUCATION',
        'PROJECTS',
        'CERTIFICATIONS',
        'SKILLS',
      ].map(text.indexOf).toList();

      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]),
            reason: 'expected ${order[i - 1]} to come before ${order[i]}');
      }
    });

    test('bullet ordering within a section is preserved', () {
      final text = service.buildPlainText(fullSnapshot());
      final first = text.indexOf('Shipped the payments pipeline.');
      final second = text.indexOf('Mentored two engineers.');
      expect(first, greaterThan(0));
      expect(second, greaterThan(first));
    });

    test('preserves the order of multiple entries within the same section', () {
      final text = service.buildPlainText(fullSnapshot());
      final first = text.indexOf('Senior Engineer - Acme Corp');
      final second = text.indexOf('Engineer - Startup Inc');
      expect(second, greaterThan(first));
    });
  });

  group('buildMarkdown - complete snapshot', () {
    test('uses a level-1 heading for the name and level-2 headings for sections', () {
      final text = service.buildMarkdown(fullSnapshot());
      expect(text, contains('# Jane Doe'));
      expect(text, contains('## Experience'));
      expect(text, contains('## Education'));
      expect(text, contains('## Projects'));
      expect(text, contains('## Certifications'));
      expect(text, contains('## Skills'));
    });

    test('uses simple bold emphasis for entry titles and bullet lists for content', () {
      final text = service.buildMarkdown(fullSnapshot());
      expect(text, contains('**Senior Engineer - Acme Corp**'));
      expect(text, contains('- Shipped the payments pipeline.'));
    });

    test('never emits a table, embedded HTML, or an image', () {
      final text = service.buildMarkdown(fullSnapshot());
      expect(text, isNot(contains('|---')));
      expect(text, isNot(contains('<')));
      expect(text, isNot(contains('![')));
    });

    test('section ordering matches the plain-text output', () {
      final text = service.buildMarkdown(fullSnapshot());
      final order = [
        '# Jane Doe',
        '## Experience',
        '## Education',
        '## Projects',
        '## Certifications',
        '## Skills',
      ].map(text.indexOf).toList();
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]));
      }
    });
  });

  group('nullable fields and empty sections', () {
    test('a null end date renders as "Present", never the literal word "null"', () {
      final text = service.buildPlainText(fullSnapshot());
      expect(text, contains('2020-01 - Present'));
      expect(text, isNot(contains('null')));
    });

    test('markdown output also never contains the literal word "null"', () {
      final text = service.buildMarkdown(fullSnapshot());
      expect(text, isNot(contains('null')));
    });

    test('an entry with no location omits it entirely rather than printing an '
        'empty separator', () {
      final text = service.buildPlainText(fullSnapshot());
      expect(text, contains('2020-01 - Present\n'));
      expect(text, isNot(contains('2020-01 - Present | ')));
    });

    test('a snapshot with no links omits the links line entirely', () {
      final snapshot = ResumeSnapshot(
        resumeId: 3,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'No Links'),
      );
      final text = service.buildPlainText(snapshot);
      expect(text, isNot(contains(':')));
    });

    test('empty sections are omitted entirely - no heading is printed for a '
        'section with zero entries', () {
      final snapshot = ResumeSnapshot(
        resumeId: 4,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Experience Only'),
        experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Engineer',
            company: 'Acme',
            startDate: '2020-01',
          ),
        ],
      );
      final text = service.buildPlainText(snapshot);
      expect(text, contains('EXPERIENCE'));
      expect(text, isNot(contains('EDUCATION')));
      expect(text, isNot(contains('PROJECTS')));
      expect(text, isNot(contains('CERTIFICATIONS')));
      expect(text, isNot(contains('SKILLS')));
    });
  });

  group('minimal snapshot', () {
    test('a snapshot with only a name and no sections exports successfully '
        'with just the name', () {
      final text = service.buildPlainText(minimalSnapshot());
      expect(text.trim(), 'Empty Resume');
    });

    test('markdown for a minimal snapshot is just the heading', () {
      final text = service.buildMarkdown(minimalSnapshot());
      expect(text.trim(), '# Empty Resume');
    });
  });

  group('content fidelity', () {
    test('special characters (C++, R&D, quotes, ampersands) are preserved verbatim', () {
      final snapshot = ResumeSnapshot(
        resumeId: 5,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Special Chars'),
        skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'C++', category: SkillCategory.technical),
        ],
        experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'R&D Lead',
            company: 'Q&A "Solutions"',
            startDate: '2020-01',
            bullets: ['Led "special projects" & delivered on time.'],
          ),
        ],
      );

      final text = service.buildPlainText(snapshot);
      expect(text, contains('C++'));
      expect(text, contains('R&D Lead - Q&A "Solutions"'));
      expect(text, contains('Led "special projects" & delivered on time.'));
    });

    test('non-Latin text is preserved unchanged in both formats', () {
      final snapshot = ResumeSnapshot(
        resumeId: 6,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: '田中 太郎', location: 'Москва'),
        skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: '国际化', category: SkillCategory.technical),
        ],
      );

      final plainText = service.buildPlainText(snapshot);
      final markdown = service.buildMarkdown(snapshot);
      expect(plainText, contains('田中 太郎'));
      expect(plainText, contains('Москва'));
      expect(plainText, contains('国际化'));
      expect(markdown, contains('田中 太郎'));
      expect(markdown, contains('国际化'));
    });

    test('output never mentions fields the snapshot does not carry, e.g. the '
        'internal sourceBlockId', () {
      final text = service.buildPlainText(fullSnapshot());
      expect(text, isNot(contains('sourceBlockId')));
      expect(text, isNot(contains('source_block_id')));
    });
  });

  group('determinism and purity', () {
    test('does not mutate the snapshot passed in', () {
      final snapshot = fullSnapshot();
      final before = snapshot.experience.map((e) => e.bullets.length).toList();

      service.buildPlainText(snapshot);
      service.buildMarkdown(snapshot);

      final after = snapshot.experience.map((e) => e.bullets.length).toList();
      expect(after, before);
      expect(snapshot.profile.fullName, 'Jane Doe');
    });

    test('repeated calls with the same snapshot produce identical output', () {
      final snapshot = fullSnapshot();
      expect(service.buildPlainText(snapshot), service.buildPlainText(snapshot));
      expect(service.buildMarkdown(snapshot), service.buildMarkdown(snapshot));
    });
  });
}
