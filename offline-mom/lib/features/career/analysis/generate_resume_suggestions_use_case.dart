import '../../../models/ai_model_spec.dart' show RecommendedDeviceTier;
import '../../../models/job_description.dart';
import '../../../models/resume_block_type.dart';
import '../../../models/resume_jd_analysis_result.dart';
import '../../../models/suggested_edit.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../repositories/suggested_edit_repository.dart';
import '../../../services/ai/llm_engine.dart';
import '../../../services/ai/llm_request_queue.dart';
import '../../../services/ai/model_lifecycle_manager.dart' show ModelKind, ModelLifecycleManager;
import '../../../services/career/resume_jd_analyzer.dart';
import '../../../services/device/device_capability_service.dart';
import '../../../services/resume/resume_compiler_service.dart';
import '../../../services/resume/resume_suggestion_prompt_builder.dart';

/// Thrown when the selected resume can no longer be found (deleted between
/// selection and generation) - the generation-pipeline counterpart to
/// [AnalyzeResumeAgainstJdUseCase]'s identically-shaped exception (kept as
/// its own type rather than imported, since "found during analysis" and
/// "found during generation" are different callers' failure modes even
/// though the underlying condition is the same).
class ResumeNotFoundForSuggestionGenerationException implements Exception {
  ResumeNotFoundForSuggestionGenerationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when JD-tailoring suggestion generation is attempted against
/// "My Profile" (Product Validation phase,
/// docs/v3/implementation/03-decisions.md) - the master profile must
/// never receive JD-specific tailoring, accepted or not: "MASTER PROFILE
/// -> CREATE RESUME -> optionally tailor for JD". Create a resume from
/// the profile first, then run JD analysis/tailoring against that
/// derived, job-specific resume instead.
class CannotTailorProfileException implements Exception {
  CannotTailorProfileException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Generates bounded, per-entry AI rewrite suggestions for resume content
/// that's relevant-but-improvable against a JD (docs/v3/01-prd.md §25
/// Milestone 3, FR3-07, §11.4, AC3-04).
///
/// "Relevant-but-improvable" is defined entirely in terms of Milestone 2's
/// own output, never a second JD-matching implementation: a candidate
/// entry is one whose own bullet/detail text is exactly the
/// `resumeEvidence` of a [MatchLevel.partial] skill match - i.e.
/// [ResumeJdAnalyzer] already found *some* real connection to a
/// requirement, just not an exact one, which is precisely the "worth
/// rewriting to more clearly address" case. An entry with no partial match
/// never gets a generative call: an exact match needs no rewrite, and a
/// requirement with no resume evidence at all has nothing to rewrite
/// *from* (generating one anyway would mean inventing content, exactly
/// what AC3-01 forbids) - the deterministic "missing" findings are
/// surfaced to the user as-is (Milestone 2's analysis screen), never
/// silently turned into a fabricated bullet.
///
/// Every generative call is bounded to exactly one entry's own text plus
/// its one associated JD requirement (AC3-04) - see [_generateForField].
/// Nothing here ever writes to a resume block; every usable result becomes
/// a `pending` [SuggestedEdit] row via [SuggestedEditRepository], never
/// merged into live content (AC3-02) - see
/// generate_resume_suggestions_use_case_test.dart's dedicated
/// architectural test for this property. [SuggestionFabricationGuard] is
/// deliberately not consulted here: per AC3-03/D-08 it only ever *flags*,
/// never rejects, so running it at generation time and discarding the
/// result would be dead code - the review screen computes the flag lazily,
/// from the same stored `originalValue`/`suggestedValue`, when a
/// suggestion is actually displayed.
///
/// **RAM sequencing on low-tier devices (Milestone 5, docs/v3/01-prd.md
/// §13 D-11, RV3-04):** [call] itself is the one place in the whole
/// tailoring pipeline where the embedding-backed analysis pass
/// ([_analyzer.analyze], which may load [ModelKind.embedding] for its
/// semantic tier) and the LLM-backed rewrite pass ([_generateForField],
/// which loads [ModelKind.llm]) run back-to-back with no user-interaction
/// gap between them - see [_releaseEmbeddingModelIfLowTier]'s own doc
/// comment for why that makes this the correct, and only necessary,
/// insertion point for the sequencing D-11 describes.
class GenerateResumeSuggestionsUseCase {
  GenerateResumeSuggestionsUseCase({
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required ResumeCompilerService compilerService,
    required ResumeJdAnalyzer analyzer,
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
    required SuggestedEditRepository suggestedEditRepository,
    required DeviceCapabilityService deviceCapabilityService,
    required ModelLifecycleManager modelLifecycleManager,
    ResumeSuggestionPromptBuilder promptBuilder = const ResumeSuggestionPromptBuilder(),
  })  : _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _compilerService = compilerService,
        _analyzer = analyzer,
        _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue,
        _suggestedEditRepository = suggestedEditRepository,
        _deviceCapabilityService = deviceCapabilityService,
        _modelLifecycleManager = modelLifecycleManager,
        _promptBuilder = promptBuilder;

  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final ResumeCompilerService _compilerService;
  final ResumeJdAnalyzer _analyzer;
  final LlmEngine _llmEngine;
  final LlmRequestQueue _llmRequestQueue;
  final SuggestedEditRepository _suggestedEditRepository;
  final DeviceCapabilityService _deviceCapabilityService;
  final ModelLifecycleManager _modelLifecycleManager;
  final ResumeSuggestionPromptBuilder _promptBuilder;

  Future<List<SuggestedEdit>> call(int resumeId, ParsedJobDescription jd) async {
    final resume = await _resumeRepository.getById(resumeId);
    if (resume == null) {
      throw ResumeNotFoundForSuggestionGenerationException(
        'This resume could not be found. It may have been deleted.',
      );
    }
    if (resume.isProfile) {
      throw CannotTailorProfileException(
        'My Profile cannot be tailored for a job description - create a resume '
        'from it first, then tailor that resume.',
      );
    }

    final blockRefs = await _resumeBlockRepository.getForResume(resumeId);
    final snapshot = await _compilerService.compile(resume, blockRefs);
    final analysisResult = await _analyzer.analyze(snapshot, jd);

    final requirementByEvidence = <String, String>{};
    for (final match in analysisResult.skillMatches) {
      if (match.level == MatchLevel.partial && match.resumeEvidence != null) {
        requirementByEvidence.putIfAbsent(match.resumeEvidence!, () => match.jdRequirement);
      }
    }
    if (requirementByEvidence.isEmpty) return const [];

    // The embedding-backed analysis pass above has already run to
    // completion; from here on only the LLM is used. Release the
    // embedding model first on a low-tier device, before starting the
    // LLM-backed loop below - see D-11/RV3-04.
    await _releaseEmbeddingModelIfLowTier();

    final created = <SuggestedEdit>[];

    for (final entry in snapshot.experience) {
      // Part H (JD tailoring re-verification): deliberately `entry.bullets`
      // only, never `entry.subProjects`' bullets. A partial match whose
      // evidence lives inside a sub-project (now possible - see
      // ResumeJdAnalyzer's own Part H fix) will simply not be found here,
      // so no suggestion is generated for it. That's intentional: unlike
      // top-level bullets, a sub-project's bullets have no write-back path
      // through SuggestedEdit/ResumeBlockRepository.setOverride (see that
      // repository's own comment on the boundary), so a suggestion sourced
      // from one would have no safe way to actually apply on accept.
      final requirement = _firstMatchingRequirement(entry.bullets, requirementByEvidence);
      if (requirement == null) continue;
      final edit = await _generateForField(
        resumeId: resumeId,
        blockType: ResumeBlockType.experience,
        blockId: entry.sourceBlockId,
        fieldName: 'bullets',
        entryContextLabel: '${entry.role} at ${entry.company}',
        originalLines: entry.bullets,
        jdRequirement: requirement,
      );
      if (edit != null) created.add(edit);
    }

    for (final entry in snapshot.education) {
      final requirement = _firstMatchingRequirement(entry.details, requirementByEvidence);
      if (requirement == null) continue;
      final fieldOfStudy = entry.fieldOfStudy;
      final label = (fieldOfStudy == null || fieldOfStudy.isEmpty)
          ? '${entry.degree}, ${entry.institution}'
          : '${entry.degree} in $fieldOfStudy, ${entry.institution}';
      final edit = await _generateForField(
        resumeId: resumeId,
        blockType: ResumeBlockType.education,
        blockId: entry.sourceBlockId,
        fieldName: 'details',
        entryContextLabel: label,
        originalLines: entry.details,
        jdRequirement: requirement,
      );
      if (edit != null) created.add(edit);
    }

    for (final entry in snapshot.projects) {
      final requirement = _firstMatchingRequirement(entry.bullets, requirementByEvidence);
      if (requirement == null) continue;
      final edit = await _generateForField(
        resumeId: resumeId,
        blockType: ResumeBlockType.project,
        blockId: entry.sourceBlockId,
        fieldName: 'bullets',
        entryContextLabel: entry.name,
        originalLines: entry.bullets,
        jdRequirement: requirement,
      );
      if (edit != null) created.add(edit);
    }

    return created;
  }

  /// docs/v3/01-prd.md §13 (D-11, RV3-04): on a low-RAM-tier device
  /// (everything except [RecommendedDeviceTier.highRamDevice]), never hold
  /// the embedding and LLM models resident simultaneously during
  /// tailoring - release the embedding model, if it's currently idle,
  /// right before the LLM-backed rewrite pass begins. Reuses the existing
  /// idle-unload/reference-counting machinery
  /// ([ModelLifecycleManager.unmanagedUnload]) rather than inventing new
  /// concurrency/lifecycle plumbing - this is a request to unload *if
  /// safe*, never a forced interrupt: if the embedding model happens to
  /// still be in active use by another in-flight caller,
  /// [ModelLifecycleManager.unmanagedUnload] itself is a safe no-op (see
  /// its own doc comment). On a high-RAM device this entire pipeline is
  /// skipped - the existing [ModelLifecycleManager] idle-timeout behavior
  /// alone is already sufficient there (docs/v3/01-prd.md §13's own
  /// "on higher-tier devices this sequencing is not enforced" wording). A
  /// RAM-read failure (`totalRamMb()` returning `null`) falls back to the
  /// lowest tier via [recommendedTierForRamMb] itself, so this always
  /// degrades toward the *safer* (more aggressive unload) behavior, never
  /// silently skips it.
  Future<void> _releaseEmbeddingModelIfLowTier() async {
    final ramMb = await _deviceCapabilityService.totalRamMb();
    if (recommendedTierForRamMb(ramMb) == RecommendedDeviceTier.highRamDevice) return;
    await _modelLifecycleManager.unmanagedUnload(ModelKind.embedding);
  }

  /// The JD requirement for the *first* (in existing order) of [lines]
  /// that has partial-match evidence - AC3-04 bounds each generative call
  /// to one requirement, so an entry whose different bullets happen to
  /// match different requirements still only produces one suggestion in
  /// this milestone, deterministically the earliest one, rather than an
  /// unbounded per-bullet fan-out.
  String? _firstMatchingRequirement(List<String> lines, Map<String, String> requirementByEvidence) {
    for (final line in lines) {
      final requirement = requirementByEvidence[line];
      if (requirement != null) return requirement;
    }
    return null;
  }

  /// Runs exactly one bounded generative call for one entry's one field
  /// (AC3-04) and, if the result is usable, persists it as a `pending`
  /// [SuggestedEdit] - never writes to any resume block. Returns null (no
  /// suggestion, never a thrown error) when: the field has no content to
  /// rewrite; the model is unavailable, unloaded, or fails (AC3-05); the
  /// output is empty after parsing (malformed/empty model output rejected
  /// safely); or the model returned the original text unchanged (the
  /// prompt's own rule 4 - nothing to suggest).
  Future<SuggestedEdit?> _generateForField({
    required int resumeId,
    required ResumeBlockType blockType,
    required int blockId,
    required String fieldName,
    required String entryContextLabel,
    required List<String> originalLines,
    required String jdRequirement,
  }) async {
    if (originalLines.isEmpty) return null;
    final originalText = originalLines.join('\n');

    final prompt = _promptBuilder.build(
      entryContextLabel: entryContextLabel,
      originalText: originalText,
      jdRequirement: jdRequirement,
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

    final suggestedLines =
        raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(growable: false);
    if (suggestedLines.isEmpty) return null;

    final suggestedText = suggestedLines.join('\n');
    if (suggestedText == originalText) return null;

    final id = await _suggestedEditRepository.insert(
      SuggestedEdit(
        id: null,
        resumeId: resumeId,
        targetBlockType: blockType,
        targetBlockId: blockId,
        fieldName: fieldName,
        originalValue: originalText,
        suggestedValue: suggestedText,
        sourceRequirement: jdRequirement,
        createdAt: DateTime.now(),
      ),
    );

    return SuggestedEdit(
      id: id,
      resumeId: resumeId,
      targetBlockType: blockType,
      targetBlockId: blockId,
      fieldName: fieldName,
      originalValue: originalText,
      suggestedValue: suggestedText,
      sourceRequirement: jdRequirement,
      createdAt: DateTime.now(),
    );
  }
}
