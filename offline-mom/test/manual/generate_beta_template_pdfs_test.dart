// Manual PDF-generation script (Product Validation phase, Phase 8/9) - NOT
// part of the regular regression suite. Runs the real, unmodified
// ResumeImportParser against a realistic DevOps/Cloud-engineer resume, then
// renders the result through all 5 beta templates via the real,
// unmodified ResumeTemplateRenderer, writing actual PDF bytes to disk so
// they can be opened and visually inspected - "actually render, actually
// inspect," never a textual claim that "templates look good."
//
// Run with: flutter test test/manual/generate_beta_template_pdfs_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

const _mediumResumeText = '''
Sarah Chen
sarah.chen@example.com | (415) 555-0142
San Francisco, CA
https://linkedin.com/in/sarahchen https://github.com/schen-devops

SUMMARY

Cloud infrastructure engineer with 8+ years automating deployments and reducing operational toil across AWS and Azure. Specializes in Kubernetes, GitOps delivery pipelines, and infrastructure as code.

EXPERIENCE

Senior DevOps Engineer - Cloudra Systems
2022 - Present
- Led migration of 40+ microservices from EC2 to a fully containerized Kubernetes platform on AWS EKS, cutting infrastructure costs by 32%.
- Designed and implemented a GitOps-based CI/CD pipeline using ArgoCD and GitHub Actions, reducing deployment time from 45 minutes to under 6 minutes.
- Owned Terraform modules provisioning multi-account AWS infrastructure across dev, staging, and production environments.
- Mentored a team of 4 junior engineers on Kubernetes operations and incident response.

DevOps Engineer - Northbridge Analytics
2019 - 2022
- Built and maintained CI/CD pipelines in Jenkins for 15 Java and Python microservices.
- Automated provisioning of Azure infrastructure using Terraform and Azure Resource Manager templates.
- Implemented centralized logging and monitoring with the ELK stack and Prometheus/Grafana.
- Reduced production incident MTTR by 40 percent by introducing automated rollback triggers.

Site Reliability Engineer - Vantage Retail Group
2017 - 2019
- On-call rotation for a 99.95 percent SLA e-commerce platform serving 2 million monthly users.
- Wrote runbooks and automated remediation scripts for the ten most common production incidents.
- Migrated legacy Chef-managed servers to Ansible playbooks, improving provisioning time by 60 percent.

EDUCATION

B.S. in Computer Science - University of Washington
2011 - 2015

PROJECTS

Kubernetes Cost Optimizer
https://github.com/schen-devops/k8s-cost-optimizer
- Built an open-source tool that analyzes EKS cluster resource requests versus actual usage and recommends right-sizing changes.
- Adopted by three other engineering teams internally before being open-sourced.

Terraform AWS Landing Zone Module
- Published a reusable Terraform module for standing up a secure multi-account AWS landing zone in under 20 minutes.

CERTIFICATIONS

AWS Certified Solutions Architect - Professional - Amazon Web Services
Issued 2023

Certified Kubernetes Administrator - Cloud Native Computing Foundation
Issued 2022

SKILLS

Kubernetes, AWS, Azure, Terraform, Docker, Jenkins, ArgoCD, GitHub Actions, Python, Ansible, Prometheus, Grafana

AWARDS

Cloudra Systems Engineering Excellence Award, 2023
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a realistic DevOps resume and renders it through all 5 beta '
      'templates, writing real PDF files for visual inspection', () async {
    const parser = ResumeImportParser();
    final draft = parser.parse(_mediumResumeText);

    // Fidelity assertions - fail loudly here (before any PDF is even
    // written) if the real parser dropped anything, rather than silently
    // rendering an incomplete resume.
    expect(draft.fullName, 'Sarah Chen');
    expect(draft.email, 'sarah.chen@example.com');
    expect(draft.experience, hasLength(3), reason: 'all 3 jobs must survive import');
    expect(draft.projects, hasLength(2), reason: 'both projects must survive import');
    expect(draft.certifications, hasLength(2));
    expect(draft.education, hasLength(1));
    expect(draft.skills.length, greaterThanOrEqualTo(10));
    // Physical-Mobile-First Validation phase: SUMMARY is now imported as
    // its own "Summary" custom section (prepended ahead of AWARDS)
    // instead of only reaching unclassifiedText.
    expect(draft.customSections, hasLength(2), reason: 'Summary and AWARDS must both survive as custom sections');
    expect(draft.customSections[0].title, 'Summary');
    expect(draft.customSections[1].title, 'AWARDS');

    final snapshot = ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: ResumeSnapshotProfile(
        fullName: draft.fullName!,
        email: draft.email,
        phone: draft.phone,
        location: draft.location,
        links: draft.links,
        roleTagline: 'Senior DevOps Engineer',
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
            details: draft.education[i].details,
          ),
      ],
      projects: [
        for (var i = 0; i < draft.projects.length; i++)
          ResolvedProjectEntry(
            sourceBlockId: i,
            name: draft.projects[i].name,
            link: draft.projects[i].link,
            bullets: draft.projects[i].bullets,
          ),
      ],
      certifications: [
        for (var i = 0; i < draft.certifications.length; i++)
          ResolvedCertificationEntry(
            sourceBlockId: i,
            name: draft.certifications[i].name,
            issuer: draft.certifications[i].issuer,
            issuedDate: draft.certifications[i].issuedDate,
          ),
      ],
      skills: [
        for (var i = 0; i < draft.skills.length; i++)
          ResolvedSkillEntry(sourceBlockId: i, name: draft.skills[i].name, category: draft.skills[i].category),
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

    const fileNameByArchetype = {
      'two-column-right': 'beta_balanced_two_column.pdf',
      'classic-single-column': 'beta_classic.pdf',
      'modern-accent-column': 'beta_modern_accent.pdf',
      'executive-summary-led': 'beta_executive_summary.pdf',
      'minimalist-monochrome': 'beta_minimalist_monochrome.pdf',
    };

    expect(ResumeTemplateCatalog.enabled, hasLength(5), reason: 'exactly the 5 beta templates');

    for (final spec in ResumeTemplateCatalog.enabled) {
      final bytes = await renderer.render(snapshot, spec);
      expect(bytes, isNotEmpty);
      // A real PDF starts with the "%PDF-" magic bytes - a cheap, direct
      // check that this is a genuine PDF file, not empty/corrupt output.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

      final fileName = fileNameByArchetype[spec.archetypeId];
      expect(fileName, isNotNull, reason: 'unexpected beta archetype id: ${spec.archetypeId}');
      final file = File('${outDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      // ignore: avoid_print
      print('Wrote ${file.path} (${bytes.length} bytes) - ${spec.displayName}');
    }
  });

  test('a long-career, multi-job resume renders through Balanced '
      'Two-Column across multiple pages without losing any entry', () async {
    const parser = ResumeImportParser();
    final buffer = StringBuffer()
      ..writeln('Marcus Alvarez')
      ..writeln('marcus.alvarez@example.com | (312) 555-0199')
      ..writeln('Chicago, IL')
      ..writeln()
      ..writeln('EXPERIENCE')
      ..writeln();
    const roles = [
      ('Principal Cloud Architect', 'Meridian Financial', '2023', 'Present'),
      ('Staff DevOps Engineer', 'Northwind Logistics', '2020', '2023'),
      ('Senior Site Reliability Engineer', 'Beacon Health Systems', '2017', '2020'),
      ('DevOps Engineer', 'Cascade Software', '2014', '2017'),
      ('Systems Engineer', 'Cascade Software', '2011', '2014'),
      ('Linux Administrator', 'DataForge Hosting', '2008', '2011'),
    ];
    for (final (role, company, start, end) in roles) {
      buffer
        ..writeln('$role - $company')
        ..writeln('$start - $end')
        ..writeln('- Owned production infrastructure reliability for $company, driving measurable uptime improvements.')
        ..writeln('- Designed and rolled out automated deployment tooling adopted across the engineering organization.')
        ..writeln('- Partnered with security and compliance teams to close audit findings ahead of schedule.')
        ..writeln('- Coached and onboarded new engineers into the team\'s operational practices.')
        ..writeln();
    }
    buffer
      ..writeln('EDUCATION')
      ..writeln()
      ..writeln('B.S. in Information Systems - Illinois State University')
      ..writeln('2004 - 2008');

    final draft = parser.parse(buffer.toString());
    expect(draft.experience, hasLength(roles.length), reason: 'all 6 jobs must survive import');

    final snapshot = ResumeSnapshot(
      resumeId: 2,
      compiledAt: DateTime(2026, 1, 1),
      profile: ResumeSnapshotProfile(
        fullName: draft.fullName!,
        email: draft.email,
        phone: draft.phone,
        location: draft.location,
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
    );

    const renderer = ResumeTemplateRenderer();
    final spec = ResumeTemplateCatalog.specById('two-column-right-warm');
    final bytes = await renderer.render(snapshot, spec);
    expect(bytes, isNotEmpty);

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/beta_balanced_two_column_long_career_multipage.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('Wrote ${file.path} (${bytes.length} bytes)');
  });
}
