// Tests PrioritizeResumeContentUseCase
// (lib/features/career/analysis/prioritize_resume_content_use_case.dart) -
// a pure, deterministic re-ranker, no database/AI/network - docs/v3/01-prd.md
// §25 Milestone 2, hard requirement 5.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/analysis/prioritize_resume_content_use_case.dart';
import 'package:offline_mom/models/experience_block.dart' show ExperienceSubProject;
import 'package:offline_mom/models/resume_jd_analysis_result.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';

void main() {
  const useCase = PrioritizeResumeContentUseCase();

  ResumeSnapshot buildSnapshot({
    List<ResolvedExperienceEntry> experience = const [],
    List<ResolvedProjectEntry> projects = const [],
    List<ResolvedSkillEntry> skills = const [],
    List<ResolvedEducationEntry> education = const [],
    List<ResolvedCertificationEntry> certifications = const [],
  }) {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      experience: experience,
      projects: projects,
      skills: skills,
      education: education,
      certifications: certifications,
    );
  }

  ResumeJdAnalysisResult buildAnalysisResult(List<String?> evidenceStrings) {
    return ResumeJdAnalysisResult(
      skillMatches: [
        for (final evidence in evidenceStrings)
          SkillMatchResult(
            jdRequirement: 'req for $evidence',
            level: evidence == null ? MatchLevel.missing : MatchLevel.exact,
            resumeEvidence: evidence,
            matchSource: evidence == null ? null : MatchSource.exactKeyword,
          ),
      ],
      experienceCheck: const ExperienceCheckResult(summary: 'n/a'),
    );
  }

  group('experience reordering', () {
    test('an entry whose role/company or bullets matched more requirements moves first', () {
      const lowMatch = ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Support Engineer',
        company: 'Acme',
        startDate: '2019-01',
        bullets: ['Answered customer tickets'],
      );
      const highMatch = ResolvedExperienceEntry(
        sourceBlockId: 2,
        role: 'Backend Engineer',
        company: 'Globex',
        startDate: '2021-01',
        bullets: ['Built Kubernetes deployment pipelines', 'Wrote Terraform modules'],
      );
      final snapshot = buildSnapshot(experience: [lowMatch, highMatch]);
      final analysisResult = buildAnalysisResult([
        'Built Kubernetes deployment pipelines',
        'Wrote Terraform modules',
      ]);

      final result = useCase(snapshot, analysisResult);

      expect(result.experience.first.sourceBlockId, 2);
      expect(result.experience.last.sourceBlockId, 1);
    });

    test('entries with equal match density (including zero) preserve their original relative order', () {
      const first = ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Role A',
        company: 'Company A',
        startDate: '2019-01',
      );
      const second = ResolvedExperienceEntry(
        sourceBlockId: 2,
        role: 'Role B',
        company: 'Company B',
        startDate: '2020-01',
      );
      const third = ResolvedExperienceEntry(
        sourceBlockId: 3,
        role: 'Role C',
        company: 'Company C',
        startDate: '2021-01',
      );
      final snapshot = buildSnapshot(experience: [first, second, third]);
      final analysisResult = buildAnalysisResult([]);

      final result = useCase(snapshot, analysisResult);

      expect(result.experience.map((e) => e.sourceBlockId), [1, 2, 3]);
    });

    test('semantic-tier matches count toward density exactly like deterministic ones', () {
      const entry = ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Data Analyst',
        company: 'Acme',
        startDate: '2019-01',
        bullets: ['Built dashboards in spreadsheet software'],
      );
      const other = ResolvedExperienceEntry(
        sourceBlockId: 2,
        role: 'Unrelated',
        company: 'Other Co',
        startDate: '2018-01',
      );
      final snapshot = buildSnapshot(experience: [other, entry]);
      const analysisResult = ResumeJdAnalysisResult(
        skillMatches: [
          SkillMatchResult(
            jdRequirement: 'Spreadsheet proficiency',
            level: MatchLevel.partial,
            resumeEvidence: 'Built dashboards in spreadsheet software',
            matchSource: MatchSource.semanticEmbedding,
          ),
        ],
        experienceCheck: ExperienceCheckResult(summary: 'n/a'),
      );

      final result = useCase(snapshot, analysisResult);

      expect(result.experience.first.sourceBlockId, 1);
    });

    test(
      'Part H (JD tailoring re-verification): an entry whose only matched evidence lives inside a '
      "sub-project's own bullets (D-M9-01) still moves first, not scored as zero density",
      () {
        const lowMatch = ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Support Engineer',
          company: 'Acme',
          startDate: '2019-01',
          bullets: ['Answered customer tickets'],
        );
        const subProjectMatch = ResolvedExperienceEntry(
          sourceBlockId: 2,
          role: 'Software Engineer',
          company: 'Globex',
          startDate: '2021-01',
          bullets: ['Led the platform team'],
          subProjects: [
            ExperienceSubProject(
              name: 'SciLab',
              bullets: ['Deployed the app using Kubernetes and Docker'],
            ),
          ],
        );
        final snapshot = buildSnapshot(experience: [lowMatch, subProjectMatch]);
        final analysisResult = buildAnalysisResult(['Deployed the app using Kubernetes and Docker']);

        final result = useCase(snapshot, analysisResult);

        expect(result.experience.first.sourceBlockId, 2);
      },
    );
  });

  group('project and skill reordering', () {
    test('projects are reordered by the same density rule as experience', () {
      const lowMatch = ResolvedProjectEntry(sourceBlockId: 1, name: 'Recipe App');
      const highMatch = ResolvedProjectEntry(
        sourceBlockId: 2,
        name: 'Distributed Cache',
        bullets: ['Implemented Kubernetes operator'],
      );
      final snapshot = buildSnapshot(projects: [lowMatch, highMatch]);
      final analysisResult = buildAnalysisResult(['Implemented Kubernetes operator']);

      final result = useCase(snapshot, analysisResult);

      expect(result.projects.first.sourceBlockId, 2);
    });

    test('skills are reordered so a matched skill surfaces first', () {
      const unmatched = ResolvedSkillEntry(sourceBlockId: 1, name: 'Photoshop', category: SkillCategory.technical);
      const matched = ResolvedSkillEntry(sourceBlockId: 2, name: 'Kubernetes', category: SkillCategory.technical);
      final snapshot = buildSnapshot(skills: [unmatched, matched]);
      final analysisResult = buildAnalysisResult(['Kubernetes']);

      final result = useCase(snapshot, analysisResult);

      expect(result.skills.first.sourceBlockId, 2);
    });
  });

  group('content preservation', () {
    test('no entry field is ever changed - only list order moves', () {
      const entry = ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Backend Engineer',
        company: 'Globex',
        startDate: '2021-01',
        bullets: ['Built Kubernetes deployment pipelines'],
      );
      final snapshot = buildSnapshot(experience: [entry]);
      final analysisResult = buildAnalysisResult(['Built Kubernetes deployment pipelines']);

      final result = useCase(snapshot, analysisResult);

      expect(result.experience.single, entry);
    });

    test(
      'Part H (JD tailoring re-verification): sub-project bullets contributing to reordering are '
      'never rewritten, added, or removed - only list order moves',
      () {
        const entry = ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Software Engineer',
          company: 'Globex',
          startDate: '2021-01',
          bullets: ['Led the platform team'],
          subProjects: [
            ExperienceSubProject(
              name: 'SciLab',
              bullets: ['Deployed the app using Kubernetes and Docker'],
            ),
          ],
        );
        final snapshot = buildSnapshot(experience: [entry]);
        final analysisResult = buildAnalysisResult(['Deployed the app using Kubernetes and Docker']);

        final result = useCase(snapshot, analysisResult);

        expect(result.experience.single, entry);
        expect(result.experience.single.subProjects, entry.subProjects);
      },
    );

    test('education and certifications are left completely untouched, in original order', () {
      const educationEntries = [
        ResolvedEducationEntry(
          sourceBlockId: 1,
          institution: 'State University',
          degree: 'B.Sc',
          startDate: '2015-09',
        ),
        ResolvedEducationEntry(
          sourceBlockId: 2,
          institution: 'City College',
          degree: 'M.Sc',
          startDate: '2019-09',
        ),
      ];
      const certificationEntries = [
        ResolvedCertificationEntry(sourceBlockId: 3, name: 'Cert A', issuer: 'Issuer A'),
        ResolvedCertificationEntry(sourceBlockId: 4, name: 'Cert B', issuer: 'Issuer B'),
      ];
      final snapshot = buildSnapshot(education: educationEntries, certifications: certificationEntries);
      final analysisResult = buildAnalysisResult([]);

      final result = useCase(snapshot, analysisResult);

      expect(result.education, educationEntries);
      expect(result.certifications, certificationEntries);
    });

    test('the profile and every other snapshot-level field are untouched', () {
      final snapshot = buildSnapshot();
      final analysisResult = buildAnalysisResult([]);

      final result = useCase(snapshot, analysisResult);

      expect(result.resumeId, snapshot.resumeId);
      expect(result.compiledAt, snapshot.compiledAt);
      expect(result.profile, snapshot.profile);
    });

    test('an empty snapshot produces an empty (unchanged) result, never a crash', () {
      final snapshot = buildSnapshot();
      final analysisResult = buildAnalysisResult([]);

      final result = useCase(snapshot, analysisResult);

      expect(result.experience, isEmpty);
      expect(result.projects, isEmpty);
      expect(result.skills, isEmpty);
    });
  });

  group('determinism', () {
    test('re-running with an identical analysis result always produces an identical order', () {
      const a = ResolvedExperienceEntry(sourceBlockId: 1, role: 'Role A', company: 'A', startDate: '2019-01');
      const b = ResolvedExperienceEntry(
        sourceBlockId: 2,
        role: 'Role B',
        company: 'B',
        startDate: '2020-01',
        bullets: ['Kubernetes work'],
      );
      final snapshot = buildSnapshot(experience: [a, b]);
      final analysisResult = buildAnalysisResult(['Kubernetes work']);

      final first = useCase(snapshot, analysisResult);
      final second = useCase(snapshot, analysisResult);

      expect(first.experience.map((e) => e.sourceBlockId), second.experience.map((e) => e.sourceBlockId));
    });
  });
}
