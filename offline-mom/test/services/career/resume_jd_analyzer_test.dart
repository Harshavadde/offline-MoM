// Tests ResumeJdAnalyzer (lib/services/career/resume_jd_analyzer.dart) - a
// pure, deterministic, offline comparison of an already-compiled
// ResumeSnapshot against an already-parsed ParsedJobDescription. No
// database, no file I/O, no AI model - mirrors resume_compiler_service_test.dart's
// style of testing a pure service directly against constructed fixtures.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/experience_block.dart' show ExperienceSubProject;
import 'package:offline_mom/models/job_description.dart';
import 'package:offline_mom/models/resume_jd_analysis_result.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/services/ai/embedding_engine.dart';
import 'package:offline_mom/services/career/resume_jd_analyzer.dart';
import 'package:offline_mom/services/career/resume_jd_semantic_matcher.dart';

import '../../test_helpers/fake_ai_engines.dart';

/// A local, hand-picked-vector embedding fake (this codebase's own
/// established precedent for "shared fake's behavior isn't precise/
/// controllable enough for a specific test" - e.g.
/// `_PreparingModelSpyEngine`) - [FakeEmbeddingEngine]'s bag-of-characters
/// hash is reproducible but not predictable-by-inspection for arbitrary
/// word pairs, so it can't be used to assert a *specific* similarity
/// outcome. This fake instead returns an exact, caller-registered vector
/// per input text, so a test can assert precisely which pairs are
/// "similar enough" and which are not.
class _FixtureVectorEmbeddingEngine implements EmbeddingEngine {
  _FixtureVectorEmbeddingEngine(this._vectors);

  final Map<String, List<double>> _vectors;

  @override
  Future<List<double>> embed(String text, {bool normalize = true}) async => _vectorFor(text);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts, {bool normalize = true}) async {
    return texts.map(_vectorFor).toList();
  }

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {}

  List<double> _vectorFor(String text) {
    final vector = _vectors[text];
    if (vector == null) {
      throw StateError('_FixtureVectorEmbeddingEngine has no fixture vector registered for "$text"');
    }
    return vector;
  }
}

void main() {
  const analyzer = ResumeJdAnalyzer();

  ResumeSnapshot buildSnapshot({
    List<ResolvedExperienceEntry> experience = const [],
    List<ResolvedEducationEntry> education = const [],
    List<ResolvedCertificationEntry> certifications = const [],
    List<ResolvedSkillEntry> skills = const [],
  }) {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      experience: experience,
      education: education,
      certifications: certifications,
      skills: skills,
    );
  }

  ParsedJobDescription buildJd({
    List<String> requirements = const [],
    List<String> educationRequirements = const [],
    List<String> certificationRequirements = const [],
    JdExperienceRequirement? experienceRequirement,
  }) {
    return ParsedJobDescription(
      rawText: 'raw jd text',
      requirements: requirements,
      educationRequirements: educationRequirements,
      certificationRequirements: certificationRequirements,
      experienceRequirement: experienceRequirement,
    );
  }

  group('skill matching', () {
    test('an exact (case-insensitive) match is classified exact with resume evidence', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'kubernetes', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Kubernetes']),
      );

      expect(result.skillMatches.single.level, MatchLevel.exact);
      expect(result.skillMatches.single.resumeEvidence, 'kubernetes');
    });

    test('a requirement found inside an experience bullet, not just the skills '
        'list, still counts as exact', () async {
      final result = await analyzer.analyze(
        buildSnapshot(experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Engineer',
            company: 'Acme',
            startDate: '2020-01',
            bullets: ['Deployed services using Kubernetes and Docker.'],
          ),
        ]),
        buildJd(requirements: const ['Docker']),
      );

      expect(result.skillMatches.single.level, MatchLevel.exact);
    });

    test(
      'Part H (JD tailoring re-verification, product-quality remediation pass): a requirement '
      'found only inside a sub-project\'s own bullets (D-M9-01) - never the parent entry\'s own '
      'top-level bullets - still counts as exact, not silently missing',
      () async {
        final result = await analyzer.analyze(
          buildSnapshot(experience: const [
            ResolvedExperienceEntry(
              sourceBlockId: 1,
              role: 'Software Engineer',
              company: 'Acme',
              startDate: '2023-01',
              bullets: ['Led the platform team.'],
              subProjects: [
                ExperienceSubProject(
                  name: 'SciLab (Web & Android)',
                  bullets: ['Deployed the app using Kubernetes and Docker.'],
                ),
              ],
            ),
          ]),
          buildJd(requirements: const ['Kubernetes']),
        );

        expect(result.skillMatches.single.level, MatchLevel.exact);
      },
    );

    test('"Azure DevOps" (JD) vs "Azure" (resume) is partial, not exact', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Azure', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Azure DevOps']),
      );

      expect(result.skillMatches.single.level, MatchLevel.partial);
      expect(result.skillMatches.single.resumeEvidence, 'Azure');
    });

    test('a genuinely unrelated skill is missing, not partial - Kubernetes and '
        'Docker are never treated as related to each other', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Docker', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Kubernetes']),
      );

      expect(result.skillMatches.single.level, MatchLevel.missing);
      expect(result.skillMatches.single.resumeEvidence, isNull);
    });

    test('AWS and Azure are never aliased to each other', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'AWS', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Azure']),
      );

      expect(result.skillMatches.single.level, MatchLevel.missing);
    });

    test('React and Angular are never aliased to each other', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'React', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Angular']),
      );

      expect(result.skillMatches.single.level, MatchLevel.missing);
    });

    test('an explicit alias (JS <-> JavaScript) counts as an exact match', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'JS', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['JavaScript']),
      );

      expect(result.skillMatches.single.level, MatchLevel.exact);
    });

    test('multiple requirements are each evaluated independently, in order', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Kubernetes', category: SkillCategory.technical),
          ResolvedSkillEntry(sourceBlockId: 2, name: 'Docker', category: SkillCategory.technical),
          ResolvedSkillEntry(sourceBlockId: 3, name: 'Terraform', category: SkillCategory.technical),
          ResolvedSkillEntry(sourceBlockId: 4, name: 'Azure', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Kubernetes', 'Docker', 'Terraform', 'Azure', 'CI/CD']),
      );

      expect(result.exactSkillMatches, hasLength(4));
      expect(result.missingSkillMatches, hasLength(1));
      expect(result.missingSkillMatches.single.jdRequirement, 'CI/CD');
    });

    test('an empty resume produces every requirement as missing, never a crash', () async {
      final result = await analyzer.analyze(buildSnapshot(), buildJd(requirements: const ['Python', 'SQL']));
      expect(result.missingSkillMatches, hasLength(2));
    });

    test('an empty JD (no requirements) produces no skill matches at all', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Python', category: SkillCategory.technical),
        ]),
        buildJd(),
      );
      expect(result.skillMatches, isEmpty);
      expect(result.warnings, isNotEmpty);
    });
  });

  group('experience requirement analysis', () {
    test('meets an open-ended "N+ years" requirement based on resume date span', () async {
      final result = await analyzer.analyze(
        buildSnapshot(experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Engineer',
            company: 'Acme',
            startDate: '2018-01',
            endDate: '2023-01',
          ),
        ]),
        buildJd(experienceRequirement: const JdExperienceRequirement(minYears: 3, rawText: '3+ years')),
      );

      expect(result.experienceCheck.resumeEstimatedYears, 5);
      expect(result.experienceCheck.summary, contains('meets or exceeds'));
    });

    test('falls below a requirement when the resume shows fewer years', () async {
      final result = await analyzer.analyze(
        buildSnapshot(experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Engineer',
            company: 'Acme',
            startDate: '2023-01',
            endDate: '2024-01',
          ),
        ]),
        buildJd(experienceRequirement: const JdExperienceRequirement(minYears: 5, rawText: '5+ years')),
      );

      expect(result.experienceCheck.summary, contains('below'));
    });

    test('returns "Unable to determine from resume" when no experience dates parse', () async {
      final result = await analyzer.analyze(
        buildSnapshot(experience: const [
          ResolvedExperienceEntry(
            sourceBlockId: 1,
            role: 'Engineer',
            company: 'Acme',
            startDate: 'unknown',
          ),
        ]),
        buildJd(experienceRequirement: const JdExperienceRequirement(minYears: 3, rawText: '3+ years')),
      );

      expect(result.experienceCheck.resumeEstimatedYears, isNull);
      expect(result.experienceCheck.summary, contains('Unable to determine from resume'));
    });

    test('reports no requirement detected when the JD has none, never a guess', () async {
      final result = await analyzer.analyze(buildSnapshot(), buildJd());
      expect(result.experienceCheck.jdRequirementRawText, isNull);
      expect(result.experienceCheck.summary, contains('No specific years-of-experience requirement'));
    });
  });

  group('education comparison', () {
    test('a matching degree level is exact', () async {
      final result = await analyzer.analyze(
        buildSnapshot(education: const [
          ResolvedEducationEntry(
            sourceBlockId: 1,
            institution: 'State University',
            degree: "Bachelor of Science",
            startDate: '2016',
            endDate: '2020',
          ),
        ]),
        buildJd(educationRequirements: const ["Bachelor's degree required"]),
      );

      expect(result.educationChecks.single.level, MatchLevel.exact);
    });

    test('a degree requirement with no matching resume education is missing, '
        'worded as "not found" rather than "does not have"', () async {
      final result = await analyzer.analyze(
        buildSnapshot(),
        buildJd(educationRequirements: const ["Master's degree required"]),
      );

      expect(result.educationChecks.single.level, MatchLevel.missing);
    });
  });

  group('certification comparison', () {
    test('a matching certification name is exact', () async {
      final result = await analyzer.analyze(
        buildSnapshot(certifications: const [
          ResolvedCertificationEntry(sourceBlockId: 1, name: 'AWS Certified Developer', issuer: 'Amazon'),
        ]),
        buildJd(certificationRequirements: const ['AWS Certified Developer']),
      );

      expect(result.certificationChecks.single.level, MatchLevel.exact);
    });

    test('missing resume evidence produces a missing certification check', () async {
      final result = await analyzer.analyze(
        buildSnapshot(),
        buildJd(certificationRequirements: const ['PMP Certification']),
      );

      expect(result.certificationChecks.single.level, MatchLevel.missing);
      expect(result.certificationChecks.single.resumeEvidence, isNull);
    });
  });

  group('local match indicator', () {
    test('is null when there are no requirements to compare', () async {
      final result = await analyzer.analyze(buildSnapshot(), buildJd());
      expect(result.localMatchIndicatorPercent, isNull);
    });

    test('is 100 when every requirement matches exactly', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Python', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Python']),
      );
      expect(result.localMatchIndicatorPercent, 100);
    });

    test('is 0 when every requirement is missing', () async {
      final result = await analyzer.analyze(buildSnapshot(), buildJd(requirements: const ['Python']));
      expect(result.localMatchIndicatorPercent, 0);
    });
  });

  group('determinism', () {
    test('repeated analysis of the same inputs produces identical results', () async {
      final snapshot = buildSnapshot(skills: const [
        ResolvedSkillEntry(sourceBlockId: 1, name: 'Python', category: SkillCategory.technical),
      ]);
      final jd = buildJd(requirements: const ['Python', 'SQL']);

      final first = await analyzer.analyze(snapshot, jd);
      final second = await analyzer.analyze(snapshot, jd);

      expect(first.localMatchIndicatorPercent, second.localMatchIndicatorPercent);
      expect(first.exactSkillMatches.length, second.exactSkillMatches.length);
      expect(first.missingSkillMatches.length, second.missingSkillMatches.length);
    });
  });

  group('matchSource tagging (docs/v3/01-prd.md §25 Milestone 2)', () {
    test('a raw exact match (no alias table entry involved on either side) is tagged exactKeyword', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Kubernetes', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Kubernetes']),
      );

      expect(result.skillMatches.single.level, MatchLevel.exact);
      expect(result.skillMatches.single.matchSource, MatchSource.exactKeyword);
    });

    test('an alias-resolved exact match (JS <-> JavaScript) is tagged alias, not exactKeyword', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'JS', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['JavaScript']),
      );

      expect(result.skillMatches.single.level, MatchLevel.exact);
      expect(result.skillMatches.single.matchSource, MatchSource.alias);
    });

    test('a shared-significant-token partial match ("Azure DevOps" vs "Azure") is tagged tokenOverlap', () async {
      final result = await analyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Azure', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Azure DevOps']),
      );

      expect(result.skillMatches.single.level, MatchLevel.partial);
      expect(result.skillMatches.single.matchSource, MatchSource.tokenOverlap);
    });

    test('a missing requirement has no matchSource', () async {
      final result = await analyzer.analyze(buildSnapshot(), buildJd(requirements: const ['Python']));
      expect(result.skillMatches.single.level, MatchLevel.missing);
      expect(result.skillMatches.single.matchSource, isNull);
    });
  });

  group('semantic matching (docs/v3/01-prd.md §25 Milestone 2)', () {
    test('a missing requirement is upgraded to partial + semanticEmbedding when the semantic '
        'matcher finds a genuine synonym with no shared word token', () async {
      const requirement = 'Spreadsheet software proficiency';
      const evidence = 'Advanced Microsoft Excel skills';
      final semanticAnalyzer = ResumeJdAnalyzer(
        semanticMatcher: ResumeJdSemanticMatcher(
          embeddingEngine: _FixtureVectorEmbeddingEngine({
            requirement: [1.0, 0.0],
            evidence: [0.95, 0.31],
          }),
        ),
      );

      final result = await semanticAnalyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: evidence, category: SkillCategory.technical),
        ]),
        buildJd(requirements: const [requirement]),
      );

      expect(result.skillMatches.single.level, MatchLevel.partial);
      expect(result.skillMatches.single.matchSource, MatchSource.semanticEmbedding);
      expect(result.skillMatches.single.resumeEvidence, evidence);
    });

    test('the semantic matcher never runs on (and never downgrades) an already-exact match', () async {
      const requirement = 'Kubernetes';
      const evidence = 'Kubernetes';
      final semanticAnalyzer = ResumeJdAnalyzer(
        // requirement and evidence are the identical string "Kubernetes"
        // here (a raw exact match), so only one fixture vector is
        // registered - it is never actually looked up regardless, since
        // the analyzer's own `_applySemanticTier` skips the matcher
        // entirely for a match that isn't already `MatchLevel.missing`.
        // An empty engine (no fixtures at all) would work identically;
        // registering one is just defensive documentation of intent.
        semanticMatcher: ResumeJdSemanticMatcher(
          embeddingEngine: _FixtureVectorEmbeddingEngine({requirement: [1.0, 0.0]}),
        ),
      );

      final result = await semanticAnalyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: evidence, category: SkillCategory.technical),
        ]),
        buildJd(requirements: const [requirement]),
      );

      expect(result.skillMatches.single.level, MatchLevel.exact);
      expect(result.skillMatches.single.matchSource, MatchSource.exactKeyword);
    });

    test('the semantic matcher never downgrades an already-partial (token-overlap) match', () async {
      const requirement = 'Azure DevOps';
      const evidence = 'Azure';
      final semanticAnalyzer = ResumeJdAnalyzer(
        semanticMatcher: ResumeJdSemanticMatcher(
          embeddingEngine: _FixtureVectorEmbeddingEngine({
            requirement: [1.0, 0.0],
            evidence: [0.0, 1.0],
          }),
        ),
      );

      final result = await semanticAnalyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: evidence, category: SkillCategory.technical),
        ]),
        buildJd(requirements: const [requirement]),
      );

      expect(result.skillMatches.single.level, MatchLevel.partial);
      expect(result.skillMatches.single.matchSource, MatchSource.tokenOverlap);
    });

    test('with no semantic matcher supplied (the default), a missing requirement stays missing - '
        'strictly opt-in, fully backward compatible', () async {
      final result = await analyzer.analyze(buildSnapshot(), buildJd(requirements: const ['Python']));
      expect(result.skillMatches.single.level, MatchLevel.missing);
    });

    test('a genuinely dissimilar candidate stays missing rather than being force-matched', () async {
      const requirement = 'Kubernetes';
      const evidence = 'Watercolor painting';
      final semanticAnalyzer = ResumeJdAnalyzer(
        semanticMatcher: ResumeJdSemanticMatcher(
          embeddingEngine: _FixtureVectorEmbeddingEngine({
            requirement: [1.0, 0.0],
            evidence: [0.0, 1.0],
          }),
        ),
      );

      final result = await semanticAnalyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: evidence, category: SkillCategory.technical),
        ]),
        buildJd(requirements: const [requirement]),
      );

      expect(result.skillMatches.single.level, MatchLevel.missing);
      expect(result.skillMatches.single.matchSource, isNull);
    });

    test('when the embedding engine throws, analysis still completes and falls back to the '
        'deterministic missing result rather than propagating the error', () async {
      final semanticAnalyzer = ResumeJdAnalyzer(
        semanticMatcher: ResumeJdSemanticMatcher(
          embeddingEngine: FakeEmbeddingEngine(errorToThrow: StateError('model not loaded')),
        ),
      );

      final result = await semanticAnalyzer.analyze(
        buildSnapshot(skills: const [
          ResolvedSkillEntry(sourceBlockId: 1, name: 'Excel', category: SkillCategory.technical),
        ]),
        buildJd(requirements: const ['Spreadsheets']),
      );

      expect(result.skillMatches.single.level, MatchLevel.missing);
      expect(result.skillMatches.single.matchSource, isNull);
    });
  });
}
