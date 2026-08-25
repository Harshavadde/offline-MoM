// Tests GenerateJdTailoredDraftUseCase
// (lib/features/career/resume/generate_jd_tailored_draft_use_case.dart) -
// AI-Tailored-Resume-from-JD feature. Real JdSkillRecommendationService
// (deterministic, no fake needed) + a FakeLlmEngine for the two bounded
// generative calls (summary, project ideas) - mirrors
// generate_resume_suggestions_use_case_test.dart's established
// real-service-plus-fake-model style.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/generate_jd_tailored_draft_use_case.dart';
import 'package:offline_mom/models/job_description.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/career/jd_skill_recommendation_service.dart';

import '../../../test_helpers/fake_ai_engines.dart';

void main() {
  const skillRecommendationService = JdSkillRecommendationService();

  GenerateJdTailoredDraftUseCase buildUseCase({
    String? promptResponse,
    String Function(String systemPrompt, String userPrompt)? responseFromPrompt,
    Object? errorToThrow,
  }) {
    return GenerateJdTailoredDraftUseCase(
      skillRecommendationService: skillRecommendationService,
      llmEngine: FakeLlmEngine(
        promptResponse: promptResponse,
        responseFromPrompt: responseFromPrompt,
        errorToThrow: errorToThrow,
      ),
      llmRequestQueue: DefaultLlmRequestQueue(),
    );
  }

  ParsedJobDescription buildJd({List<String> requirements = const ['Python', 'Django', 'PostgreSQL']}) {
    return ParsedJobDescription(rawText: 'raw', title: 'Python Developer', requirements: requirements);
  }

  group('successful generation', () {
    test('produces a fully-populated draft with a real summary and confirmed recommendations', () async {
      final useCase = buildUseCase(
        responseFromPrompt: (systemPrompt, userPrompt) {
          if (systemPrompt.contains('professional summary')) {
            return 'Motivated Python Developer skilled in Python.';
          }
          return 'Title: Job Application Tracker\n'
              'Technologies: Python, Django\n'
              'Features: Track applications, Send reminders';
        },
      );

      final draft = await useCase.call(
        targetRoleLabel: 'Python Developer',
        jd: buildJd(),
        confirmedSkillNames: ['Python'],
      );

      expect(draft.targetRoleLabel, 'Python Developer');
      expect(draft.summaryText, 'Motivated Python Developer skilled in Python.');
      expect(draft.summaryWasGenerated, isTrue);
      final recommendedNames = draft.recommendedSkills.map((s) => s.name).toList();
      expect(recommendedNames, containsAll(['Django', 'PostgreSQL']));
      expect(recommendedNames, isNot(contains('Python')));
      expect(draft.suggestedProjectIdeas, isNotEmpty);
      expect(draft.suggestedProjectIdeas.first.title, 'Job Application Tracker');
    });
  });

  group('offline / AI-unavailable graceful continuation', () {
    test('a summary-generation failure falls back to a deterministic sentence, never throws', () async {
      final useCase = buildUseCase(errorToThrow: Exception('model unavailable'));

      final draft = await useCase.call(
        targetRoleLabel: 'Python Developer',
        jd: buildJd(),
        confirmedSkillNames: ['Python'],
      );

      expect(draft.summaryWasGenerated, isFalse);
      expect(draft.summaryText, isNotEmpty);
      expect(draft.summaryText, contains('Python Developer'));
      // The failure also prevents any project-idea calls from succeeding,
      // but the draft itself is still returned, never an exception.
      expect(draft.suggestedProjectIdeas, isEmpty);
    });

    test('an empty raw summary response also falls back gracefully', () async {
      final useCase = buildUseCase(promptResponse: '   ');

      final draft = await useCase.call(
        targetRoleLabel: 'Python Developer',
        jd: buildJd(requirements: const []),
        confirmedSkillNames: const [],
      );

      expect(draft.summaryWasGenerated, isFalse);
      expect(draft.summaryText, isNotEmpty);
    });
  });

  group('project ideas never read as completed work', () {
    test('an idea containing completed-tense language is rejected and never appears', () async {
      final useCase = buildUseCase(
        responseFromPrompt: (systemPrompt, userPrompt) {
          if (systemPrompt.contains('professional summary')) return 'A summary.';
          return 'Title: Job Tracker\n'
              'Technologies: Python\n'
              'Features: I built this to track my job applications';
        },
      );

      final draft = await useCase.call(
        targetRoleLabel: 'Python Developer',
        jd: buildJd(requirements: const ['Python']),
        confirmedSkillNames: ['Python'],
      );

      expect(draft.suggestedProjectIdeas, isEmpty);
    });

    test('"Developed a..." phrasing is also rejected', () async {
      final useCase = buildUseCase(
        responseFromPrompt: (systemPrompt, userPrompt) {
          if (systemPrompt.contains('professional summary')) return 'A summary.';
          return 'Title: Developed a tracker app\n'
              'Technologies: Python\n'
              'Features: Tracking';
        },
      );

      final draft = await useCase.call(
        targetRoleLabel: 'Python Developer',
        jd: buildJd(requirements: const ['Python']),
        confirmedSkillNames: ['Python'],
      );

      expect(draft.suggestedProjectIdeas, isEmpty);
    });

    test('a malformed (unparsable) idea response is dropped, not thrown', () async {
      final useCase = buildUseCase(
        responseFromPrompt: (systemPrompt, userPrompt) {
          if (systemPrompt.contains('professional summary')) return 'A summary.';
          return 'not the expected format at all';
        },
      );

      final draft = await useCase.call(
        targetRoleLabel: 'Python Developer',
        jd: buildJd(requirements: const ['Python']),
        confirmedSkillNames: ['Python'],
      );

      expect(draft.suggestedProjectIdeas, isEmpty);
    });
  });

  test('empty JD requirements -> zero project-idea calls attempted', () async {
    final promptCalls = <String>[];
    final useCase = buildUseCase(
      responseFromPrompt: (systemPrompt, userPrompt) {
        promptCalls.add(systemPrompt);
        return 'A summary.';
      },
    );

    final draft = await useCase.call(
      targetRoleLabel: 'General Fresher',
      jd: buildJd(requirements: const []),
      confirmedSkillNames: const [],
    );

    expect(draft.suggestedProjectIdeas, isEmpty);
    // Only the one summary call was made - no project-idea prompts at all.
    expect(promptCalls, hasLength(1));
  });

  test('never suggests more than 3 project ideas even with many requirements', () async {
    final useCase = buildUseCase(
      responseFromPrompt: (systemPrompt, userPrompt) {
        if (systemPrompt.contains('professional summary')) return 'A summary.';
        return 'Title: Idea\nTechnologies: X\nFeatures: Y';
      },
    );

    final draft = await useCase.call(
      targetRoleLabel: 'Full Stack Developer',
      jd: buildJd(requirements: const ['A', 'B', 'C', 'D', 'E']),
      confirmedSkillNames: const [],
    );

    expect(draft.suggestedProjectIdeas.length, lessThanOrEqualTo(3));
  });
}
