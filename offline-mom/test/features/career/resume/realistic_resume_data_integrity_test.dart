// Beta Product Validation phase - full field-level data-preservation tests
// across the whole real import pipeline: raw text -> ResumeImportParser ->
// ImportResumeUseCase.confirmImport -> real Sqflite DB (openTestDatabase())
// -> ResumeCompilerService.compile -> ResumeSnapshot -> ResumeTemplateRenderer.
// Unlike test/manual/generate_beta_template_pdfs_test.dart (a visual-
// inspection script that hand-builds its ResumeSnapshot and never touches a
// database), every scenario here goes through the exact same repositories,
// use case, and compiler the real app uses, so a field surviving these
// tests means it survives the real Import -> Database -> Editor -> Template
// Preview -> Final PDF path, not just the parser in isolation.
//
// Scenarios mirror the Beta Product Validation brief's 8 named realistic
// resumes: (A) a normal resume, (B) a long-career resume (8 roles, 2+
// pages), (C) 12 distinct section types, (D) unusual/custom section names,
// (E) 10+ projects, (F) 15-20 skills, (G) missing/unusual dates, (H) an
// unusual section order.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/import_resume_use_case.dart';
import 'package:offline_mom/models/certification_block.dart';
import 'package:offline_mom/models/custom_section_block.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/education_block.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/project_block.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/documents/document_text_extraction_service.dart';
import 'package:offline_mom/services/resume/resume_compiler_service.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void expectExperiencePreserved(List<ExperienceBlock> parsed, List<ResolvedExperienceEntry> resolved) {
  expect(resolved.length, parsed.length, reason: 'experience entry count must survive the DB round-trip');
  for (var i = 0; i < parsed.length; i++) {
    expect(resolved[i].role, parsed[i].role, reason: 'entry $i role');
    expect(resolved[i].company, parsed[i].company, reason: 'entry $i company');
    expect(resolved[i].startDate, parsed[i].startDate, reason: 'entry $i startDate');
    expect(resolved[i].endDate, parsed[i].endDate, reason: 'entry $i endDate');
    expect(resolved[i].bullets, parsed[i].bullets, reason: 'entry $i bullets');
  }
}

void expectEducationPreserved(List<EducationBlock> parsed, List<ResolvedEducationEntry> resolved) {
  expect(resolved.length, parsed.length, reason: 'education entry count must survive the DB round-trip');
  for (var i = 0; i < parsed.length; i++) {
    expect(resolved[i].institution, parsed[i].institution, reason: 'entry $i institution');
    expect(resolved[i].degree, parsed[i].degree, reason: 'entry $i degree');
    expect(resolved[i].fieldOfStudy, parsed[i].fieldOfStudy, reason: 'entry $i fieldOfStudy');
    expect(resolved[i].startDate, parsed[i].startDate, reason: 'entry $i startDate');
    expect(resolved[i].endDate, parsed[i].endDate, reason: 'entry $i endDate');
    expect(resolved[i].details, parsed[i].details, reason: 'entry $i details');
  }
}

void expectProjectsPreserved(List<ProjectBlock> parsed, List<ResolvedProjectEntry> resolved) {
  expect(resolved.length, parsed.length, reason: 'project entry count must survive the DB round-trip');
  for (var i = 0; i < parsed.length; i++) {
    expect(resolved[i].name, parsed[i].name, reason: 'entry $i name');
    expect(resolved[i].link, parsed[i].link, reason: 'entry $i link');
    expect(resolved[i].bullets, parsed[i].bullets, reason: 'entry $i bullets');
  }
}

void expectCertificationsPreserved(List<CertificationBlock> parsed, List<ResolvedCertificationEntry> resolved) {
  expect(resolved.length, parsed.length, reason: 'certification entry count must survive the DB round-trip');
  for (var i = 0; i < parsed.length; i++) {
    expect(resolved[i].name, parsed[i].name, reason: 'entry $i name');
    expect(resolved[i].issuer, parsed[i].issuer, reason: 'entry $i issuer');
    expect(resolved[i].issuedDate, parsed[i].issuedDate, reason: 'entry $i issuedDate');
  }
}

void expectSkillsPreserved(List<SkillEntry> parsed, List<ResolvedSkillEntry> resolved) {
  expect(resolved.length, parsed.length, reason: 'skill count must survive the DB round-trip');
  for (var i = 0; i < parsed.length; i++) {
    expect(resolved[i].name, parsed[i].name, reason: 'skill $i name');
    expect(resolved[i].category, parsed[i].category, reason: 'skill $i category');
  }
}

void expectCustomSectionsPreserved(List<CustomSectionBlock> parsed, List<ResolvedCustomSectionEntry> resolved) {
  expect(resolved.length, parsed.length, reason: 'custom section count must survive the DB round-trip');
  for (var i = 0; i < parsed.length; i++) {
    expect(resolved[i].title, parsed[i].title, reason: 'custom section $i title (verbatim, never renamed)');
    expect(resolved[i].entries, parsed[i].entries, reason: 'custom section $i entries');
  }
}

String _longCareerText({required int roleCount}) {
  final buffer = StringBuffer()
    ..writeln('Devika Rao')
    ..writeln('devika.rao@example.com | (512) 555-0177')
    ..writeln('Austin, TX')
    ..writeln()
    ..writeln('EXPERIENCE')
    ..writeln();
  for (var i = 0; i < roleCount; i++) {
    final start = 2024 - (roleCount - i) * 3;
    final end = i == roleCount - 1 ? 'Present' : '${start + 3}';
    buffer
      ..writeln('Role ${i + 1} Title - Company ${i + 1} Inc')
      ..writeln('$start - $end')
      ..writeln('- Owned a major initiative during role ${i + 1}, improving a key operational metric.')
      ..writeln('- Partnered cross-functionally with product and security stakeholders on role ${i + 1}\'s roadmap.')
      ..writeln('- Mentored engineers and documented runbooks for role ${i + 1}\'s systems.')
      ..writeln('- Drove a measurable reliability improvement while in role ${i + 1}.')
      ..writeln();
  }
  buffer
    ..writeln('EDUCATION')
    ..writeln()
    ..writeln('B.S. in Electrical Engineering - Texas A&M University')
    ..writeln('2005 - 2009');
  return buffer.toString();
}

String _manyProjectsText({required int projectCount}) {
  final buffer = StringBuffer()
    ..writeln('Owen Fitzgerald')
    ..writeln('owen.fitzgerald@example.com')
    ..writeln()
    ..writeln('PROJECTS')
    ..writeln();
  for (var i = 0; i < projectCount; i++) {
    buffer.writeln('Project Alpha ${i + 1}');
    if (i.isEven) buffer.writeln('https://github.com/ofitz/project-alpha-${i + 1}');
    buffer
      ..writeln('- Built and shipped project ${i + 1}, used by real end users.')
      ..writeln('- Covered project ${i + 1} with automated tests.')
      ..writeln();
  }
  return buffer.toString();
}

String _manySkillsText({required int skillCount}) {
  final skills = List.generate(skillCount, (i) => 'Skill${i + 1}').join(', ');
  return 'Nadia Petrov\nnadia.petrov@example.com\n\nSKILLS\n\n$skills\n';
}

const _normalResumeText = '''
Ravi Kapoor
ravi.kapoor@example.com | (206) 555-0113
Seattle, WA
https://linkedin.com/in/ravikapoor

SUMMARY

Backend engineer with 6 years building distributed systems in Go and Python.

EXPERIENCE

Backend Engineer - Lumen Analytics
2021 - Present
- Designed a multi-tenant billing service processing 2M events per day.
- Cut P99 API latency by 45 percent through targeted caching and query optimization.
- Introduced contract testing across 8 internal services.

Software Engineer - Fernbridge Data
2018 - 2021
- Built ETL pipelines ingesting 500GB of daily clickstream data.
- Migrated a monolith's reporting module into an independently deployable service.

EDUCATION

B.S. in Computer Engineering - University of Washington
2014 - 2018

PROJECTS

Distributed Rate Limiter
https://github.com/rkapoor/rate-limiter
- Implemented a token-bucket rate limiter used by three internal teams.

Personal Finance Tracker
- Built a self-hosted budgeting app with a Postgres backend.

CERTIFICATIONS

AWS Certified Solutions Architect - Associate - Amazon Web Services
Issued 2021

SKILLS

Go, Python, PostgreSQL, Kafka, Docker, Kubernetes, gRPC, Redis, AWS, Terraform, Git, Linux

AWARDS

Q3 2022 Engineering Impact Award
''';

const _twelveSectionTypesText = '''
Felix Adeyemi
felix.adeyemi@example.com
Denver, CO

SUMMARY

Full-stack engineer focused on developer tooling.

EXPERIENCE

Platform Engineer - Ridgeline Software
2020 - Present
- Built internal developer tooling adopted company-wide.

Software Engineer - Ridgeline Software
2018 - 2020
- Shipped the first version of the internal CLI.

EDUCATION

B.S. in Computer Science - Colorado State University
2014 - 2018

PROJECTS

Internal CLI Toolkit
- Built the internal developer CLI mentioned above.

CERTIFICATIONS

Certified Kubernetes Administrator - Cloud Native Computing Foundation
Issued 2021

SKILLS

TypeScript, Go, React, PostgreSQL, Docker, Kubernetes, gRPC, Terraform

AWARDS

Hackathon Winner, 2021

PUBLICATIONS

"Scaling Internal Tools," Platform Weekly, 2022

VOLUNTEER EXPERIENCE

Code mentor, Denver Coding Bootcamp, 2019 - Present

LANGUAGES

English (native), Yoruba (conversational)

INTERESTS

Rock climbing, generative art

REFERENCES

Available upon request
''';

const _unusualSectionNamesText = '''
Camille Dubois
camille.dubois@example.com

EXPERIENCE

Product Engineer - Solstice Labs
2019 - 2023
- Led the redesign of the core onboarding flow.

EDUCATION

B.A. in Design - Parsons School of Design
2015 - 2019

RANDOM ACCOMPLISHMENTS

Shipped a side project with 10,000 downloads in its first month.

OPEN SOURCE CONTRIBUTIONS

Maintainer of a CSS utility library with 2,000 GitHub stars.

THINGS I AM PROUD OF

Mentored five junior designers into mid-level roles.

SPEAKING ENGAGEMENTS

Spoke at Design Systems Conference 2022 on componentization.
''';

const _unusualSectionOrderText = '''
Priya Shah
priya.shah@example.com
Austin, TX

SKILLS

Java, Spring Boot, PostgreSQL, AWS, Docker

LANGUAGES

English, Hindi

EXPERIENCE

Software Engineer - Delta Systems
2019 - 2022
- Built a payments reconciliation service handling 1M transactions per day.

INTERESTS

Chess, urban sketching

EDUCATION

B.S. in Computer Science - University of Texas at Austin
2015 - 2019

PROJECTS

Expense Splitter
- A small web app for splitting group expenses.

CERTIFICATIONS

Certified Scrum Master - Scrum Alliance
Issued 2021
''';

const _missingUnusualDatesText = '''
Tomas Novak
tomas.novak@example.com

EXPERIENCE

Engineer - Acme Corp
2018 - 2020
- Shipped the v1 reporting dashboard.

Senior Engineer - Beta Corp
2020 - Present
- Owns the payments integration layer.

Contractor - Gamma Corp
2022
- A short contract engagement with no clear end date given.
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ImportResumeUseCase importUseCase;
  late ResumeCompilerService compiler;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    final experienceRepo = SqfliteExperienceBlockRepository(db);
    final educationRepo = SqfliteEducationBlockRepository(db);
    final projectRepo = SqfliteProjectBlockRepository(db);
    final certificationRepo = SqfliteCertificationBlockRepository(db);
    final skillRepo = SqfliteSkillEntryRepository(db);
    final customSectionRepo = SqfliteCustomSectionBlockRepository(db);

    importUseCase = ImportResumeUseCase(
      extractors: const <DocumentSourceType, DocumentTextExtractionService>{},
      parser: const ResumeImportParser(),
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      experienceBlockRepository: experienceRepo,
      educationBlockRepository: educationRepo,
      projectBlockRepository: projectRepo,
      certificationBlockRepository: certificationRepo,
      skillEntryRepository: skillRepo,
      customSectionBlockRepository: customSectionRepo,
    );

    compiler = ResumeCompilerService(
      experienceBlockRepository: experienceRepo,
      educationBlockRepository: educationRepo,
      projectBlockRepository: projectRepo,
      certificationBlockRepository: certificationRepo,
      skillEntryRepository: skillRepo,
      customSectionBlockRepository: customSectionRepo,
    );
  });

  tearDown(() => db.close());

  const parser = ResumeImportParser();
  const renderer = ResumeTemplateRenderer();

  /// Imports [rawText] through the real parser and the real
  /// `ImportResumeUseCase.confirmImport`, reads the resume's composition
  /// back out of the real DB, compiles it into a [ResumeSnapshot] via the
  /// real [ResumeCompilerService], and renders it through one beta template
  /// as a smoke check that the compiled snapshot is actually renderable -
  /// giving each scenario test everything it needs to compare "what the
  /// parser saw" against "what the database, compiler, and renderer
  /// actually produced."
  Future<(ParsedResumeDraft, ResumeSnapshot)> importAndCompile(String rawText, {String title = 'Test Resume'}) async {
    final draft = parser.parse(rawText);
    final resumeId = await importUseCase.confirmImport(draft, title: title);
    final resume = await resumeRepository.getById(resumeId);
    final refs = await resumeBlockRepository.getForResume(resumeId);
    final totalBlocks = draft.experience.length +
        draft.education.length +
        draft.projects.length +
        draft.certifications.length +
        draft.skills.length +
        draft.customSections.length;
    expect(
      refs.length,
      totalBlocks,
      reason: 'every parsed block must be attached to the resume exactly once - no silent drop, no duplicate attach',
    );
    final snapshot = await compiler.compile(resume!, refs);
    final pdfBytes = await renderer.render(snapshot, ResumeTemplateCatalog.enabled.first);
    expect(pdfBytes, isNotEmpty);
    expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
    return (draft, snapshot);
  }

  group('Scenario A - a normal, realistic resume', () {
    test('every field survives import -> database -> compiled snapshot -> rendered PDF', () async {
      final (draft, snapshot) = await importAndCompile(_normalResumeText, title: 'Ravi - Normal');

      expect(draft.fullName, 'Ravi Kapoor');
      expect(draft.email, 'ravi.kapoor@example.com');
      expect(draft.phone, '(206) 555-0113');
      // Physical-Mobile-First Validation phase: ParsedResumeDraft.location
      // is now detected (a "City, ST" preamble line - the near-universal
      // US resume convention) instead of always being null - see
      // resume_import_parser.dart's own _locationPattern/_detectLocation.
      // Never appears in unclassifiedText once it's been classified.
      expect(draft.location, 'Seattle, WA');
      expect(draft.unclassifiedText, isNot(contains('Seattle, WA')));
      // Real-device beta fix: _extractLinks is now scoped to the preamble
      // only (the same reasoning already applied to phone detection) - a
      // real resume's project-specific GitHub link (already preserved as
      // *that project's own* `link` field, see expectProjectsPreserved
      // below) was previously ALSO being added here as if it were a
      // personal profile link, rendering the same link twice in the
      // header. `draft.links` now legitimately has just the one LinkedIn
      // profile URL from the preamble.
      expect(draft.links, hasLength(1));
      expect(draft.links.single.label, 'LinkedIn');
      expect(snapshot.profile.fullName, draft.fullName);
      expect(snapshot.profile.email, draft.email);
      expect(snapshot.profile.phone, draft.phone);
      expect(snapshot.profile.location, draft.location);
      // ResumeLink has no `==` override (a plain value class serialized to
      // JSON, see lib/models/resume_link.dart) - compare by field, not by
      // list identity/equality.
      expect(
        snapshot.profile.links.map((l) => (l.label, l.url)).toList(),
        draft.links.map((l) => (l.label, l.url)).toList(),
      );

      expectExperiencePreserved(draft.experience, snapshot.experience);
      expectEducationPreserved(draft.education, snapshot.education);
      expectProjectsPreserved(draft.projects, snapshot.projects);
      expectCertificationsPreserved(draft.certifications, snapshot.certifications);
      expectSkillsPreserved(draft.skills, snapshot.skills);
      expectCustomSectionsPreserved(draft.customSections, snapshot.customSections);

      expect(draft.experience, hasLength(2));
      expect(draft.projects, hasLength(2));
      expect(draft.certifications, hasLength(1));
      expect(draft.skills.length, greaterThanOrEqualTo(10));
      // Physical-Mobile-First Validation phase: the SUMMARY paragraph is
      // now its own "Summary" custom section, inserted first - see the
      // next test for the full behavior this replaced.
      expect(draft.customSections, hasLength(2));
      expect(draft.customSections[0].title, 'Summary');
      expect(draft.customSections[1].title, 'AWARDS');
    });

    test('Physical-Mobile-First Validation phase: the SUMMARY paragraph is imported as a real '
        '"Summary" custom section and survives confirmImport into the database for real - it used '
        'to only ever reach unclassifiedText, which confirmImport never persists, so in practice '
        'the summary was silently lost on import unless the user copied it in manually', () async {
      final draft = parser.parse(_normalResumeText);
      final summarySection = draft.customSections.firstWhere((s) => s.title == 'Summary');
      expect(summarySection.entries, ['Backend engineer with 6 years building distributed systems in Go and Python.']);
      expect(
        draft.unclassifiedText.any((b) => b.contains('Backend engineer with 6 years')),
        isFalse,
        reason: 'it is classified now, not left for manual review',
      );

      final resumeId = await importUseCase.confirmImport(draft, title: 'Ravi - Normal');
      final resume = await resumeRepository.getById(resumeId);
      final refs = await resumeBlockRepository.getForResume(resumeId);
      final snapshot = await compiler.compile(resume!, refs);
      final everyCustomSectionEntry = snapshot.customSections.expand((s) => s.entries).join(' ');
      expect(
        everyCustomSectionEntry.contains('Backend engineer with 6 years'),
        isTrue,
        reason: 'the summary is genuinely in the database now, reachable through the same '
            'ResumeBlockRef/CustomSectionBlock path every other custom section already uses',
      );
    });
  });

  group('Scenario B - a long-career resume (8 roles, 2+ pages)', () {
    test('all 8 roles survive with every bullet intact', () async {
      final rawText = _longCareerText(roleCount: 8);
      final (draft, snapshot) = await importAndCompile(rawText, title: 'Devika - Long Career');

      expect(draft.experience, hasLength(8));
      expectExperiencePreserved(draft.experience, snapshot.experience);
      for (final entry in snapshot.experience) {
        expect(entry.bullets, hasLength(4));
      }
      expect(snapshot.experience.last.endDate, isNull, reason: 'the most recent role is open-ended ("Present")');
      expectEducationPreserved(draft.education, snapshot.education);
    });
  });

  group('Scenario C - a resume with 12 distinct section types', () {
    test('all 6 typed sections and all 6 custom sections survive, in order, with nothing merged', () async {
      final (draft, snapshot) = await importAndCompile(_twelveSectionTypesText, title: 'Felix - 12 Sections');

      expect(draft.experience, hasLength(2));
      expect(draft.education, hasLength(1));
      expect(draft.projects, hasLength(1));
      expect(draft.certifications, hasLength(1));
      expect(draft.skills, isNotEmpty);
      // 7, not 6: the fixture's own SUMMARY section is now imported too,
      // as a "Summary" custom section prepended ahead of the others.
      expect(draft.customSections, hasLength(7));
      expect(
        draft.customSections.map((s) => s.title).toList(),
        ['Summary', 'AWARDS', 'PUBLICATIONS', 'VOLUNTEER EXPERIENCE', 'LANGUAGES', 'INTERESTS', 'REFERENCES'],
        reason: 'custom section order must match the original document order',
      );

      expectExperiencePreserved(draft.experience, snapshot.experience);
      expectEducationPreserved(draft.education, snapshot.education);
      expectProjectsPreserved(draft.projects, snapshot.projects);
      expectCertificationsPreserved(draft.certifications, snapshot.certifications);
      expectSkillsPreserved(draft.skills, snapshot.skills);
      expectCustomSectionsPreserved(draft.customSections, snapshot.customSections);
    });
  });

  group('Scenario D - unusual/custom section names', () {
    test('non-standard section titles are preserved verbatim, distinct, and not merged into one another', () async {
      final (draft, snapshot) = await importAndCompile(_unusualSectionNamesText, title: 'Camille - Unusual Sections');

      expect(
        draft.customSections.map((s) => s.title).toList(),
        ['RANDOM ACCOMPLISHMENTS', 'OPEN SOURCE CONTRIBUTIONS', 'THINGS I AM PROUD OF', 'SPEAKING ENGAGEMENTS'],
      );
      expect(draft.customSections[0].entries, ['Shipped a side project with 10,000 downloads in its first month.']);
      expect(draft.customSections[1].entries, ['Maintainer of a CSS utility library with 2,000 GitHub stars.']);
      expect(draft.customSections[2].entries, ['Mentored five junior designers into mid-level roles.']);
      expect(draft.customSections[3].entries, ['Spoke at Design Systems Conference 2022 on componentization.']);

      expectCustomSectionsPreserved(draft.customSections, snapshot.customSections);
      expectExperiencePreserved(draft.experience, snapshot.experience);
      expectEducationPreserved(draft.education, snapshot.education);
    });
  });

  group('Scenario E - 10+ projects', () {
    test('all 12 projects survive with their links and bullets, in order', () async {
      final rawText = _manyProjectsText(projectCount: 12);
      final (draft, snapshot) = await importAndCompile(rawText, title: 'Owen - Many Projects');

      expect(draft.projects, hasLength(12));
      expectProjectsPreserved(draft.projects, snapshot.projects);
      for (var i = 0; i < 12; i++) {
        expect(draft.projects[i].name, 'Project Alpha ${i + 1}');
        expect(draft.projects[i].link, i.isEven ? 'https://github.com/ofitz/project-alpha-${i + 1}' : null);
      }
    });
  });

  group('Scenario F - 15-20 skills', () {
    test('all 18 skills survive with no de-duplication or truncation', () async {
      final rawText = _manySkillsText(skillCount: 18);
      final (draft, snapshot) = await importAndCompile(rawText, title: 'Nadia - Many Skills');

      expect(draft.skills, hasLength(18));
      expectSkillsPreserved(draft.skills, snapshot.skills);
      expect(draft.skills.map((s) => s.name).toList(), List.generate(18, (i) => 'Skill${i + 1}'));
    });
  });

  group('Scenario G - missing/unusual dates', () {
    test('a role with no confident date range is never fabricated a date - it is left for manual review, and the '
        'two well-dated roles still import cleanly', () async {
      final draft = parser.parse(_missingUnusualDatesText);

      expect(draft.experience, hasLength(2), reason: 'only the two roles with a confident date range structure');
      expect(draft.experience[0].role, 'Engineer');
      expect(draft.experience[0].company, 'Acme Corp');
      expect(draft.experience[0].startDate, '2018');
      expect(draft.experience[0].endDate, '2020');
      expect(draft.experience[1].role, 'Senior Engineer');
      expect(draft.experience[1].company, 'Beta Corp');
      expect(draft.experience[1].startDate, '2020');
      expect(draft.experience[1].endDate, isNull, reason: '"Present" must resolve to an open-ended null endDate');

      expect(
        draft.unclassifiedText.any((b) => b.contains('Gamma Corp')),
        isTrue,
        reason: 'the undated Contractor/Gamma Corp entry must still be visible for manual review',
      );
      expect(
        draft.experience.any((e) => e.company == 'Gamma Corp'),
        isFalse,
        reason: 'no fabricated start/end date may ever be invented for the Gamma Corp entry',
      );
      expect(draft.warnings, isNotEmpty);

      final (_, snapshot) = await importAndCompile(_missingUnusualDatesText, title: 'Tomas - Unusual Dates');
      expect(snapshot.experience, hasLength(2));
      expect(
        snapshot.experience.any((e) => e.company == 'Gamma Corp'),
        isFalse,
        reason: 'the undated entry must not reappear anywhere downstream of the parser either',
      );
    });
  });

  group('Scenario H - an unusual section order', () {
    test('sections are still correctly classified when Skills/custom sections come before Experience/Education',
        () async {
      final (draft, snapshot) = await importAndCompile(_unusualSectionOrderText, title: 'Priya - Unusual Order');

      expect(draft.skills.map((s) => s.name).toList(), ['Java', 'Spring Boot', 'PostgreSQL', 'AWS', 'Docker']);
      expect(draft.customSections.map((s) => s.title).toList(), ['LANGUAGES', 'INTERESTS']);
      expect(draft.experience, hasLength(1));
      expect(draft.experience.single.company, 'Delta Systems');
      expect(draft.education, hasLength(1));
      expect(draft.education.single.institution, 'University of Texas at Austin');
      expect(draft.projects, hasLength(1));
      expect(draft.certifications, hasLength(1));

      expectSkillsPreserved(draft.skills, snapshot.skills);
      expectCustomSectionsPreserved(draft.customSections, snapshot.customSections);
      expectExperiencePreserved(draft.experience, snapshot.experience);
      expectEducationPreserved(draft.education, snapshot.education);
      expectProjectsPreserved(draft.projects, snapshot.projects);
      expectCertificationsPreserved(draft.certifications, snapshot.certifications);
    });
  });
}
