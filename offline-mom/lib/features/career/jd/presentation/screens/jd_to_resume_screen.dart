import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/job_description.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../shared/widgets/section_heading.dart';
import '../../../analysis/presentation/providers/resume_jd_analysis_providers.dart';
import '../../../resume/create_resume_from_profile_use_case.dart' show NoProfileException;
import '../../../resume/presentation/providers/resume_providers.dart' show openOrCreateProfile;
import '../providers/jd_import_providers.dart';

/// R-7 §3: "Create resume from a Job Description" - a clear, first-class
/// alternative to the existing "pick an existing resume, then analyze it
/// against a JD" flow (`JdImportScreen` -> `ResumeJdAnalysisScreen`). This
/// screen leads with pasting the JD text (its own explicit requirement:
/// "Paste your JD and get a tailored resume"), with importing a file as
/// the secondary option - the opposite emphasis of `JdImportScreen`, which
/// leads with file import because analysis mode has no reason to prefer
/// one over the other.
///
/// Reuses [jdImportControllerProvider] unchanged (same parsing, same
/// states) and [CreateResumeFromJdUseCase] for resume creation - no new
/// JD-parsing or resume-creation logic lives here, only a different entry
/// UI and a different destination on confirm.
class JdToResumeScreen extends ConsumerStatefulWidget {
  const JdToResumeScreen({super.key});

  @override
  ConsumerState<JdToResumeScreen> createState() => _JdToResumeScreenState();
}

class _JdToResumeScreenState extends ConsumerState<JdToResumeScreen> {
  final _textController = TextEditingController();
  bool _isCreating = false;
  String? _createError;
  // R-11 P0 fix: on a real device, "My Profile" is very often not set up
  // yet, so `CreateResumeFromJdUseCase` throws `NoProfileException` and no
  // resume is ever created - the flow then looked "broken" (no resume, no
  // suggestions) with only a plain error string and no way forward. This
  // flag distinguishes that one specific, recoverable case so the UI can
  // offer a real next step instead of a dead end.
  bool _needsProfileSetup = false;

  @override
  void initState() {
    super.initState();
    // `jdImportControllerProvider` is shared with the existing "Analyze
    // against a job description" flow (`JdImportScreen`) - resetting on
    // entry means a JD left mid-review there never leaks into this screen
    // as an unexpected pre-filled state.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(jdImportControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _createResume(ParsedJobDescription jd) async {
    if (_isCreating) return;
    setState(() {
      _isCreating = true;
      _createError = null;
      _needsProfileSetup = false;
    });
    try {
      final resumeId = await ref.read(createResumeFromJdUseCaseProvider)(jd);
      if (!mounted) return;
      context.pushReplacement(
        RoutePaths.resumeJdAnalysis,
        extra: ResumeJdAnalysisLaunchArgs(jd: jd, initialResumeId: resumeId),
      );
    } on NoProfileException catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createError = e.message;
        _needsProfileSetup = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createError = friendlyErrorMessage(e);
      });
    }
  }

  // R-11 P0 fix: sends the user to set up "My Profile" (creating it on
  // first use, same as the Resume list screen's own entry point) via
  // `context.push` (not a replace) so popping back returns to this exact
  // screen with the already-parsed JD still shown, ready to retry
  // "Create my resume" - no JD re-paste, no re-parse.
  Future<void> _setUpProfile() async {
    final id = await openOrCreateProfile(ref);
    if (!mounted) return;
    await context.push(RoutePaths.resumeEditorPath(id));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(jdImportControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Resume from a Job Description')),
      body: switch (state) {
        JdImportIdle() || JdImportProcessing() => _PasteOrImportBody(
            isProcessing: state is JdImportProcessing,
            controller: _textController,
            onUseText: () => ref.read(jdImportControllerProvider.notifier).parseText(_textController.text),
            onImportFile: () => ref.read(jdImportControllerProvider.notifier).pickAndParse(),
          ),
        JdImportReviewing(:final draft) => _ReviewAndCreateBody(
            draft: draft,
            isCreating: _isCreating,
            createError: _createError,
            needsProfileSetup: _needsProfileSetup,
            onBack: () => ref.read(jdImportControllerProvider.notifier).reset(),
            onCreate: () => _createResume(draft),
            onSetUpProfile: _setUpProfile,
          ),
        JdImportConfirmed() => const SizedBox.shrink(),
        JdImportFailed(:final message) => Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.read(jdImportControllerProvider.notifier).reset(),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
      },
    );
  }
}

class _PasteOrImportBody extends StatelessWidget {
  const _PasteOrImportBody({
    required this.isProcessing,
    required this.controller,
    required this.onUseText,
    required this.onImportFile,
  });

  final bool isProcessing;
  final TextEditingController controller;
  final VoidCallback onUseText;
  final VoidCallback onImportFile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste your JD and get a tailored resume.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              "We'll build a new resume from your saved Profile, prioritized "
              'toward what this job description actually asks for - nothing '
              "is invented beyond what's already in your Profile.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('jdPasteField'),
              controller: controller,
              enabled: !isProcessing,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                hintText: 'Paste the job description here…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('jdUseTextButton'),
              onPressed: isProcessing ? null : onUseText,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Use this text'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: isProcessing ? null : onImportFile,
              icon: isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_rounded),
              label: Text(isProcessing ? 'Reading the job description…' : 'Import a JD file instead'),
            ),
            const SizedBox(height: 8),
            Text(
              'Supports PDF, DOCX, TXT and Markdown.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              'The job description is read and analyzed entirely on this '
              'device. Nothing is ever uploaded or sent anywhere.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewAndCreateBody extends StatelessWidget {
  const _ReviewAndCreateBody({
    required this.draft,
    required this.isCreating,
    required this.createError,
    required this.needsProfileSetup,
    required this.onBack,
    required this.onCreate,
    required this.onSetUpProfile,
  });

  final ParsedJobDescription draft;
  final bool isCreating;
  final String? createError;
  final bool needsProfileSetup;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onSetUpProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                // R-7 §3: "Clearly see the JD after importing/pasting it" -
                // shown in full, up front, before anything else on this
                // step.
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          draft.title ?? 'Job description',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (draft.company != null) Text(draft.company!),
                        const SizedBox(height: 8),
                        Text(
                          '${draft.requirements.length} requirement(s) detected',
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
                const SectionHeading('Detected requirements'),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: draft.requirements.isEmpty
                          ? [
                              Text(
                                'None detected.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ]
                          : [
                              for (final requirement in draft.requirements)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text('• $requirement'),
                                ),
                            ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  color: scheme.secondaryContainer,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: scheme.onSecondaryContainer, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your new resume is built entirely from your Profile - it '
                            "will never include experience, skills, or education you "
                            "haven't already entered there.",
                            style: TextStyle(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (createError != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: scheme.errorContainer,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(createError!, style: TextStyle(color: scheme.onErrorContainer)),
                          if (needsProfileSetup) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const Key('jdSetUpProfileButton'),
                              onPressed: onSetUpProfile,
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: const Text('Set up My Profile'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your job description is still here - come back to '
                              'this screen and tap "Create my resume" again once '
                              "you've added your experience/education/skills.",
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onErrorContainer),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isCreating ? null : onBack,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('jdCreateResumeButton'),
                    onPressed: isCreating ? null : onCreate,
                    icon: isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(isCreating ? 'Creating…' : 'Create my resume'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
