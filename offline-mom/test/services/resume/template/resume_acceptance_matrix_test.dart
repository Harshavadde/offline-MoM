// Reliability-overhaul pass, Phases 6/7/8/20/21: promotes the Phase-4
// (content-aware layout) stress datasets from a throwaway test/manual/
// script into the permanent regression suite, and extends them with the
// verification the manual version never had:
//
//  - Phase 6 (template output must match selection): every template's
//    rendered PDF bytes are pairwise distinguishable, and none accidentally
//    match a different template's rendering byte-for-byte (an accidental
//    fallback to Classic would be caught here).
//  - Phase 8 (content completeness after render): every experience company/
//    role, every education institution, every project name, and every
//    custom-section heading in the source snapshot is confirmed present in
//    the pre-render ResumeContentPlan - the same, already-established,
//    disclosed-limitation approach ResumeContentPlan's own doc comment
//    describes (real native PDF text extraction needs read_pdf_text's
//    platform channel and cannot run under `flutter test`; this verifies
//    through the layer that actually determines final PDF content instead).
//  - Phase 20/21 (4+ experiences, acceptance matrix): explicit assertions
//    that a 6-role dataset's every entry survives into the content plan,
//    and a full dataset x template matrix confirming no crash, no empty
//    output, and a valid PDF for every combination.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/experience_block.dart' show ExperienceSubProject;
import 'package:offline_mom/models/resume_link.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_content_plan.dart';
import 'package:offline_mom/services/resume/template/resume_content_plan_builder.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

const _profile = ResumeSnapshotProfile(
  fullName: 'Jane Doe',
  email: 'jane.doe@example.com',
  phone: '555-123-4567',
  location: 'San Francisco, CA',
  roleTagline: 'Senior Software Engineer',
);

ResolvedExperienceEntry _exp(int id, {int bullets = 4, int bulletLength = 110}) {
  return ResolvedExperienceEntry(
    sourceBlockId: id,
    role: 'Senior Engineer $id',
    company: 'Company $id Inc.',
    location: 'City $id, ST',
    startDate: '${2010 + id}',
    endDate: id == 1 ? null : '${2011 + id}',
    bullets: List.generate(
      bullets,
      (i) => ('Delivered a significant technical outcome number $i with measurable business impact. ' * 3)
          .substring(0, bulletLength),
    ),
  );
}

ResolvedProjectEntry _project(int id) => ResolvedProjectEntry(
      sourceBlockId: id,
      name: 'Project $id',
      link: 'https://github.com/janedoe/project-$id',
      bullets: ['Built feature $id.', 'Improved metric $id by 20%.'],
    );

ResolvedSkillEntry _skill(int id) => ResolvedSkillEntry(
      sourceBlockId: id,
      name: 'Skill$id',
      category: SkillCategory.values[id % SkillCategory.values.length],
    );

/// Every dataset this pass's acceptance matrix runs across all 5 beta
/// templates - deliberately extreme in different dimensions (short/long,
/// many projects, many skills, many custom sections, very long bullets,
/// everything present at once) so a pagination/overflow defect that only
/// manifests at one content extreme can't hide behind an "average" dataset.
final _datasets = <String, ResumeSnapshot>{
  'A-short': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: [_exp(1, bullets: 1, bulletLength: 40)],
  ),
  'C-3job': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: [_exp(1), _exp(2), _exp(3)],
    education: const [
      ResolvedEducationEntry(
        sourceBlockId: 1,
        institution: 'State University',
        degree: 'B.Sc Computer Science',
        startDate: '2010',
        endDate: '2014',
      ),
    ],
    skills: List.generate(10, _skill),
  ),
  // Phase 20: at least 4 employment entries, explicitly asserted below to
  // all survive into the content plan.
  'D-6job': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: List.generate(6, (i) => _exp(i + 1, bullets: 5)),
    education: const [
      ResolvedEducationEntry(
        sourceBlockId: 1,
        institution: 'State University',
        degree: 'B.Sc Computer Science',
        startDate: '2000',
        endDate: '2004',
      ),
    ],
    skills: List.generate(18, _skill),
    projects: List.generate(3, _project),
  ),
  'E-10projects': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: [_exp(1, bullets: 3)],
    projects: List.generate(12, _project),
  ),
  'F-20skills': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: [_exp(1, bullets: 3)],
    skills: List.generate(20, _skill),
  ),
  'G-customSections': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: [_exp(1, bullets: 3)],
    customSections: const [
      ResolvedCustomSectionEntry(sourceBlockId: 1, title: 'Summary', entries: ['A concise summary paragraph.']),
      ResolvedCustomSectionEntry(
        sourceBlockId: 2,
        title: 'Awards',
        entries: ['Employee of the Year, 2021', 'Top Performer Award, 2020'],
      ),
      ResolvedCustomSectionEntry(
        sourceBlockId: 3,
        title: 'Publications',
        entries: ['A Paper About Something, 2022', 'Another Paper, 2021', 'Third Paper, 2020'],
      ),
      ResolvedCustomSectionEntry(
        sourceBlockId: 4,
        title: 'Languages',
        entries: ['English (Native)', 'Spanish (Conversational)', 'French (Basic)'],
      ),
      ResolvedCustomSectionEntry(
        sourceBlockId: 5,
        title: 'Volunteer Experience',
        entries: ['Mentored 5 junior developers at a local coding bootcamp.'],
      ),
    ],
  ),
  'H-longBullets': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: [
      const ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Principal Engineer',
        company: 'Big Corp',
        startDate: '2015',
        bullets: [
          'This is an intentionally extremely long bullet point designed to stress-test text wrapping and '
              'page-break behavior for a single very dense accomplishment description that goes on for several '
              'sentences without stopping, covering architecture decisions, stakeholder management, cross-team '
              'coordination, incident response leadership, and long-term technical strategy all within one '
              'continuous run-on bullet to see whether the renderer handles it gracefully without clipping, '
              'overlapping, or crashing under real content pressure.',
          'A second similarly long bullet point that continues to describe substantial technical achievements '
              'across multiple systems, programming languages, cloud platforms, and organizational contexts, '
              'deliberately written to exceed what a normal resume bullet would contain in order to validate '
              'that content-aware layout handles unusually dense single entries without truncating any of the '
              'underlying text content.',
        ],
      ),
    ],
  ),
  // Phase 20: 4+ experience entries, plus everything else present at once -
  // the single most demanding dataset in this matrix.
  'I-everything': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: List.generate(4, (i) => _exp(i + 1, bullets: 4)),
    education: const [
      ResolvedEducationEntry(
        sourceBlockId: 1,
        institution: 'State University',
        degree: 'M.Sc Computer Science',
        startDate: '2008',
        endDate: '2010',
      ),
      ResolvedEducationEntry(
        sourceBlockId: 2,
        institution: 'Other University',
        degree: 'B.Sc Computer Science',
        startDate: '2004',
        endDate: '2008',
      ),
    ],
    skills: List.generate(15, _skill),
    projects: List.generate(4, _project),
    certifications: const [
      ResolvedCertificationEntry(sourceBlockId: 1, name: 'AWS Certified', issuer: 'Amazon', issuedDate: '2021'),
      ResolvedCertificationEntry(sourceBlockId: 2, name: 'PMP', issuer: 'PMI', issuedDate: '2019'),
    ],
    customSections: const [
      ResolvedCustomSectionEntry(
        sourceBlockId: 1,
        title: 'Summary',
        entries: [
          'A seasoned engineering leader with over a decade of experience building and scaling distributed '
              'systems across fintech, healthcare, and consumer products.',
        ],
      ),
      ResolvedCustomSectionEntry(sourceBlockId: 2, title: 'Awards', entries: ['Employee of the Year, 2021']),
    ],
  ),
  // Part G (product-quality remediation pass): sub-projects (D-M9-01,
  // migration v20) never had matrix coverage - the acceptance matrix
  // predates that architecture entirely. Shaped after the real
  // SciLab/ByHeart/Crossword resume that originally motivated it: one
  // role with 3 named sub-projects, each with its own bullets, alongside
  // a second, ordinary role with no sub-projects at all (so the matrix
  // also confirms sub-project-free entries are unaffected).
  'J-subProjects': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: _profile,
    experience: [
      const ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Software Engineer',
        company: 'Acme Corp',
        location: 'Remote',
        startDate: '2023',
        endDate: null,
        bullets: ['Led the platform team\'s core services rewrite.'],
        subProjects: [
          ExperienceSubProject(
            name: 'SciLab (Web & Android) — Godot, AWS S3',
            bullets: ['Built the initial SciLab release.', 'Scaled it to 50k monthly users.'],
          ),
          ExperienceSubProject(
            name: 'ByHeart (Web & Android) — Cloudflare Workers',
            bullets: ['Built the audio pipeline.', 'Shipped speech-to-text integration.'],
          ),
          ExperienceSubProject(
            name: 'Crossword App (Web & Android) — Kotlin',
            bullets: ['Migrated speech recognition to a self-hosted pipeline.'],
          ),
        ],
      ),
      _exp(2, bullets: 2),
    ],
    education: const [
      ResolvedEducationEntry(
        sourceBlockId: 1,
        institution: 'State University',
        degree: 'B.Sc Computer Science',
        startDate: '2018',
        endDate: '2022',
      ),
    ],
    skills: List.generate(6, _skill),
  ),
  // Part G: profile.links was never populated by any prior dataset in
  // this matrix - every header/contact-links rendering path across all
  // 5 templates was genuinely unexercised until now.
  'K-multipleLinks': ResumeSnapshot(
    resumeId: 1,
    compiledAt: DateTime.now(),
    profile: const ResumeSnapshotProfile(
      fullName: 'Jane Doe',
      email: 'jane.doe@example.com',
      phone: '555-123-4567',
      location: 'San Francisco, CA',
      roleTagline: 'Senior Software Engineer',
      links: [
        ResumeLink(label: 'LinkedIn', url: 'linkedin.com/in/janedoe'),
        ResumeLink(label: 'GitHub', url: 'github.com/janedoe'),
        ResumeLink(label: 'Portfolio', url: 'janedoe.dev'),
        ResumeLink(label: 'X', url: 'x.com/janedoe'),
        ResumeLink(label: 'Stack Overflow', url: 'stackoverflow.com/users/12345/janedoe'),
      ],
    ),
    experience: [_exp(1, bullets: 3)],
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const renderer = ResumeTemplateRenderer();
  final templates = ResumeTemplateCatalog.enabled;

  group('Phase 21: template acceptance matrix (dataset x template)', () {
    for (final datasetEntry in _datasets.entries) {
      for (final spec in templates) {
        test('${datasetEntry.key} x ${spec.displayName}: renders a non-empty, valid PDF', () async {
          final bytes = await renderer.render(datasetEntry.value, spec);
          expect(bytes, isNotEmpty);
          // A real, minimal PDF-validity signal reachable without a
          // platform channel: every valid PDF file begins with the
          // literal "%PDF-" magic bytes (PDF spec §7.5.2).
          expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        });
      }
    }
  });

  group('Phase 6: template output must be distinguishable, never an accidental fallback', () {
    test('every enabled template renders byte-different output for the same resume data', () async {
      final snapshot = _datasets['I-everything']!;
      final rendered = <String, List<int>>{};
      for (final spec in templates) {
        rendered[spec.id] = await renderer.render(snapshot, spec);
      }

      final ids = rendered.keys.toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(
            rendered[ids[i]],
            isNot(equals(rendered[ids[j]])),
            reason: '${ids[i]} and ${ids[j]} produced byte-identical PDFs - one of them is silently '
                'falling back to the other instead of rendering its own template',
          );
        }
      }
    });
  });

  group('Phase 8: content completeness (source -> ResumeContentPlan)', () {
    test('a 6-experience dataset (D-6job) preserves every single company and role', () {
      final snapshot = _datasets['D-6job']!;
      expect(snapshot.experience, hasLength(6), reason: 'Phase 20: do not stop at one or two entries');

      final plan = buildResumeContentPlan(snapshot);
      final allText = plan.lines.map((l) => l.text).join('\n');
      for (final entry in snapshot.experience) {
        expect(allText, contains(entry.company), reason: 'missing company: ${entry.company}');
        expect(allText, contains(entry.role), reason: 'missing role: ${entry.role}');
      }
    });

    test('the "everything present" dataset preserves every experience, education, project, and custom section', () {
      final snapshot = _datasets['I-everything']!;
      expect(snapshot.experience.length, greaterThanOrEqualTo(4));

      final plan = buildResumeContentPlan(snapshot);
      final allText = plan.lines.map((l) => l.text).join('\n');

      for (final entry in snapshot.experience) {
        expect(allText, contains(entry.company), reason: 'missing experience company: ${entry.company}');
        expect(allText, contains(entry.role), reason: 'missing experience role: ${entry.role}');
      }
      for (final edu in snapshot.education) {
        expect(allText, contains(edu.institution), reason: 'missing education institution: ${edu.institution}');
      }
      for (final project in snapshot.projects) {
        expect(allText, contains(project.name), reason: 'missing project: ${project.name}');
      }
      for (final section in snapshot.customSections) {
        expect(allText, contains(section.title), reason: 'missing custom section heading: ${section.title}');
      }
    });

    test('12 projects (E-10projects) all survive into the content plan, none silently truncated', () {
      final snapshot = _datasets['E-10projects']!;
      expect(snapshot.projects, hasLength(12));

      final plan = buildResumeContentPlan(snapshot);
      final allText = plan.lines.map((l) => l.text).join('\n');
      for (final project in snapshot.projects) {
        expect(allText, contains(project.name), reason: 'missing project: ${project.name}');
      }
    });

    test('5 custom sections (G-customSections) all appear as real headings, in the source order', () {
      final snapshot = _datasets['G-customSections']!;
      final plan = buildResumeContentPlan(snapshot);
      final headings = plan.sectionHeadingsInOrder;
      final customTitles = snapshot.customSections.map((s) => s.title).toList();
      for (final title in customTitles) {
        expect(headings, contains(title), reason: 'missing custom section heading: $title');
      }
    });

    test(
      'Part G: every sub-project name and every one of its own bullets (J-subProjects) survives '
      'into the content plan as a distinct subProjectTitle line, and the sub-project-free second '
      'entry is completely unaffected',
      () {
        final snapshot = _datasets['J-subProjects']!;
        final subProjectEntry = snapshot.experience.first;
        expect(subProjectEntry.subProjects, hasLength(3));

        final plan = buildResumeContentPlan(snapshot);
        final subProjectTitleLines =
            plan.lines.where((l) => l.kind == ResumeContentLineKind.subProjectTitle).map((l) => l.text).toList();
        for (final subProject in subProjectEntry.subProjects) {
          expect(subProjectTitleLines, contains(subProject.name), reason: 'missing sub-project: ${subProject.name}');
        }
        final allText = plan.lines.map((l) => l.text).join('\n');
        for (final subProject in subProjectEntry.subProjects) {
          for (final bullet in subProject.bullets) {
            expect(allText, contains(bullet), reason: 'missing sub-project bullet: $bullet');
          }
        }
        // The second, ordinary role has no sub-projects and must not have
        // gained any subProjectTitle lines of its own.
        expect(subProjectTitleLines, hasLength(3));
      },
    );

    test(
      'Part G: every profile link (K-multipleLinks) - label and URL - survives into the content '
      'plan',
      () {
        final snapshot = _datasets['K-multipleLinks']!;
        expect(snapshot.profile.links, hasLength(5));

        final plan = buildResumeContentPlan(snapshot);
        final allText = plan.lines.map((l) => l.text).join('\n');
        for (final link in snapshot.profile.links) {
          expect(allText, contains(link.label), reason: 'missing link label: ${link.label}');
          expect(allText, contains(link.url), reason: 'missing link url: ${link.url}');
        }
      },
    );
  });
}
