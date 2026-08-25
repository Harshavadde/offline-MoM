import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/experience_block.dart' show ExperienceSubProject;
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/services/resume/template/resume_content_plan.dart';
import 'package:offline_mom/services/resume/template/resume_content_plan_builder.dart';

void main() {
  ResumeSnapshot fullSnapshot() {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        phone: '555-1234',
        location: 'Remote',
      ),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Senior Engineer',
          company: 'Acme Corp',
          startDate: '2022-01',
          bullets: ['Shipped the thing', 'Led the team'],
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
      projects: const [
        ResolvedProjectEntry(sourceBlockId: 3, name: 'Side Project', bullets: ['Built a thing']),
      ],
      certifications: const [
        ResolvedCertificationEntry(sourceBlockId: 4, name: 'AWS Certified', issuer: 'Amazon'),
      ],
      skills: const [
        ResolvedSkillEntry(sourceBlockId: 5, name: 'Dart', category: SkillCategory.technical),
        ResolvedSkillEntry(sourceBlockId: 6, name: 'Flutter', category: SkillCategory.technical),
      ],
    );
  }

  group('single-column (default) mode', () {
    test('an empty snapshot produces only the name line, no sections', () {
      final plan = buildResumeContentPlan(ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      ));
      expect(plan.sectionHeadingsInOrder, isEmpty);
    });

    test('section headings appear in the expected ATS-standard order and text '
        '(docs/v3/01-prd.md §9)', () {
      final plan = buildResumeContentPlan(fullSnapshot());

      expect(plan.sectionHeadingsInOrder, ['Experience', 'Education', 'Skills', 'Projects', 'Certifications']);
    });

    test('every line lives in the main column - nothing sidebar-tagged by default', () {
      final plan = buildResumeContentPlan(fullSnapshot());
      expect(plan.hasSidebar, isFalse);
      expect(plan.mainLines.length, plan.lines.length);
    });

    test('the name line is always first', () {
      final plan = buildResumeContentPlan(fullSnapshot());
      expect(plan.lines.first.kind, ResumeContentLineKind.name);
      expect(plan.lines.first.text, 'Jane Doe');
    });

    test('an experience entry emits title, meta, then each bullet in order', () {
      final plan = buildResumeContentPlan(fullSnapshot());
      final experienceIndex = plan.lines.indexWhere((l) => l.text == 'Experience');
      final following = plan.lines.sublist(experienceIndex + 1, experienceIndex + 5);

      expect(following[0].kind, ResumeContentLineKind.entryTitle);
      expect(following[0].text, 'Senior Engineer - Acme Corp');
      expect(following[1].kind, ResumeContentLineKind.entryMeta);
      expect(following[2].text, 'Shipped the thing');
      expect(following[3].text, 'Led the team');
    });

    test('skills render as one paragraph line, not one line per skill', () {
      final plan = buildResumeContentPlan(fullSnapshot());
      final paragraphs = plan.lines.where((l) => l.kind == ResumeContentLineKind.paragraph);
      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.text, 'Dart, Flutter');
    });

    test('a section with zero entries produces no heading for it', () {
      final plan = buildResumeContentPlan(ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
        experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Engineer',
            company: 'Acme',
            startDate: '2022-01',
          ),
        ],
      ));

      expect(plan.sectionHeadingsInOrder, ['Experience']);
    });
  });

  group('sub-projects (migration v20 - Resume -> Experience -> Project -> Project bullets)', () {
    ResumeSnapshot snapshotWithSubProjects() {
      return ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
        experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Software Engineer',
            company: 'Acme Corp',
            startDate: '2022-01',
            bullets: ['Top-level bullet'],
            subProjects: [
              ExperienceSubProject(name: 'SciLab', bullets: ['Built SciLab.', 'Shipped SciLab.']),
              ExperienceSubProject(name: 'ByHeart', bullets: ['Built ByHeart.']),
            ],
          ),
        ],
      );
    }

    test('each sub-project emits a subProjectTitle line followed by its own bullet lines', () {
      final plan = buildResumeContentPlan(snapshotWithSubProjects());
      final experienceIndex = plan.lines.indexWhere((l) => l.text == 'Experience');
      final following = plan.lines.sublist(experienceIndex + 1);

      expect(following[0].kind, ResumeContentLineKind.entryTitle);
      expect(following[1].kind, ResumeContentLineKind.entryMeta);
      expect(following[2].text, 'Top-level bullet');
      expect(following[3].kind, ResumeContentLineKind.subProjectTitle);
      expect(following[3].text, 'SciLab');
      expect(following[4].kind, ResumeContentLineKind.bullet);
      expect(following[4].text, 'Built SciLab.');
      expect(following[5].text, 'Shipped SciLab.');
      expect(following[6].kind, ResumeContentLineKind.subProjectTitle);
      expect(following[6].text, 'ByHeart');
      expect(following[7].text, 'Built ByHeart.');
    });

    test('an entry with no sub-projects emits no subProjectTitle lines', () {
      final plan = buildResumeContentPlan(fullSnapshot());
      expect(plan.lines.where((l) => l.kind == ResumeContentLineKind.subProjectTitle), isEmpty);
    });
  });

  group('sidebarContactAndSkills mode (two-column-sidebar archetype)', () {
    test('name, contact, and Skills move to the sidebar column', () {
      final plan = buildResumeContentPlan(fullSnapshot(), sidebarContactAndSkills: true);

      expect(plan.hasSidebar, isTrue);
      final sidebarKinds = plan.sidebarLines.map((l) => l.kind).toSet();
      expect(sidebarKinds, contains(ResumeContentLineKind.name));
      expect(sidebarKinds, contains(ResumeContentLineKind.contact));
      expect(sidebarKinds, contains(ResumeContentLineKind.sectionHeading));
      expect(plan.sidebarLines.map((l) => l.text), contains('Skills'));
    });

    test('Experience/Education/Projects/Certifications stay in the main column, in order', () {
      final plan = buildResumeContentPlan(fullSnapshot(), sidebarContactAndSkills: true);

      final mainHeadings = plan.mainLines
          .where((l) => l.kind == ResumeContentLineKind.sectionHeading)
          .map((l) => l.text)
          .toList();
      expect(mainHeadings, ['Experience', 'Education', 'Projects', 'Certifications']);
    });

    test('the main column never contains the Skills heading in sidebar mode', () {
      final plan = buildResumeContentPlan(fullSnapshot(), sidebarContactAndSkills: true);
      expect(plan.mainLines.map((l) => l.text), isNot(contains('Skills')));
    });

    test(
      'overall sectionHeadingsInOrder still lists every heading in the canonical build order, '
      'regardless of which column each is tagged with',
      () {
        final plan = buildResumeContentPlan(fullSnapshot(), sidebarContactAndSkills: true);
        expect(
          plan.sectionHeadingsInOrder,
          ['Experience', 'Education', 'Skills', 'Projects', 'Certifications'],
        );
      },
    );
  });

  group('capOlderExperienceBullets (product composition-audit pass - recency-weighted bullet density)', () {
    ResumeSnapshot longCareerSnapshot() {
      ResolvedExperienceEntry entry(String role, String start, String? end, List<String> bullets) {
        return ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: role,
          company: 'Company $role',
          startDate: start,
          endDate: end,
          bullets: bullets,
        );
      }

      const fourBullets = ['B1', 'B2', 'B3', 'B4'];
      return ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
        // Deliberately NOT in chronological order in the list itself, to
        // prove ranking is by parsed date, never by list position.
        experience: [
          entry('Oldest', '2008-01', '2011-01', fourBullets),
          entry('Current', '2023-01', null, fourBullets),
          entry('Middle', '2014-01', '2017-01', fourBullets),
          entry('Recent', '2020-01', '2023-01', fourBullets),
          entry('Second-Oldest', '2011-01', '2014-01', fourBullets),
        ],
      );
    }

    List<String> bulletsForEntry(ResumeContentPlan plan, String role) {
      final titleIndex = plan.lines.indexWhere((l) => l.primaryText == role);
      final bullets = <String>[];
      for (var i = titleIndex + 2; i < plan.lines.length; i++) {
        if (plan.lines[i].kind != ResumeContentLineKind.bullet) break;
        bullets.add(plan.lines[i].text);
      }
      return bullets;
    }

    test('with 5+ entries, the 2 most-recent-by-date entries keep every bullet', () {
      final plan = buildResumeContentPlan(longCareerSnapshot());
      expect(bulletsForEntry(plan, 'Current'), hasLength(4));
      expect(bulletsForEntry(plan, 'Recent'), hasLength(4));
    });

    test('with 5+ entries, every older entry is capped to its first 2 bullets', () {
      final plan = buildResumeContentPlan(longCareerSnapshot());
      expect(bulletsForEntry(plan, 'Middle'), ['B1', 'B2']);
      expect(bulletsForEntry(plan, 'Second-Oldest'), ['B1', 'B2']);
      expect(bulletsForEntry(plan, 'Oldest'), ['B1', 'B2']);
    });

    test('ranking is by parsed end date, not by list position', () {
      final plan = buildResumeContentPlan(longCareerSnapshot());
      // "Current" (endDate null / Present) and "Recent" (2023-01) are the
      // 2 most recent by date despite not being first/second in the list.
      expect(bulletsForEntry(plan, 'Current'), hasLength(4));
      expect(bulletsForEntry(plan, 'Recent'), hasLength(4));
    });

    test('with 3 or fewer entries, no cap is applied even if capOlderExperienceBullets is true', () {
      final snapshot = ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
        experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Only Role',
            company: 'Acme',
            startDate: '2020-01',
            bullets: ['B1', 'B2', 'B3', 'B4'],
          ),
        ],
      );
      final plan = buildResumeContentPlan(snapshot);
      expect(bulletsForEntry(plan, 'Only Role'), hasLength(4));
    });

    test('capOlderExperienceBullets: false disables the cap entirely (Government Dense)', () {
      final plan = buildResumeContentPlan(longCareerSnapshot(), capOlderExperienceBullets: false);
      expect(bulletsForEntry(plan, 'Oldest'), hasLength(4));
      expect(bulletsForEntry(plan, 'Middle'), hasLength(4));
      expect(bulletsForEntry(plan, 'Second-Oldest'), hasLength(4));
    });

    test('capping never removes an entire entry - every role still appears', () {
      final plan = buildResumeContentPlan(longCareerSnapshot());
      final titles = plan.lines
          .where((l) => l.kind == ResumeContentLineKind.entryTitle)
          .map((l) => l.primaryText)
          .toSet();
      expect(titles, {'Oldest', 'Current', 'Middle', 'Recent', 'Second-Oldest'});
    });
  });

  group('custom/generic sections (beta data-fidelity requirement)', () {
    test('a snapshot with no custom sections renders none - never a placeholder', () {
      final plan = buildResumeContentPlan(fullSnapshot());
      expect(plan.sectionHeadingsInOrder, isNot(contains('Awards')));
    });

    test(
      'a Summary/Objective-titled custom section renders immediately after the header, '
      'before Experience/Education/Skills/Projects/Certifications - real-device beta fix: '
      'previously every custom section (Summary included) rendered dead last, after '
      'Certifications, which put a resume\'s own professional summary at the very bottom '
      'of the page instead of right after the name/contact block',
      () {
        final snapshot = fullSnapshot().copyWith(customSections: const [
          ResolvedCustomSectionEntry(
            sourceBlockId: 9,
            title: 'Summary',
            entries: ['Results-driven engineer with 5 years of experience.'],
          ),
          ResolvedCustomSectionEntry(sourceBlockId: 10, title: 'Awards', entries: ['Employee of the Year']),
        ]);
        final plan = buildResumeContentPlan(snapshot);

        expect(
          plan.sectionHeadingsInOrder,
          ['Summary', 'Experience', 'Education', 'Skills', 'Projects', 'Certifications', 'Awards'],
        );

        final summaryIndex = plan.lines.indexWhere(
          (l) => l.kind == ResumeContentLineKind.sectionHeading && l.text == 'Summary',
        );
        // Summary comes before the name-only preamble ends and Experience begins.
        final experienceIndex = plan.lines.indexWhere(
          (l) => l.kind == ResumeContentLineKind.sectionHeading && l.text == 'Experience',
        );
        expect(summaryIndex, greaterThan(0));
        expect(summaryIndex, lessThan(experienceIndex));
        expect(plan.lines[summaryIndex + 1].kind, ResumeContentLineKind.paragraph);
        expect(plan.lines[summaryIndex + 1].text, 'Results-driven engineer with 5 years of experience.');

        // A Summary section is never rendered twice (once inline, once via the
        // generic trailing custom-sections loop).
        expect(plan.sectionHeadingsInOrder.where((h) => h == 'Summary'), hasLength(1));
      },
    );

    test('an "Objective" title is also recognized as summary-like and moved after the header', () {
      final snapshot = fullSnapshot().copyWith(customSections: const [
        ResolvedCustomSectionEntry(sourceBlockId: 9, title: 'Objective', entries: ['Seeking a senior role.']),
      ]);
      final plan = buildResumeContentPlan(snapshot);
      expect(plan.sectionHeadingsInOrder.first, 'Objective');
    });

    test('every custom section renders as a real heading, using the primitives '
        'every other section already uses (sectionHeading + a single paragraph, or '
        'sectionHeading + bullet per entry for a genuine list), never a special '
        'per-archetype layout', () {
      final snapshot = fullSnapshot().copyWith(customSections: const [
        ResolvedCustomSectionEntry(sourceBlockId: 7, title: 'Awards', entries: ['Employee of the Year']),
        ResolvedCustomSectionEntry(
          sourceBlockId: 8,
          title: 'Publications',
          entries: ['A Paper About Something', 'Another Paper'],
        ),
      ]);
      final plan = buildResumeContentPlan(snapshot);

      expect(
        plan.sectionHeadingsInOrder,
        ['Experience', 'Education', 'Skills', 'Projects', 'Certifications', 'Awards', 'Publications'],
      );
      // A single-entry custom section (real-device beta fix) renders as one
      // paragraph, not a lone bullet dot in front of what may be a whole
      // sentence - matches the same rule applied to a Summary/Objective
      // section, see resume_content_plan_builder.dart's own doc comment.
      final awardsIndex = plan.lines.indexWhere(
        (l) => l.kind == ResumeContentLineKind.sectionHeading && l.text == 'Awards',
      );
      expect(plan.lines[awardsIndex + 1].kind, ResumeContentLineKind.paragraph);
      expect(plan.lines[awardsIndex + 1].text, 'Employee of the Year');

      // A multi-entry custom section still renders as one bullet per entry,
      // unchanged.
      final pubIndex = plan.lines.indexWhere(
        (l) => l.kind == ResumeContentLineKind.sectionHeading && l.text == 'Publications',
      );
      expect(plan.lines[pubIndex + 1].kind, ResumeContentLineKind.bullet);
      expect(plan.lines[pubIndex + 1].text, 'A Paper About Something');
      expect(plan.lines[pubIndex + 2].kind, ResumeContentLineKind.bullet);
      expect(plan.lines[pubIndex + 2].text, 'Another Paper');
    });

    test('preserves every custom section - none dropped or truncated with several present', () {
      final snapshot = ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
        customSections: [
          for (var i = 1; i <= 5; i++)
            ResolvedCustomSectionEntry(sourceBlockId: i, title: 'Section $i', entries: ['Entry $i']),
        ],
      );
      final plan = buildResumeContentPlan(snapshot);
      expect(plan.sectionHeadingsInOrder, ['Section 1', 'Section 2', 'Section 3', 'Section 4', 'Section 5']);
    });
  });
}
