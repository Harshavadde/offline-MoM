import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../models/job_description.dart';
import '../../../../../models/resume_jd_analysis_result.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../../../../shared/widgets/section_heading.dart';
import '../../../../../shared/widgets/skeleton_loader.dart';
import '../../../resume/presentation/providers/resume_providers.dart';
import '../../../resume/presentation/providers/resume_suggestion_providers.dart';
import '../providers/resume_jd_analysis_providers.dart';

/// Select an existing resume and run a local, explainable Resume <-> JD
/// analysis against the confirmed [jd]. Reuses `resumeListProvider`
/// (lib/features/career/resume/presentation/providers/resume_providers.dart)
/// for resume selection - no resume-loading logic is duplicated here.
///
/// [initialResumeId], when set (R-7 §3's "Create resume from a Job
/// Description" flow), skips resume selection entirely and starts the
/// analysis immediately against that resume - the caller already knows
/// which resume this is (it just created it), so making the user re-pick
/// it from a list of one would be pure friction.
class ResumeJdAnalysisScreen extends ConsumerStatefulWidget {
  const ResumeJdAnalysisScreen({super.key, required this.jd, this.initialResumeId});

  final ParsedJobDescription jd;
  final int? initialResumeId;

  @override
  ConsumerState<ResumeJdAnalysisScreen> createState() => _ResumeJdAnalysisScreenState();
}

class _ResumeJdAnalysisScreenState extends ConsumerState<ResumeJdAnalysisScreen> {
  @override
  void initState() {
    super.initState();
    final resumeId = widget.initialResumeId;
    if (resumeId == null) return;
    // Deferred a frame, same "act once mounted, not while building"
    // discipline used elsewhere in this app (e.g. `ChatScreen.initState`) -
    // triggering a provider mutation synchronously during the very first
    // build isn't safe in Riverpod.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(resumeJdAnalysisControllerProvider(widget.jd).notifier).analyze(resumeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final jd = widget.jd;
    final state = ref.watch(resumeJdAnalysisControllerProvider(jd));

    return Scaffold(
      appBar: AppBar(title: Text(jd.title ?? 'Resume vs. Job Description')),
      body: switch (state) {
        // Still showing the picker's default initial state, but a caller
        // already chose a resume for us (`initialResumeId`) - the
        // deferred `analyze()` call just hasn't started yet this frame.
        // Shows the same loading body it's about to become, rather than
        // flashing the resume picker for one frame.
        ResumeJdAnalysisSelectingResume() when widget.initialResumeId != null =>
          const _RunningBody(),
        ResumeJdAnalysisSelectingResume() => _SelectResumeBody(jd: jd),
        ResumeJdAnalysisRunning() => const _RunningBody(),
        ResumeJdAnalysisSucceeded(:final result, :final resumeId) =>
          _ResultBody(jd: jd, result: result, resumeId: resumeId),
        ResumeJdAnalysisFailed(:final message) => _FailedBody(jd: jd, message: message),
      },
    );
  }
}

class _RunningBody extends StatelessWidget {
  const _RunningBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Analyzing locally on this device…'),
        ],
      ),
    );
  }
}

class _FailedBody extends ConsumerWidget {
  const _FailedBody({required this.jd, required this.message});

  final ParsedJobDescription jd;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: "Couldn't complete the analysis",
      message: message,
      actionLabel: 'Try again',
      onAction: () => ref.read(resumeJdAnalysisControllerProvider(jd).notifier).reset(),
    );
  }
}

/// Names both inputs side by side, unmistakably - R-7 §4. Deliberately not
/// folded into the AppBar title (which stays the JD's title alone, same as
/// every other state on this screen) since a resume can be renamed/deleted
/// after this analysis ran; this reads the resume's *current* title live
/// via [resumeByIdProvider] rather than freezing it at analysis time.
class _ResumeAndJdHeader extends ConsumerWidget {
  const _ResumeAndJdHeader({required this.jd, required this.resumeId});

  final ParsedJobDescription jd;
  final int resumeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final resume = ref.watch(resumeByIdProvider(resumeId)).valueOrNull;
    final jdLabel =
        [jd.title, jd.company].where((s) => s != null && s.isNotEmpty).join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InputRow(
              icon: Icons.description_outlined,
              label: 'Resume',
              value: resume?.title ?? '…',
            ),
            const SizedBox(height: 8),
            _InputRow(
              icon: Icons.work_outline_rounded,
              label: 'Job description',
              value: jdLabel.isEmpty ? 'Job description' : jdLabel,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
              ),
              Text(value, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectResumeBody extends ConsumerWidget {
  const _SelectResumeBody({required this.jd});

  final ParsedJobDescription jd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumesAsync = ref.watch(resumeListProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jd.title ?? 'Job description', style: Theme.of(context).textTheme.titleMedium),
                  if (jd.company != null) Text(jd.company!),
                  const SizedBox(height: 4),
                  Text(
                    '${jd.requirements.length} requirement(s) detected',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeading('Select a resume to analyze'),
          const SizedBox(height: 8),
          resumesAsync.when(
            loading: () => const SkeletonCardList(),
            error: (err, _) => ErrorState(title: "Couldn't load your resumes", error: err),
            data: (allResumes) {
              // "My Profile" is never a JD-tailoring target - see
              // CannotTailorProfileException's own doc comment. Filtered
              // out here too so the picker itself guides the user toward
              // "create a resume from your profile, then tailor that"
              // rather than only rejecting the choice after the fact.
              final resumes = allResumes.where((r) => !r.isProfile).toList();
              if (resumes.isEmpty) {
                return const EmptyState(
                  icon: Icons.description_outlined,
                  title: 'No resumes yet',
                  message: 'Create or import a resume first, then come back '
                      'here to analyze it against this job description.',
                );
              }
              return Column(
                children: [
                  for (final resume in resumes)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
                        title: Text(resume.title),
                        subtitle: Text(resume.fullName.isEmpty ? 'No name set yet' : resume.fullName),
                        onTap: () => ref
                            .read(resumeJdAnalysisControllerProvider(jd).notifier)
                            .analyze(resume.id!),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ResultBody extends ConsumerWidget {
  const _ResultBody({required this.jd, required this.result, required this.resumeId});

  final ParsedJobDescription jd;
  final ResumeJdAnalysisResult result;

  /// The resume this [result] was computed for - every "Go to editor"
  /// action below navigates back into this exact resume
  /// (docs/v3/01-prd.md §25 Milestone 2, hard requirement 6).
  final int resumeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final indicator = result.localMatchIndicatorPercent;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // R-7 §4: "the user should always understand THIS is the resume
          // I'm tailoring, and THIS is the job description I'm tailoring it
          // for" - both named together, in one place, rather than the
          // resume only ever being implied by which list item was tapped.
          _ResumeAndJdHeader(jd: jd, resumeId: resumeId),
          const SizedBox(height: 20),
          if (indicator != null) ...[
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$indicator%', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Local match indicator - a transparent, on-device '
                      'estimate based on the requirements below. This is '
                      'not an official ATS score and does not represent '
                      'any company\'s real hiring system.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          _MatchSection(
            title: 'Strong matches',
            icon: Icons.check_circle_outline_rounded,
            color: Colors.green,
            matches: result.exactSkillMatches,
            resumeId: resumeId,
          ),
          _MatchSection(
            title: 'Partial / related matches',
            icon: Icons.adjust_rounded,
            color: Colors.amber,
            matches: result.partialSkillMatches,
            resumeId: resumeId,
          ),
          _MatchSection(
            title: 'Missing from resume',
            icon: Icons.cancel_outlined,
            color: scheme.error,
            matches: result.missingSkillMatches,
            resumeId: resumeId,
          ),
          const SectionHeading('Experience'),
          const SizedBox(height: 8),
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.experienceCheck.summary),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _GoToEditorButton(resumeId: resumeId),
                  ),
                ],
              ),
            ),
          ),
          if (result.educationChecks.isNotEmpty) ...[
            const SectionHeading('Education'),
            const SizedBox(height: 8),
            _RequirementChecksCard(checks: result.educationChecks, resumeId: resumeId),
          ],
          if (result.certificationChecks.isNotEmpty) ...[
            const SectionHeading('Certifications'),
            const SizedBox(height: 8),
            _RequirementChecksCard(checks: result.certificationChecks, resumeId: resumeId),
          ],
          if (result.warnings.isNotEmpty) ...[
            const SectionHeading('Warnings'),
            const SizedBox(height: 8),
            Card(
              color: scheme.tertiaryContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final warning in result.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(warning, style: TextStyle(color: scheme.onTertiaryContainer)),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (result.partialSkillMatches.isNotEmpty) ...[
            _GenerateSuggestionsButton(
              jd: jd,
              resumeId: resumeId,
              hasPartialMatches: result.partialSkillMatches.isNotEmpty,
            ),
            const SizedBox(height: 12),
          ] else ...[
            // R-11 P0 fix: previously this button simply didn't render with
            // no explanation at all, which real-device testing read as "the
            // JD flow doesn't produce suggestions" - AI rewrite suggestions
            // are only ever generated from a partial skill match (see
            // GenerateResumeSuggestionsUseCase's own doc comment: an exact
            // match needs no rewrite, and a fully-missing skill has no
            // resume text to rewrite from without inventing content), so
            // zero partial matches correctly means zero suggestions are
            // possible here - this card says that plainly instead of
            // looking broken.
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: scheme.onSurfaceVariant, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No AI rewrite suggestions are available for this resume. This '
                        'happens when your skills already directly match the job '
                        "description, or when there's nothing in your resume to safely "
                        "rewrite without inventing content that isn't there. Check the "
                        "Missing section above for skills you may want to add yourself.",
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton(
            onPressed: () => ref.read(resumeJdAnalysisControllerProvider(jd).notifier).reset(),
            child: const Text('Analyze a different resume'),
          ),
        ],
      ),
    );
  }
}

/// Triggers `GenerateResumeSuggestionsUseCase` for [resumeId] against
/// [jd] (docs/v3/01-prd.md §25 Milestone 3) and, on success, navigates to
/// the Suggestion Review screen - the JD's own requirements and the
/// already-computed match results only ever live on this screen (a JD is
/// held in memory for the current session only, per FR3-05), so this is
/// the one place generation can genuinely be triggered from; the Editor's
/// own entry point (`_EditorOverflowMenu`'s "AI suggestions" item,
/// resume_editor_screen.dart) only ever *reviews* suggestions that already
/// exist, it never generates new ones.
class _GenerateSuggestionsButton extends ConsumerWidget {
  const _GenerateSuggestionsButton({
    required this.jd,
    required this.resumeId,
    required this.hasPartialMatches,
  });

  final ParsedJobDescription jd;
  final int resumeId;
  final bool hasPartialMatches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(generateSuggestionsControllerProvider(resumeId));

    ref.listen<GenerateSuggestionsUiState>(generateSuggestionsControllerProvider(resumeId),
        (previous, next) {
      if (next is GenerateSuggestionsSucceeded) {
        ref.read(generateSuggestionsControllerProvider(resumeId).notifier).reset();
        if (context.mounted) context.push(RoutePaths.resumeSuggestionsPath(resumeId));
      } else if (next is GenerateSuggestionsFailed) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
        }
      }
    });

    final isRunning = state is GenerateSuggestionsRunning;

    return FilledButton.icon(
      onPressed: (!hasPartialMatches || isRunning)
          ? null
          : () => ref.read(generateSuggestionsControllerProvider(resumeId).notifier).generate(jd),
      icon: isRunning
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome_outlined),
      label: Text(isRunning ? 'Generating suggestions…' : 'Generate AI suggestions'),
    );
  }
}

class _MatchSection extends StatelessWidget {
  const _MatchSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.matches,
    required this.resumeId,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<SkillMatchResult> matches;
  final int resumeId;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading('$title (${matches.length})'),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final match in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(match.jdRequirement),
                                if (match.resumeEvidence != null)
                                  Text(
                                    match.resumeEvidence!,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          _GoToEditorButton(resumeId: resumeId),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequirementChecksCard extends StatelessWidget {
  const _RequirementChecksCard({required this.checks, required this.resumeId});

  final List<RequirementCheckResult> checks;
  final int resumeId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final check in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(check.jdRequirement),
                          Text(
                            switch (check.level) {
                              MatchLevel.exact => check.resumeEvidence != null
                                  ? 'Found in resume: ${check.resumeEvidence}'
                                  : 'Found in resume.',
                              MatchLevel.partial => check.resumeEvidence != null
                                  ? 'Related content found: ${check.resumeEvidence}'
                                  : 'Related content found in resume.',
                              MatchLevel.missing => 'Not found in resume.',
                            },
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    _GoToEditorButton(resumeId: resumeId),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Navigates back into [resumeId]'s editor (docs/v3/01-prd.md §25
/// Milestone 2, hard requirement 6: every analysis finding needs a working
/// path back into the editor). No section-specific deep link/scroll
/// anchor exists anywhere in the app yet - this opens the resume editor's
/// top level, the same destination every other "open this resume" action
/// in the app already uses (see `resume_list_screen.dart`), rather than
/// inventing a new, unproven navigation mechanism for this one screen.
class _GoToEditorButton extends StatelessWidget {
  const _GoToEditorButton({required this.resumeId});

  final int resumeId;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.push(RoutePaths.resumeEditorPath(resumeId)),
      child: const Text('Go to editor'),
    );
  }
}
