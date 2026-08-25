// Manual verification script (real-device beta fix, Phase 1 audit) - NOT
// part of the regular regression suite. Runs the ACTUAL text extracted from
// the user's real resume PDF through the real, unmodified
// ResumeImportParser, assembles a ResumeSnapshot from the parsed draft
// exactly the way ResumeCompilerService would, then renders it through the
// real, unmodified ResumeTemplateRenderer for all 5 beta templates - so the
// fix can be visually inspected against the real defect, not just asserted
// by a unit test.
//
// Run with: flutter test test/manual/verify_real_device_import_fix_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

// The exact text extracted from Harshavardhan_SoftwareEngineer_1yearexp.resume.pdf.
const _resumeText = '''
VADDE HARSHAVARDHAN (Python Developer)
Hyderabad, Telangana | iamharsha.vadde@gmail.com | 9035759795 | www.linkedin.com/in/vaddeharshavardhan | github.com/Harshavadde

PROFESSIONAL SUMMARY

Python Full Stack Developer with 1 year of professional experience in Python backend development and Android application
development. Skilled in Python, Django, FastAPI, REST APIs, SQL, and Linux, with strong knowledge of database management and
backend development. Experienced in building and deploying production-ready Android applications using Godot (GDScript) and
Android Studio, integrating Firebase, Cloudflare, and AWS S3, developing Java/Kotlin-based Android plugins (.aar), and publishing
APK/AAB builds through the Google Play Console. Strong problem-solving skills with experience working in Agile environments and
delivering scalable, high-quality software solutions.

SKILLS SUMMARY

Languages: Python, JavaScript, SQL
Backend: FastAPI, Django, Django REST Framework, REST APIs
Frontend: React.js, HTML, CSS
Databases: OracleSQL, SQLite, Subqueries, Views, Cursors, Indexes, Triggers, Stored Procedures & Functions
Machine Learning & Deep Learning: Machine Learning (ML), Deep Learning (DL), Model Training & Evaluation
Computer Vision: OpenCV, YOLO (Object Detection), CV Model Development
Cloud: AWS S3
Tools: Git, GitHub, Postman, Linux, VS Code

WORK EXPERIENCE

Software Engineer | Pranakshit IT Solutions December 2025 - Present | Hyderabad, India
- Developed and maintained Python-based data pipelines to extract, validate, and deploy multilingual educational content to
AWS S3, reducing manual QA effort by ~70% through Linux CLI automation.
- Designed database schemas and analytics pipelines to track student progress, institutional usage, and engagement, enabling
data-driven decisions across Class 6-10 learning platforms.
- Built Python validation scripts to ensure content integrity across English, Hindi, and Telugu, reducing deployment errors by
~60%.
- Created internal dashboards to monitor deployment status, user adoption, and content coverage, improving release visibility
for stakeholders.
SciLab (Web & Android) — Godot, GDScript, AWS S3, Google Play Console
- Developed and deployed SciLab for Web and Android using Godot (GDScript) to transform theoretical science learning into
conceptual learning using interactive simulations aligned with the NCERT curriculum.
- Implemented cloud-based content delivery using AWS S3, integrated analytics, and optimized deployment pipelines,
reducing content update time by ~50%.
- Published and maintained production releases through Google Play Console, improving application stability and accessibility
for educational institutions.
ByHeart (Web & Android) — MediaRecorder, Cloudflare Workers, Speech-to-Text
- Contributed to frontend and backend development of ByHeart, a voice-based active recall learning platform that helps
students improve concept retention by speaking textbook questions and answers instead of only reading them.
- Built the complete audio processing pipeline (MediaRecorder to 16 kHz Mono WAV) and integrated it with a Cloudflare
Worker backend for Speech-to-Text and AI-based answer evaluation.
- Resolved cross-browser voice input issues, codec compatibility, and mobile recording bugs, improving voice recognition
reliability by ~40%.
Crossword App (Web & Android) — Cloudflare Workers, Ollama LLM, Kotlin
- Developed features for a crossword-based educational platform that reinforces subject concepts through interactive puzzle-
solving, helping students shift from rote memorization to active learning.
- Migrated speech recognition from a third-party LLM API to a self-hosted pipeline using Cloudflare Workers, custom STT,
and Ollama LLM, eliminating external API dependency and reducing operational costs.
- Refactored Android speech modules in Kotlin, resolved authentication and payload integration issues, and improved
recognition accuracy for Indian English by ~30%.

Software Developer Intern | E-Commerce Analytics Dashboard June 2025 - November 2025 | Hyderabad, India
- Engineered an end-to-end analytics dashboard using Pandas and NumPy for data processing, with Matplotlib for visualizing
revenue trends, customer behavior, and inventory KPIs.
- Built and consumed Django REST Framework APIs to feed real-time transactional data into the analytics layer, enabling
live reporting.
- Performed data wrangling on raw e-commerce datasets - handling missing values, normalizing formats, and creating
aggregated summary tables for business reporting.

PROJECTS

AI Job Application Automation Platform — FastAPI, React.js, Playwright, SQLite
- Developed a full-stack platform that automates job applications across multiple job portals using Playwright.
- Built REST APIs with FastAPI to manage user profiles, resumes, job preferences, and automation workflows.
- Implemented browser automation for login, job search, resume upload, and multi-step application submission.
- Designed background job execution and tracking for long-running automation tasks.
- Added detailed logging, error handling, and application status monitoring.

AI Medical Emergency System — FastAPI, React.js, Gemini 2.0 Flash, LangChain RAG, ChromaDB, PostgreSQL
GitHub: github.com/Harshavadde/Ai_Medical_Emergency_System
- Built a full-stack GenAI healthcare platform enabling AI-powered medical guidance and locating the nearest hospital from a
database of 20,000+ hospitals across India.
- Designed a RAG pipeline using LangChain and ChromaDB vector search that retrieves relevant hospital and medical
context before every Gemini 2.0 Flash LLM call for grounded, accurate responses.
- Implemented real-time emergency detection by scanning for high-risk keywords and triggering a red-alert UI before the AI
response is generated.
- Built a PDF upload feature enabling dynamic RAG, indexing user-uploaded prescriptions and medical reports into
ChromaDB as live query context.

EDUCATION

Sri Venkateshwara College of Engineering August 2020 - June 2024 | Tirupathi, India
Bachelor of Technology - Electrical and Electronics Engineering

CERTIFICATIONS & ACHIEVEMENTS

- Top 20% on LeetCode with 100+ problems solved - strong foundation in DSA and problem solving
- Deployed 2 live production applications on Google Play Store used by schools across India
- Built and shipped open-source Scilab Mobile educational app used in real institutional environments
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render Harshavardhan\'s real resume through the fixed import pipeline for all 5 beta templates', () async {
    final draft = const ResumeImportParser().parse(_resumeText);

    // Diagnostics first - print what the parser actually recovered, so a
    // regression is visible in test output even without opening a PDF.
    // ignore: avoid_print
    print('fullName: ${draft.fullName}');
    // ignore: avoid_print
    print('location: ${draft.location}');
    // ignore: avoid_print
    print('experience entries: ${draft.experience.length}');
    for (final e in draft.experience) {
      final chars = e.bullets.fold<int>(0, (sum, b) => sum + b.length);
      // ignore: avoid_print
      print('  - ${e.role} | ${e.company}: ${e.bullets.length} bullets, $chars chars');
      for (final sub in e.subProjects) {
        // ignore: avoid_print
        print('      sub-project: ${sub.name} (${sub.bullets.length} bullets)');
      }
    }
    // ignore: avoid_print
    print('education entries: ${draft.education.length}');
    // ignore: avoid_print
    print('projects entries: ${draft.projects.length}');
    // ignore: avoid_print
    print('skills entries: ${draft.skills.length}');
    // ignore: avoid_print
    print('certifications entries: ${draft.certifications.length}');
    // ignore: avoid_print
    print('custom sections: ${draft.customSections.map((s) => s.title).toList()}');
    // ignore: avoid_print
    print('unclassified blocks: ${draft.unclassifiedText.length}');
    // ignore: avoid_print
    print('warnings: ${draft.warnings}');

    expect(draft.fullName, 'VADDE HARSHAVARDHAN');
    expect(draft.experience, isNotEmpty);
    expect(draft.education, isNotEmpty);

    // Migration v20 / Resume -> Experience -> Project -> Project bullets
    // architecture: the real "Software Engineer" entry lists three named
    // sub-projects (SciLab, ByHeart, Crossword App), each with its own
    // bullets - previously flattened into 16 indistinguishable bullets on
    // the parent entry, now structurally distinct.
    final softwareEngineer = draft.experience.firstWhere((e) => e.role == 'Software Engineer');
    expect(
      softwareEngineer.subProjects.map((s) => s.name).toList(),
      containsAll([
        contains('SciLab'),
        contains('ByHeart'),
        contains('Crossword'),
      ]),
    );
    for (final sub in softwareEngineer.subProjects) {
      expect(sub.bullets, isNotEmpty, reason: '${sub.name} lost its own bullets during structuring');
    }

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
        final file = File('${outDir.path}/harshavardhan_fixed_$safeName.pdf');
        await file.writeAsBytes(bytes);
        // ignore: avoid_print
        print('OK   ${spec.displayName}: wrote ${file.path} (${bytes.length} bytes)');
      } catch (e) {
        // ignore: avoid_print
        print('FAIL ${spec.displayName}: $e');
      }
    }
  });
}
