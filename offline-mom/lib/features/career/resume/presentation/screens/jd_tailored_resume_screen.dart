import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/project_block.dart' show ProjectBlockStatus;
import '../../../../../models/skill_entry.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/career/beginner/role_category.dart' show SuggestedSkill;
import '../../../../../shared/widgets/ai_disclaimer.dart';
import '../../../../../shared/widgets/section_heading.dart';
import '../../../jd/presentation/providers/jd_import_providers.dart';
import '../../create_jd_tailored_resume_use_case.dart';
import '../../generate_jd_tailored_draft_use_case.dart';
import '../widgets/bullet_suggestion_field.dart';

enum _Step { basics, jobDescription, education, experience, projects, skills, review }

extension on _Step {
  String get label => switch (this) {
        _Step.basics => 'Basic details',
        _Step.jobDescription => 'Job description',
        _Step.education => 'Education',
        _Step.experience => 'Experience',
        _Step.projects => 'Projects',
        _Step.skills => 'Skills',
        _Step.review => 'Review',
      };
}

/// One in-progress "Internship / part-time / volunteer / previous
/// employment" entry - the exact same lighter-weight shape
/// `BeginnerResumeScreen`'s own `_ExperienceDraft` uses.
class _ExperienceDraft {
  _ExperienceDraft()
      : title = TextEditingController(),
        organization = TextEditingController(),
        when = TextEditingController(),
        description = TextEditingController();

  final TextEditingController title;
  final TextEditingController organization;
  final TextEditingController when;
  final TextEditingController description;

  void dispose() {
    title.dispose();
    organization.dispose();
    when.dispose();
    description.dispose();
  }

  JdTailoredExperienceEntryInput toInput() => JdTailoredExperienceEntryInput(
        title: title.text,
        organization: organization.text,
        when: when.text,
        description: description.text,
      );
}

/// One in-progress real, already-completed project the user typed
/// themselves (as opposed to an AI-suggested idea) - always persisted with
/// `status: completed` (see `CreateJdTailoredResumeUseCase`'s own doc
/// comment).
class _ProjectDraft {
  _ProjectDraft()
      : name = TextEditingController(),
        link = TextEditingController(),
        bullets = TextEditingController();

  final TextEditingController name;
  final TextEditingController link;
  final TextEditingController bullets;

  bool get isBlank => name.text.trim().isEmpty;

  void dispose() {
    name.dispose();
    link.dispose();
    bullets.dispose();
  }
}

/// "Create Resume for a Job" - fills basic details, pastes/imports a Job
/// Description, then reviews an AI-proposed professional summary,
/// JD-recommended skills, and JD-relevant project ideas before any resume
/// is created. Ends by creating a real [Resume] via
/// [CreateJdTailoredResumeUseCase] and handing off to the *existing*
/// Template Gallery and Resume Editor - this screen only ever collects and
/// reviews input; every persistence/rendering/export concern is reused
/// unchanged from the standard resume architecture.
///
/// Deliberately a standalone flow, not a retrofit of `JdToResumeScreen`
/// (which requires a pre-existing "My Profile" and has no basic-details
/// step of its own) - see docs/v3/implementation/03-decisions.md.
///
/// **The core rule this whole screen enforces**: an AI recommendation
/// (a skill or a project idea) never becomes part of the resume on its
/// own - see [_confirmedSkills] and [_confirmedProjectEntries], both of
/// which only ever include what the user explicitly accepted at the
/// review step.
class JdTailoredResumeScreen extends ConsumerStatefulWidget {
  const JdTailoredResumeScreen({super.key});

  @override
  ConsumerState<JdTailoredResumeScreen> createState() => _JdTailoredResumeScreenState();
}

class _JdTailoredResumeScreenState extends ConsumerState<JdTailoredResumeScreen> {
  static const _steps = _Step.values;

  int _stepIndex = 0;
  _Step get _step => _steps[_stepIndex];

  // Step 1 - basics.
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _locationController = TextEditingController();
  final _linkedInController = TextEditingController();
  final _portfolioController = TextEditingController();

  // Step 2 - job description (mandatory for this flow).
  final _jdPasteController = TextEditingController();
  final _targetRoleOverrideController = TextEditingController();

  // Step 3 - education (all optional).
  final _degreeController = TextEditingController();
  final _institutionController = TextEditingController();
  final _gradYearController = TextEditingController();

  // Step 4 - experience (optional, repeatable).
  final List<_ExperienceDraft> _experienceDrafts = [];

  // Step 5 - existing/completed projects (optional, repeatable).
  final List<_ProjectDraft> _existingProjectDrafts = [];

  // Step 6 - the user's own skills.
  final _ownSkillController = TextEditingController();
  List<String> _ownSkills = [];

  // Step 7 - review.
  final _summaryController = TextEditingController();
  JdTailoredDraft? _draft;
  bool _isGeneratingDraft = false;
  final Set<String> _acceptedRecommendedSkillNames = {};
  final List<JdTailoredProjectEntryInput> _confirmedProjectIdeas = [];
  final Set<int> _handledIdeaIndices = {};
  bool _isCreating = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    // jdImportControllerProvider is shared with every other JD-related
    // flow (BeginnerResumeScreen, JdToResumeScreen, JdImportScreen) -
    // resetting on entry means a JD left mid-review elsewhere never leaks
    // into this screen as unexpected pre-filled state.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(jdImportControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    _linkedInController.dispose();
    _portfolioController.dispose();
    _jdPasteController.dispose();
    _targetRoleOverrideController.dispose();
    _degreeController.dispose();
    _institutionController.dispose();
    _gradYearController.dispose();
    for (final draft in _experienceDrafts) {
      draft.dispose();
    }
    for (final draft in _existingProjectDrafts) {
      draft.dispose();
    }
    _ownSkillController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  bool get _hasJdReady => ref.read(jdImportControllerProvider) is JdImportReviewing;

  bool get _canGoNext => switch (_step) {
        _Step.basics => _nameController.text.trim().isNotEmpty,
        _Step.jobDescription => _hasJdReady,
        _ => true,
      };

  String get _effectiveRoleLabel {
    final override = _targetRoleOverrideController.text.trim();
    if (override.isNotEmpty) return override;
    final jdState = ref.read(jdImportControllerProvider);
    if (jdState is JdImportReviewing) {
      final title = jdState.draft.title;
      if (title != null && title.trim().isNotEmpty) return title.trim();
    }
    return 'this role';
  }

  /// The user's own typed skills plus whichever JD-recommended skills they
  /// explicitly accepted - never more (see this class's own doc comment).
  List<SuggestedSkill> get _confirmedSkills {
    final own = [for (final name in _ownSkills) SuggestedSkill(name, SkillCategory.technical)];
    final draft = _draft;
    if (draft == null) return own;
    final accepted = [
      for (final skill in draft.recommendedSkills)
        if (_acceptedRecommendedSkillNames.contains(skill.name))
          SuggestedSkill(skill.name, skill.suggestedCategory),
    ];
    return [...own, ...accepted];
  }

  /// The user's own real projects (always `status: completed`) plus
  /// whichever AI-suggested ideas they explicitly confirmed - never more.
  List<JdTailoredProjectEntryInput> get _confirmedProjectEntries {
    final own = [
      for (final draft in _existingProjectDrafts)
        if (!draft.isBlank)
          JdTailoredProjectEntryInput(
            name: draft.name.text,
            link: draft.link.text,
            bullets: draft.bullets.text.split('\n'),
            status: ProjectBlockStatus.completed,
          ),
    ];
    return [...own, ..._confirmedProjectIdeas];
  }

  void _goNext() {
    if (!_canGoNext || _stepIndex >= _steps.length - 1) return;
    setState(() => _stepIndex++);
    if (_step == _Step.review) _maybeGenerateDraft();
  }

  void _goBack() {
    if (_stepIndex <= 0) return;
    setState(() => _stepIndex--);
  }

  void _goToStep(int index) {
    if (index < 0 || index >= _steps.length) return;
    if (index > _stepIndex && !_canGoNext) return;
    setState(() => _stepIndex = index);
    if (_steps[index] == _Step.review) _maybeGenerateDraft();
  }

  Future<void> _maybeGenerateDraft() async {
    if (_draft != null || _isGeneratingDraft) return;
    setState(() => _isGeneratingDraft = true);

    final jdState = ref.read(jdImportControllerProvider);
    final jd = jdState is JdImportReviewing ? jdState.draft : null;
    if (jd == null) {
      setState(() => _isGeneratingDraft = false);
      return;
    }

    final experienceOneLiners = [
      for (final draft in _experienceDrafts)
        if (draft.title.text.trim().isNotEmpty || draft.organization.text.trim().isNotEmpty)
          '${draft.title.text.trim()} at ${draft.organization.text.trim()}',
    ];
    final existingProjectNames = [
      for (final draft in _existingProjectDrafts)
        if (!draft.isBlank) draft.name.text.trim(),
    ];

    final draft = await ref.read(generateJdTailoredDraftUseCaseProvider).call(
          targetRoleLabel: _effectiveRoleLabel,
          jd: jd,
          confirmedSkillNames: _ownSkills,
          educationLabel: _degreeController.text,
          experienceOneLiners: experienceOneLiners,
          existingProjectNames: existingProjectNames,
        );

    if (!mounted) return;
    setState(() {
      _draft = draft;
      _isGeneratingDraft = false;
      _summaryController.text = draft.summaryText;
    });
  }

  Future<void> _createResume() async {
    if (_isCreating) return;
    setState(() {
      _isCreating = true;
      _createError = null;
    });

    try {
      final input = JdTailoredResumeInput(
        fullName: _nameController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        location: _locationController.text,
        linkedIn: _linkedInController.text,
        portfolio: _portfolioController.text,
        targetRoleLabel: _effectiveRoleLabel,
        degree: _degreeController.text,
        institution: _institutionController.text,
        graduationYear: _gradYearController.text,
        experienceEntries: [for (final draft in _experienceDrafts) draft.toInput()],
        projectEntries: _confirmedProjectEntries,
        confirmedSkills: _confirmedSkills,
        summaryText: _summaryController.text,
      );
      final resumeId = await ref.read(createJdTailoredResumeUseCaseProvider)(input);
      if (!mounted) return;
      context.pushReplacement(RoutePaths.resumeTemplatesPath(resumeId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createError = friendlyErrorMessage(e);
      });
    }
  }

  void _acceptProjectIdea(int index, ProjectIdea idea, ProjectBlockStatus status) async {
    final result = await showDialog<JdTailoredProjectEntryInput>(
      context: context,
      builder: (context) => _ConfirmProjectIdeaDialog(idea: idea, status: status),
    );
    if (result == null || !mounted) return;
    setState(() {
      _confirmedProjectIdeas.add(result);
      _handledIdeaIndices.add(index);
    });
  }

  void _declineProjectIdea(int index) {
    setState(() => _handledIdeaIndices.add(index));
  }

  @override
  Widget build(BuildContext context) {
    // Makes this widget rebuild when the shared jdImportControllerProvider
    // finishes parsing a pasted/imported JD - see BeginnerResumeScreen's
    // identical comment for why this one `ref.watch` (rather than relying
    // on `_JdStatus` alone) is what unsticks `_canGoNext`/"Next".
    ref.watch(jdImportControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Resume for a Job')),
      body: Column(
        children: [
          _StepBar(current: _stepIndex, steps: _steps, onStepTapped: _goToStep),
          Expanded(
            child: SingleChildScrollView(
              key: ValueKey(_step),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: _stepBody(),
            ),
          ),
          _NavBar(
            canGoNext: _canGoNext,
            isLast: _step == _Step.review,
            isBusy: _isCreating,
            onBack: _stepIndex > 0 ? _goBack : null,
            onNext: _step == _Step.review ? _createResume : _goNext,
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    return switch (_step) {
      _Step.basics => _BasicsStep(
          nameController: _nameController,
          phoneController: _phoneController,
          emailController: _emailController,
          locationController: _locationController,
          linkedInController: _linkedInController,
          portfolioController: _portfolioController,
          onChanged: () => setState(() {}),
        ),
      _Step.jobDescription => _JobDescriptionStep(
          jdPasteController: _jdPasteController,
          targetRoleOverrideController: _targetRoleOverrideController,
        ),
      _Step.education => _EducationStep(
          degreeController: _degreeController,
          institutionController: _institutionController,
          gradYearController: _gradYearController,
        ),
      _Step.experience => _ExperienceStep(
          drafts: _experienceDrafts,
          onAdd: () => setState(() => _experienceDrafts.add(_ExperienceDraft())),
          onRemove: (draft) => setState(() {
            _experienceDrafts.remove(draft);
            draft.dispose();
          }),
        ),
      _Step.projects => _ProjectsStep(
          drafts: _existingProjectDrafts,
          onAdd: () => setState(() => _existingProjectDrafts.add(_ProjectDraft())),
          onRemove: (draft) => setState(() {
            _existingProjectDrafts.remove(draft);
            draft.dispose();
          }),
        ),
      _Step.skills => _SkillsStep(
          ownSkillController: _ownSkillController,
          ownSkills: _ownSkills,
          onOwnSkillsChanged: (skills) => setState(() => _ownSkills = skills),
        ),
      _Step.review => _ReviewStep(
          roleLabel: _effectiveRoleLabel,
          summaryController: _summaryController,
          draft: _draft,
          isGeneratingDraft: _isGeneratingDraft,
          acceptedRecommendedSkillNames: _acceptedRecommendedSkillNames,
          onRecommendedSkillToggled: (name, accept) => setState(() {
            if (accept) {
              _acceptedRecommendedSkillNames.add(name);
            } else {
              _acceptedRecommendedSkillNames.remove(name);
            }
          }),
          ownSkills: _ownSkills,
          experienceEntries: [for (final d in _experienceDrafts) d.toInput()],
          existingProjectDrafts: _existingProjectDrafts,
          handledIdeaIndices: _handledIdeaIndices,
          onAddIdeaAsPlanned: (i, idea) => _acceptProjectIdea(i, idea, ProjectBlockStatus.planned),
          onAddIdeaAsCompleted: (i, idea) => _acceptProjectIdea(i, idea, ProjectBlockStatus.completed),
          onDeclineIdea: _declineProjectIdea,
          createError: _createError,
        ),
    };
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.current, required this.steps, required this.onStepTapped});

  final int current;
  final List<_Step> steps;
  final void Function(int index) onStepTapped;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: steps.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final isCurrent = index == current;
                return ChoiceChip(
                  key: ValueKey('jdTailoredResumeStep_${steps[index].name}'),
                  label: Text(steps[index].label),
                  selected: isCurrent,
                  onSelected: (_) => onStepTapped(index),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: (current + 1) / steps.length, minHeight: 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.canGoNext,
    required this.isLast,
    required this.isBusy,
    required this.onBack,
    required this.onNext,
  });

  final bool canGoNext;
  final bool isLast;
  final bool isBusy;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: isBusy ? null : onBack,
            child: const Text('Back'),
          ),
          const Spacer(),
          Flexible(
            child: FilledButton.icon(
              key: const Key('jdTailoredResumeNextButton'),
              onPressed: (canGoNext && !isBusy) ? onNext : null,
              icon: isBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(isLast ? Icons.auto_awesome_rounded : Icons.chevron_right_rounded),
              label: Text(
                isBusy ? 'Creating…' : (isLast ? 'Create Resume' : 'Next'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BasicsStep extends StatelessWidget {
  const _BasicsStep({
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.locationController,
    required this.linkedInController,
    required this.portfolioController,
    required this.onChanged,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController locationController;
  final TextEditingController linkedInController;
  final TextEditingController portfolioController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Let's start with the basics.", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Only your name is required - add what you can, skip the rest.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('jdTailoredNameField'),
          controller: nameController,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: locationController,
          decoration: const InputDecoration(
            labelText: 'Location (optional)',
            hintText: 'e.g. Pune, India',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: linkedInController,
          decoration: const InputDecoration(labelText: 'LinkedIn (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: portfolioController,
          decoration:
              const InputDecoration(labelText: 'Portfolio/website (optional)', border: OutlineInputBorder()),
        ),
      ],
    );
  }
}

class _JobDescriptionStep extends ConsumerWidget {
  const _JobDescriptionStep({required this.jdPasteController, required this.targetRoleOverrideController});

  final TextEditingController jdPasteController;
  final TextEditingController targetRoleOverrideController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paste the job description', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          "We'll use this to suggest skills, a summary, and project ideas for "
          'this specific job - nothing is added to your resume without your say.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('jdTailoredJdPasteField'),
          controller: jdPasteController,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'Paste the full job description here…',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('jdTailoredJdUseTextButton'),
              onPressed: () {
                final text = jdPasteController.text;
                if (text.trim().isEmpty) return;
                ref.read(jdImportControllerProvider.notifier).parseText(text);
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Use this'),
            ),
            OutlinedButton.icon(
              key: const Key('jdTailoredJdImportButton'),
              onPressed: () => ref.read(jdImportControllerProvider.notifier).pickAndParse(),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Import a file'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _JdStatus(),
        const SizedBox(height: 20),
        TextField(
          controller: targetRoleOverrideController,
          decoration: const InputDecoration(
            labelText: 'Target role (optional override)',
            hintText: "Defaults to the job title detected above",
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _JdStatus extends ConsumerWidget {
  const _JdStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(jdImportControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return switch (state) {
      JdImportIdle() || JdImportConfirmed() => const SizedBox.shrink(),
      JdImportProcessing() => const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Reading the job description…'),
            ],
          ),
        ),
      JdImportFailed(:final message) => Text(message, style: TextStyle(color: scheme.error)),
      JdImportReviewing(:final draft) => Card(
          color: scheme.secondaryContainer,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_outlined, size: 18, color: scheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        draft.title ?? 'Job description',
                        style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
                if (draft.company != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 26),
                    child: Text(draft.company!, style: TextStyle(color: scheme.onSecondaryContainer)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 26),
                  child: Text(
                    '${draft.requirements.length} requirement(s) detected.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => ref.read(jdImportControllerProvider.notifier).reset(),
                    child: const Text('Change'),
                  ),
                ),
              ],
            ),
          ),
        ),
    };
  }
}

class _EducationStep extends StatelessWidget {
  const _EducationStep({
    required this.degreeController,
    required this.institutionController,
    required this.gradYearController,
  });

  final TextEditingController degreeController;
  final TextEditingController institutionController;
  final TextEditingController gradYearController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Education (optional)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Leave blank to skip this section entirely.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('jdTailoredDegreeField'),
          controller: degreeController,
          decoration: const InputDecoration(
            labelText: 'Degree',
            hintText: 'e.g. B.Com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: institutionController,
          decoration: const InputDecoration(labelText: 'Institution', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: gradYearController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Graduation year', border: OutlineInputBorder()),
        ),
      ],
    );
  }
}

class _ExperienceStep extends StatelessWidget {
  const _ExperienceStep({required this.drafts, required this.onAdd, required this.onRemove});

  final List<_ExperienceDraft> drafts;
  final VoidCallback onAdd;
  final void Function(_ExperienceDraft draft) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Experience (optional)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          "If you don't have any, skip this and move on. Nothing here is invented for you.",
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final draft in drafts) ...[
          _ExperienceEntryCard(draft: draft, onRemove: () => onRemove(draft)),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          key: const Key('jdTailoredAddExperienceButton'),
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(drafts.isEmpty ? 'Add experience' : 'Add another'),
        ),
      ],
    );
  }
}

class _ExperienceEntryCard extends StatelessWidget {
  const _ExperienceEntryCard({required this.draft, required this.onRemove});

  final _ExperienceDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. Marketing Intern',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.organization,
              decoration: const InputDecoration(
                labelText: 'Organization',
                hintText: 'e.g. Acme Retail Pvt Ltd',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.when,
              decoration: const InputDecoration(labelText: 'When', hintText: 'e.g. Summer 2023', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What did you do? (optional, one line per point)',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectsStep extends StatelessWidget {
  const _ProjectsStep({required this.drafts, required this.onAdd, required this.onRemove});

  final List<_ProjectDraft> drafts;
  final VoidCallback onAdd;
  final void Function(_ProjectDraft draft) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your own projects (optional)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          "Projects you've actually completed. If you don't have any yet, "
          "skip this - you'll see AI-suggested project ideas later that you "
          'can add only if you build them.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final draft in drafts) ...[
          _ProjectEntryCard(draft: draft, onRemove: () => onRemove(draft)),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          key: const Key('jdTailoredAddProjectButton'),
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(drafts.isEmpty ? 'Add a project' : 'Add another'),
        ),
      ],
    );
  }
}

class _ProjectEntryCard extends StatelessWidget {
  const _ProjectEntryCard({required this.draft, required this.onRemove});

  final _ProjectDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.name,
                    decoration: const InputDecoration(labelText: 'Project name', isDense: true),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.link,
              decoration: const InputDecoration(labelText: 'Link (optional)', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.bullets,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What did it involve? (one line per point)',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillsStep extends StatelessWidget {
  const _SkillsStep({
    required this.ownSkillController,
    required this.ownSkills,
    required this.onOwnSkillsChanged,
  });

  final TextEditingController ownSkillController;
  final List<String> ownSkills;
  final ValueChanged<List<String>> onOwnSkillsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your skills', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Add only the skills you actually have - the next step will show '
          'skills from the job description you can add separately if you '
          'want to learn or already know them.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _ChipListEditor(
          key: const Key('jdTailoredOwnSkillsEditor'),
          hintText: 'Type a skill and add it',
          items: ownSkills,
          onChanged: onOwnSkillsChanged,
        ),
      ],
    );
  }
}

class _ChipListEditor extends StatefulWidget {
  const _ChipListEditor({super.key, required this.items, required this.onChanged, required this.hintText});

  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String hintText;

  @override
  State<_ChipListEditor> createState() => _ChipListEditorState();
}

class _ChipListEditorState extends State<_ChipListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onChanged([...widget.items, value]);
    _controller.clear();
  }

  void _remove(String value) {
    widget.onChanged(widget.items.where((v) => v != value).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(hintText: widget.hintText, isDense: true),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: _add, icon: const Icon(Icons.add_rounded), tooltip: 'Add'),
          ],
        ),
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in widget.items) Chip(label: Text(item), onDeleted: () => _remove(item)),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.roleLabel,
    required this.summaryController,
    required this.draft,
    required this.isGeneratingDraft,
    required this.acceptedRecommendedSkillNames,
    required this.onRecommendedSkillToggled,
    required this.ownSkills,
    required this.experienceEntries,
    required this.existingProjectDrafts,
    required this.handledIdeaIndices,
    required this.onAddIdeaAsPlanned,
    required this.onAddIdeaAsCompleted,
    required this.onDeclineIdea,
    required this.createError,
  });

  final String roleLabel;
  final TextEditingController summaryController;
  final JdTailoredDraft? draft;
  final bool isGeneratingDraft;
  final Set<String> acceptedRecommendedSkillNames;
  final void Function(String name, bool accept) onRecommendedSkillToggled;
  final List<String> ownSkills;
  final List<JdTailoredExperienceEntryInput> experienceEntries;
  final List<_ProjectDraft> existingProjectDrafts;
  final Set<int> handledIdeaIndices;
  final void Function(int index, ProjectIdea idea) onAddIdeaAsPlanned;
  final void Function(int index, ProjectIdea idea) onAddIdeaAsCompleted;
  final void Function(int index) onDeclineIdea;
  final String? createError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final realExperience = experienceEntries.where((e) => !e.isBlank).toList();
    final realExistingProjects = existingProjectDrafts.where((d) => !d.isBlank).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review your tailored resume', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Nothing below is added to your resume until you tap "Create Resume" - '
          'review and edit everything first.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _ReviewRow(label: 'Target role', value: roleLabel),
        const SizedBox(height: 16),

        const SectionHeading('Professional summary', dense: true),
        const SizedBox(height: 4),
        if (isGeneratingDraft)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Generating suggestions…'),
              ],
            ),
          )
        else ...[
          if (draft != null && !draft!.summaryWasGenerated)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'AI resume suggestions are unavailable right now - a simple '
                'summary was filled in instead. You can still create your '
                'resume normally.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          BulletSuggestionField(
            controller: summaryController,
            entryContextLabel: '$roleLabel resume summary',
            labelText: 'Summary',
            helperText: null,
          ),
        ],
        const SizedBox(height: 16),

        const SectionHeading('Confirmed skills', dense: true),
        const SizedBox(height: 4),
        Text(
          'Skills you added yourself.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ownSkills.isEmpty
              ? [Text('None added', style: TextStyle(color: scheme.onSurfaceVariant))]
              : [for (final s in ownSkills) Chip(label: Text(s))],
        ),

        if (draft != null && draft!.recommendedSkills.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeading('Skills from the Job Description', dense: true),
          const SizedBox(height: 4),
          Text(
            'These are skills mentioned in the job description. Add only the '
            'ones you actually know.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in draft!.recommendedSkills)
                FilterChip(
                  key: ValueKey('jdTailoredRecommendedSkill_${skill.name}'),
                  label: Text(skill.name),
                  selected: acceptedRecommendedSkillNames.contains(skill.name),
                  onSelected: (accept) => onRecommendedSkillToggled(skill.name, accept),
                ),
            ],
          ),
        ],

        if (draft != null && draft!.jdKeywordsCovered.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeading('Important words from this job description', dense: true),
          const SizedBox(height: 8),
          Text('Already covered:', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in draft!.jdKeywordsCovered)
                Chip(
                  label: Text(k),
                  backgroundColor: scheme.primaryContainer,
                  labelStyle: TextStyle(color: scheme.onPrimaryContainer),
                ),
            ],
          ),
        ],

        if (realExperience.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeading('Experience', dense: true),
          const SizedBox(height: 8),
          for (final entry in realExperience)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.title} at ${entry.organization}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (entry.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(entry.description),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],

        if (realExistingProjects.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeading('Your projects', dense: true),
          const SizedBox(height: 8),
          for (final p in realExistingProjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(p.name.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ],

        if (draft != null && draft!.suggestedProjectIdeas.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeading('Project ideas related to this job', dense: true),
          const SizedBox(height: 4),
          Text(
            'These are project ideas related to this job. Add them only if '
            'you have completed them, or add as a planned project you intend '
            'to build.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < draft!.suggestedProjectIdeas.length; i++)
            if (!handledIdeaIndices.contains(i))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ProjectIdeaCard(
                  idea: draft!.suggestedProjectIdeas[i],
                  onAddPlanned: () => onAddIdeaAsPlanned(i, draft!.suggestedProjectIdeas[i]),
                  onAddCompleted: () => onAddIdeaAsCompleted(i, draft!.suggestedProjectIdeas[i]),
                  onDecline: () => onDeclineIdea(i),
                ),
              ),
        ],

        const SizedBox(height: 16),
        const AiDisclaimer(
          text: 'AI can make mistakes. Review and verify all generated content before using your resume.',
        ),

        if (createError != null) ...[
          const SizedBox(height: 16),
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(createError!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProjectIdeaCard extends StatelessWidget {
  const _ProjectIdeaCard({
    required this.idea,
    required this.onAddPlanned,
    required this.onAddCompleted,
    required this.onDecline,
  });

  final ProjectIdea idea;
  final VoidCallback onAddPlanned;
  final VoidCallback onAddCompleted;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Idea: ${idea.title}',
                style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer)),
            if (idea.suggestedTechnologies.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Suggested technologies: ${idea.suggestedTechnologies.join(', ')}',
                style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12),
              ),
            ],
            if (idea.suggestedFeatures.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Suggested features: ${idea.suggestedFeatures.join(', ')}',
                style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: onAddPlanned, child: const Text('Add as Planned Project')),
                OutlinedButton(onPressed: onAddCompleted, child: const Text("I've Actually Completed This")),
                TextButton(onPressed: onDecline, child: const Text("Don't Add")),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Requires the user to type/confirm real bullet text before an AI project
/// idea can be added - the idea's own suggested title/features are only a
/// starting point, never inserted verbatim without this step (see
/// `CreateJdTailoredResumeUseCase`'s own doc comment on why every project
/// entry it receives already carries user-confirmed bullets, never raw AI
/// text).
class _ConfirmProjectIdeaDialog extends StatefulWidget {
  const _ConfirmProjectIdeaDialog({required this.idea, required this.status});

  final ProjectIdea idea;
  final ProjectBlockStatus status;

  @override
  State<_ConfirmProjectIdeaDialog> createState() => _ConfirmProjectIdeaDialogState();
}

class _ConfirmProjectIdeaDialogState extends State<_ConfirmProjectIdeaDialog> {
  late final _nameController = TextEditingController(text: widget.idea.title);
  late final _linkController = TextEditingController();
  late final _bulletsController = TextEditingController(
    text: widget.idea.suggestedFeatures.join('\n'),
  );

  @override
  void dispose() {
    _nameController.dispose();
    _linkController.dispose();
    _bulletsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = widget.status == ProjectBlockStatus.completed;
    return AlertDialog(
      title: Text(isCompleted ? "Confirm what you've completed" : 'Confirm your planned project'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCompleted
                  ? 'Edit the details below to describe what you actually built.'
                  : 'Edit the details below - this will be added as a planned project.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Project name', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _linkController,
              decoration: const InputDecoration(labelText: 'Link (optional)', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bulletsController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Details (one line per point)', isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_nameController.text.trim().isEmpty) return;
            Navigator.of(context).pop(
              JdTailoredProjectEntryInput(
                name: _nameController.text,
                link: _linkController.text,
                bullets: _bulletsController.text.split('\n'),
                status: widget.status,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
