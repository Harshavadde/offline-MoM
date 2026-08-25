// Tests JdSkillRecommendationService
// (lib/services/career/jd_skill_recommendation_service.dart) -
// AI-Tailored-Resume-from-JD feature. Deterministic, no LLM/fake needed;
// reuses the real ResumeJdAnalyzer exactly like the production service does.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/job_description.dart';
import 'package:offline_mom/services/career/jd_skill_recommendation_service.dart';
import 'package:offline_mom/services/career/resume_jd_analyzer.dart';

void main() {
  const service = JdSkillRecommendationService(analyzer: ResumeJdAnalyzer());

  test(
    'the spec scenario: confirmed Python only, JD wants Python+Django+PostgreSQL -> '
    'recommends exactly Django and PostgreSQL, never Python',
    () async {
      const jd = ParsedJobDescription(
        rawText: 'raw',
        requirements: ['Python', 'Django', 'PostgreSQL'],
      );

      final result = await service.recommend(jd: jd, confirmedSkillNames: ['Python']);

      final recommendedNames = result.recommendedSkills.map((s) => s.name).toList();
      expect(recommendedNames, containsAll(['Django', 'PostgreSQL']));
      expect(recommendedNames, isNot(contains('Python')));
      expect(result.jdKeywordsCovered, ['Python']);
      expect(result.jdKeywordsMissing, containsAll(['Django', 'PostgreSQL']));
    },
  );

  test('a JD requirement matched via the alias table is treated as covered, not recommended', () async {
    const jd = ParsedJobDescription(rawText: 'raw', requirements: ['JavaScript']);

    final result = await service.recommend(jd: jd, confirmedSkillNames: ['JS']);

    expect(result.recommendedSkills, isEmpty);
    expect(result.jdKeywordsCovered, ['JavaScript']);
  });

  test('a partial (token-overlap) match still counts as "not yet confirmed"', () async {
    // "Azure" (confirmed) shares only the "azure" token with "Azure DevOps"
    // (JD requirement) - not an exact match, so the more specific JD
    // requirement is still surfaced for the user to explicitly confirm.
    const jd = ParsedJobDescription(rawText: 'raw', requirements: ['Azure DevOps']);

    final result = await service.recommend(jd: jd, confirmedSkillNames: ['Azure']);

    expect(result.recommendedSkills, hasLength(1));
    expect(result.recommendedSkills.single.name, 'Azure DevOps');
  });

  test('no JD requirements at all produces no recommendations and no keywords', () async {
    const jd = ParsedJobDescription(rawText: 'raw');

    final result = await service.recommend(jd: jd, confirmedSkillNames: ['Python']);

    expect(result.recommendedSkills, isEmpty);
    expect(result.jdKeywordsCovered, isEmpty);
    expect(result.jdKeywordsMissing, isEmpty);
  });

  test('no confirmed skills at all -> every JD requirement is recommended', () async {
    const jd = ParsedJobDescription(rawText: 'raw', requirements: ['Excel', 'Data Entry']);

    final result = await service.recommend(jd: jd, confirmedSkillNames: const []);

    expect(result.recommendedSkills.map((s) => s.name), containsAll(['Excel', 'Data Entry']));
    expect(result.jdKeywordsCovered, isEmpty);
  });

  test('a recommended skill always defaults to SkillCategory.technical - never guessed otherwise', () async {
    const jd = ParsedJobDescription(rawText: 'raw', requirements: ['Communication']);

    final result = await service.recommend(jd: jd, confirmedSkillNames: const []);

    expect(result.recommendedSkills.single.suggestedCategory.name, 'technical');
  });
}
