import '../../../models/job_description.dart';
import '../../../services/ai/llm_engine.dart';
import '../../../services/ai/llm_request_queue.dart';
import '../../../services/career/jd_skill_recommendation_service.dart'
    show JdSkillRecommendationService, RecommendedSkill;
import '../../../services/resume/jd_tailored_summary_prompt_builder.dart';
import '../../../services/resume/project_idea_prompt_builder.dart';

/// One AI-suggested project idea for the AI-Tailored-Resume-from-JD
/// feature - explicitly NOT a claim that the user has built this. Never
/// persisted on its own; becomes a real `ProjectBlock` only once the user
/// explicitly confirms it via the review screen (see
/// `CreateJdTailoredResumeUseCase`), at which point the user has also
/// edited/confirmed real bullet text - the raw fields here are never
/// written to a resume verbatim.
class ProjectIdea {
  const ProjectIdea({
    required this.title,
    this.suggestedTechnologies = const [],
    this.suggestedFeatures = const [],
  });

  final String title;
  final List<String> suggestedTechnologies;
  final List<String> suggestedFeatures;
}

/// Everything [GenerateJdTailoredDraftUseCase] produces - an in-memory
/// proposal, never touching the database. Flows: generation -> review
/// screen's local widget state -> (only for whatever the user explicitly
/// accepts) `CreateJdTailoredResumeUseCase`. Mirrors
/// `BeginnerResumeInput.confirmedSkills`/`SuggestedSkill`'s "a suggestion
/// never becomes part of the resume on its own" rule, applied to
/// JD-recommended skills and project ideas alike.
class JdTailoredDraft {
  const JdTailoredDraft({
    required this.targetRoleLabel,
    required this.summaryText,
    required this.summaryWasGenerated,
    this.recommendedSkills = const [],
    this.jdKeywordsCovered = const [],
    this.jdKeywordsMissing = const [],
    this.suggestedProjectIdeas = const [],
  });

  final String targetRoleLabel;
  final String summaryText;

  /// False when the LLM was unavailable or failed and [summaryText] is the
  /// deterministic fallback sentence instead - display-only messaging
  /// ("AI resume suggestions are unavailable right now" per the offline
  /// requirement); never blocks resume creation either way.
  final bool summaryWasGenerated;

  /// None pre-selected - the review screen starts every recommendation
  /// unaccepted.
  final List<RecommendedSkill> recommendedSkills;
  final List<String> jdKeywordsCovered;
  final List<String> jdKeywordsMissing;

  /// May be shorter than requested (or empty) if generation failed or every
  /// candidate was rejected for completed-tense language - never a
  /// generation failure by itself.
  final List<ProjectIdea> suggestedProjectIdeas;
}

/// Matches first-person/declarative completed-tense phrasing a project
/// *idea* must never contain (e.g. "I built...", "Developed a..."). Not
/// case-sensitive. This is the deterministic second layer behind
/// [ProjectIdeaPromptBuilder]'s own wording rules - see that class's doc
/// comment for why both layers exist. Matched anywhere in the output
/// (not just as the very first word) since the model could still slip the
/// phrasing into the middle of a "Features:" line.
final RegExp _completedTenseLanguage = RegExp(
  r'\b(built|developed|created|completed|delivered|shipped|launched|implemented|deployed)\b',
  caseSensitive: false,
);

/// Generates the in-memory AI draft (professional summary + JD-recommended
/// skills + JD-relevant project ideas) for the AI-Tailored-Resume-from-JD
/// feature. Never persists anything - there is no `Resume` row yet at this
/// point in the flow (`CreateJdTailoredResumeUseCase`, run only after the
/// user reviews and confirms this draft, is what actually writes to the
/// database).
///
/// Every generative call follows the exact bounded-call discipline
/// `GenerateResumeSuggestionsUseCase`/`GenerateBulletRewriteUseCase`
/// already established elsewhere in this app: one small prompt, submitted
/// through [LlmRequestQueue] (ADR-008, single in-flight generation),
/// wrapped in try/catch with no retry - any failure (model unavailable,
/// generation error, malformed output) degrades gracefully rather than
/// throwing, so "AI resume suggestions are unavailable right now" never
/// blocks the user from continuing with the rest of the wizard (the
/// existing app-wide offline requirement).
class GenerateJdTailoredDraftUseCase {
  GenerateJdTailoredDraftUseCase({
    required JdSkillRecommendationService skillRecommendationService,
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
    JdTailoredResumeSummaryPromptBuilder summaryPromptBuilder = const JdTailoredResumeSummaryPromptBuilder(),
    ProjectIdeaPromptBuilder projectIdeaPromptBuilder = const ProjectIdeaPromptBuilder(),
  })  : _skillRecommendationService = skillRecommendationService,
        _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue,
        _summaryPromptBuilder = summaryPromptBuilder,
        _projectIdeaPromptBuilder = projectIdeaPromptBuilder;

  final JdSkillRecommendationService _skillRecommendationService;
  final LlmEngine _llmEngine;
  final LlmRequestQueue _llmRequestQueue;
  final JdTailoredResumeSummaryPromptBuilder _summaryPromptBuilder;
  final ProjectIdeaPromptBuilder _projectIdeaPromptBuilder;

  /// Never throws - every step degrades to a safe default on failure, so
  /// this always returns a usable (if partially empty) [JdTailoredDraft].
  Future<JdTailoredDraft> call({
    required String targetRoleLabel,
    required ParsedJobDescription jd,
    List<String> confirmedSkillNames = const [],
    String? educationLabel,
    List<String> experienceOneLiners = const [],
    List<String> existingProjectNames = const [],
  }) async {
    // Step 1 - deterministic, no LLM: which JD requirements the user's
    // already-confirmed skills cover vs. don't.
    final skillResult = await _skillRecommendationService.recommend(
      jd: jd,
      confirmedSkillNames: confirmedSkillNames,
    );

    // Step 2 - one bounded LLM call for the professional summary, with a
    // deterministic fallback (never invents, never blocks - mirrors
    // buildBeginnerResumeSummary's own "never fabricates" shape) if the
    // model is unavailable or fails.
    final summaryPrompt = _summaryPromptBuilder.build(
      targetRoleLabel: targetRoleLabel,
      confirmedSkillNames: confirmedSkillNames,
      educationLabel: educationLabel,
      experienceOneLiners: experienceOneLiners,
      existingProjectNames: existingProjectNames,
    );

    String summaryText;
    bool summaryWasGenerated;
    try {
      final raw = await _llmRequestQueue
          .enqueue(
            LlmQueueRequest(
              isForeground: true,
              run: () => _llmEngine.generateFromPrompt(summaryPrompt.systemPrompt, summaryPrompt.userPrompt),
            ),
          )
          .result;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        summaryText = _fallbackSummary(targetRoleLabel, confirmedSkillNames);
        summaryWasGenerated = false;
      } else {
        summaryText = trimmed;
        summaryWasGenerated = true;
      }
    } catch (_) {
      summaryText = _fallbackSummary(targetRoleLabel, confirmedSkillNames);
      summaryWasGenerated = false;
    }

    // Step 3 - up to 3 separate bounded LLM calls for project ideas, each
    // covering requirements not yet covered by an earlier idea in this same
    // call. Any individual failure/rejection just yields fewer ideas.
    final ideas = <ProjectIdea>[];
    final requirementPool = jd.requirements.where((r) => r.trim().isNotEmpty).toList();
    final maxIdeas = requirementPool.isEmpty ? 0 : (requirementPool.length < 3 ? requirementPool.length : 3);
    for (var i = 0; i < maxIdeas; i++) {
      final topRequirements = requirementPool.take(i + 1).toList();
      final idea = await _generateOneProjectIdea(
        jdTitle: targetRoleLabel,
        topRequirements: topRequirements,
        confirmedSkillNames: confirmedSkillNames,
      );
      if (idea != null) ideas.add(idea);
    }

    return JdTailoredDraft(
      targetRoleLabel: targetRoleLabel,
      summaryText: summaryText,
      summaryWasGenerated: summaryWasGenerated,
      recommendedSkills: skillResult.recommendedSkills,
      jdKeywordsCovered: skillResult.jdKeywordsCovered,
      jdKeywordsMissing: skillResult.jdKeywordsMissing,
      suggestedProjectIdeas: ideas,
    );
  }

  Future<ProjectIdea?> _generateOneProjectIdea({
    required String jdTitle,
    required List<String> topRequirements,
    required List<String> confirmedSkillNames,
  }) async {
    final prompt = _projectIdeaPromptBuilder.build(
      jdTitle: jdTitle,
      topRequirements: topRequirements,
      confirmedSkillNames: confirmedSkillNames,
    );

    final String raw;
    try {
      raw = await _llmRequestQueue
          .enqueue(
            LlmQueueRequest(
              isForeground: true,
              run: () => _llmEngine.generateFromPrompt(prompt.systemPrompt, prompt.userPrompt),
            ),
          )
          .result;
    } catch (_) {
      return null;
    }

    if (_completedTenseLanguage.hasMatch(raw)) return null;

    String? title;
    List<String> technologies = const [];
    List<String> features = const [];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.toLowerCase().startsWith('title:')) {
        title = trimmed.substring(6).trim();
      } else if (trimmed.toLowerCase().startsWith('technologies:')) {
        technologies = _splitCommaList(trimmed.substring(13));
      } else if (trimmed.toLowerCase().startsWith('features:')) {
        features = _splitCommaList(trimmed.substring(9));
      }
    }

    if (title == null || title.isEmpty) return null;
    return ProjectIdea(title: title, suggestedTechnologies: technologies, suggestedFeatures: features);
  }

  List<String> _splitCommaList(String text) {
    return text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(growable: false);
  }

  String _fallbackSummary(String targetRoleLabel, List<String> confirmedSkillNames) {
    final skills = confirmedSkillNames.where((s) => s.trim().isNotEmpty).toList();
    if (skills.isEmpty) {
      return 'Motivated candidate seeking to build a career as a $targetRoleLabel.';
    }
    return 'Candidate for $targetRoleLabel roles, skilled in ${_joinWithAnd(skills.take(6).toList())}.';
  }

  String _joinWithAnd(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }
}
