import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/skill_entry.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/career/beginner/role_category.dart';
import '../../../../../services/career/beginner/role_category_catalog.dart';
import '../../../../../services/career/beginner/role_category_matcher.dart';
import '../../../../../services/career/beginner/role_input_classifier.dart';
import '../../../../../shared/widgets/ai_disclaimer.dart';
import '../../../../../shared/widgets/section_heading.dart';
import '../../../analysis/presentation/providers/resume_jd_analysis_providers.dart';
import '../../../jd/presentation/providers/jd_import_providers.dart';
import '../../create_beginner_resume_use_case.dart';
import '../widgets/bullet_suggestion_field.dart';

enum _Step { basics, role, education, experience, skills, languages, review }

extension on _Step {
  String get label => switch (this) {
        _Step.basics => 'Basic details',
        _Step.role => 'Target role',
        _Step.education => 'Education',
        _Step.experience => 'Experience',
        _Step.skills => 'Skills',
        _Step.languages => 'Languages',
        _Step.review => 'Review',
      };
}

enum _RoleInputMode { pickList, jd }

/// One in-progress "Internship / part-time / volunteer / previous
/// employment" entry, with its own controllers - a lighter-weight form than
/// the standard Experience Block Editor (see
/// [BeginnerExperienceEntryInput]'s own doc comment for why).
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

  BeginnerExperienceEntryInput toInput() => BeginnerExperienceEntryInput(
        title: title.text,
        organization: organization.text,
        when: when.text,
        description: description.text,
      );
}

/// R-10: "Create a Beginner Resume" - a short, progressive flow for a user
/// with little/no experience or projects (fresh graduates, first-time job
/// seekers). Ends by creating a real [Resume] via
/// [CreateBeginnerResumeUseCase] and handing off to the *existing* template
/// chooser ([BeginnerResumeTemplateScreen]) and Resume Editor - this screen
/// only ever collects input; every persistence/rendering/export concern is
/// reused unchanged from the standard resume architecture.
///
/// One screen with an internal step index (mirrors `JdToResumeScreen`'s own
/// state-switched-body shape), not five separate routes - keeps "Back"
/// trivial and avoids a route per step for a flow this short.
class BeginnerResumeScreen extends ConsumerStatefulWidget {
  const BeginnerResumeScreen({super.key});

  @override
  ConsumerState<BeginnerResumeScreen> createState() => _BeginnerResumeScreenState();
}

class _BeginnerResumeScreenState extends ConsumerState<BeginnerResumeScreen> {
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

  // Step 2 - target role.
  _RoleInputMode _roleMode = _RoleInputMode.pickList;
  final _roleSearchController = TextEditingController();
  RoleCategory? _selectedRoleCategory;
  final _jdPasteController = TextEditingController();

  // Step 3 - education (all optional).
  final _degreeController = TextEditingController();
  final _institutionController = TextEditingController();
  final _gradYearController = TextEditingController();

  // Step 4 - experience (optional, repeatable).
  final List<_ExperienceDraft> _experienceDrafts = [];

  // Step 5 - skills.
  final _ownSkillController = TextEditingController();
  List<String> _ownSkills = [];
  final Set<String> _removedSuggestedSkills = {};

  // Step 6 - languages/certifications/achievements.
  List<String> _languages = [];
  List<String> _certifications = [];
  List<String> _achievements = [];

  // Step 7 - review.
  final _summaryController = TextEditingController();
  bool _summarySeeded = false;
  bool _isGenerating = false;
  String? _generateError;

  @override
  void initState() {
    super.initState();
    // `jdImportControllerProvider` is shared with the existing "Analyze
    // against a job description"/"Create resume from a Job Description"
    // flows - resetting on entry means a JD left mid-review there never
    // leaks into this screen as unexpected pre-filled state (mirrors
    // `JdToResumeScreen`'s identical reset-on-entry).
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
    _roleSearchController.dispose();
    _jdPasteController.dispose();
    _degreeController.dispose();
    _institutionController.dispose();
    _gradYearController.dispose();
    for (final draft in _experienceDrafts) {
      draft.dispose();
    }
    _ownSkillController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  bool get _hasJdReady => ref.read(jdImportControllerProvider) is JdImportReviewing;

  bool get _canGoNext => switch (_step) {
        _Step.basics => _nameController.text.trim().isNotEmpty,
        _Step.role => _selectedRoleCategory != null || _hasJdReady,
        _ => true,
      };

  RoleCategory get _effectiveRoleCategory {
    final jdState = ref.read(jdImportControllerProvider);
    if (jdState is JdImportReviewing) {
      final title = jdState.draft.title;
      if (title != null && title.trim().isNotEmpty) {
        return const RoleCategoryMatcher().match(title);
      }
      return RoleCategoryCatalog.generalFresher;
    }
    return _selectedRoleCategory ?? RoleCategoryCatalog.generalFresher;
  }

  String get _effectiveRoleLabel {
    final jdState = ref.read(jdImportControllerProvider);
    if (jdState is JdImportReviewing) {
      final title = jdState.draft.title;
      if (title != null && title.trim().isNotEmpty) return title.trim();
    }
    final typed = _roleSearchController.text.trim();
    if (_selectedRoleCategory != null && typed.isNotEmpty) return typed;
    return _effectiveRoleCategory.displayName;
  }

  List<SuggestedSkill> get _confirmedSkills {
    final role = _effectiveRoleCategory;
    return [
      for (final skill in role.suggestedSkills)
        if (!_removedSuggestedSkills.contains(skill.name)) skill,
      for (final name in _ownSkills) SuggestedSkill(name, SkillCategory.technical),
    ];
  }

  BeginnerResumeInput _buildInput({String? summaryOverride}) {
    return BeginnerResumeInput(
      fullName: _nameController.text,
      phone: _phoneController.text,
      email: _emailController.text,
      location: _locationController.text,
      linkedIn: _linkedInController.text,
      portfolio: _portfolioController.text,
      roleCategory: _effectiveRoleCategory,
      targetRoleLabel: _effectiveRoleLabel,
      degree: _degreeController.text,
      institution: _institutionController.text,
      graduationYear: _gradYearController.text,
      experienceEntries: [for (final draft in _experienceDrafts) draft.toInput()],
      confirmedSkills: _confirmedSkills,
      languages: _languages,
      certifications: _certifications,
      achievements: _achievements,
      summaryOverride: summaryOverride,
    );
  }

  void _goNext() {
    if (!_canGoNext || _stepIndex >= _steps.length - 1) return;
    setState(() => _stepIndex++);
    if (_step == _Step.review && !_summarySeeded) {
      _summaryController.text = buildBeginnerResumeSummary(_buildInput());
      _summarySeeded = true;
    }
  }

  void _goBack() {
    if (_stepIndex <= 0) return;
    setState(() => _stepIndex--);
  }

  void _goToStep(int index) {
    if (index < 0 || index >= _steps.length) return;
    // Only allow jumping backward, or one step forward at a time via the
    // step chips - going straight to Review from Basics would skip past
    // required validation (the role step) with nothing to show there yet.
    if (index > _stepIndex && !_canGoNext) return;
    setState(() => _stepIndex = index);
    if (_steps[index] == _Step.review && !_summarySeeded) {
      _summaryController.text = buildBeginnerResumeSummary(_buildInput());
      _summarySeeded = true;
    }
  }

  Future<void> _generate() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _generateError = null;
    });

    final jdState = ref.read(jdImportControllerProvider);
    final pastedJd = jdState is JdImportReviewing ? jdState.draft : null;

    try {
      final input = _buildInput(summaryOverride: _summaryController.text);
      final resumeId = await ref.read(createBeginnerResumeUseCaseProvider)(input);
      if (!mounted) return;

      if (pastedJd != null) {
        // R-10 §12: hand off to the existing JD analysis/tailoring pipeline
        // exactly the way `JdToResumeScreen` (R-7) already does - same
        // mechanism, same screen, no changes to that flow.
        context.pushReplacement(
          RoutePaths.resumeJdAnalysis,
          extra: ResumeJdAnalysisLaunchArgs(jd: pastedJd, initialResumeId: resumeId),
        );
      } else {
        context.pushReplacement(RoutePaths.resumeBeginnerTemplatePath(resumeId));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _generateError = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // `_canGoNext`/`_effectiveRoleCategory`/etc. below all read
    // `jdImportControllerProvider` via `ref.read` (safe to call from
    // event handlers too, unlike `ref.watch`) - this one `ref.watch` is
    // what actually makes this widget rebuild when a pasted/imported JD
    // finishes parsing, so "Next" stops being stuck disabled the moment
    // the JD summary card appears. Without it, `_JdStatus` (which does
    // watch the provider) updates correctly on its own, but this screen's
    // own `_canGoNext` - computed during *this* build - would keep
    // whatever stale value it had from the last time something else
    // (typing, tapping a step chip) happened to trigger a rebuild here.
    ref.watch(jdImportControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create a Beginner Resume')),
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
            isBusy: _isGenerating,
            onBack: _stepIndex > 0 ? _goBack : null,
            onNext: _step == _Step.review ? _generate : _goNext,
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
      _Step.role => _RoleStep(
          mode: _roleMode,
          onModeChanged: (mode) => setState(() => _roleMode = mode),
          searchController: _roleSearchController,
          selectedCategory: _selectedRoleCategory,
          onCategorySelected: (category) => setState(() {
            _selectedRoleCategory = category;
            _removedSuggestedSkills.clear();
          }),
          jdPasteController: _jdPasteController,
          onChanged: () => setState(() {}),
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
      _Step.skills => _SkillsStep(
          roleCategory: _effectiveRoleCategory,
          removedSuggestedSkills: _removedSuggestedSkills,
          onSuggestedSkillToggled: (name, keep) => setState(() {
            if (keep) {
              _removedSuggestedSkills.remove(name);
            } else {
              _removedSuggestedSkills.add(name);
            }
          }),
          ownSkillController: _ownSkillController,
          ownSkills: _ownSkills,
          onOwnSkillsChanged: (skills) => setState(() => _ownSkills = skills),
        ),
      _Step.languages => _OptionalListsStep(
          languages: _languages,
          onLanguagesChanged: (v) => setState(() => _languages = v),
          certifications: _certifications,
          onCertificationsChanged: (v) => setState(() => _certifications = v),
          achievements: _achievements,
          onAchievementsChanged: (v) => setState(() => _achievements = v),
        ),
      _Step.review => _ReviewStep(
          roleLabel: _effectiveRoleLabel,
          summaryController: _summaryController,
          input: _buildInput(),
          isGenerating: _isGenerating,
          generateError: _generateError,
        ),
    };
  }
}

/// Tappable progress bar naming every step - mirrors
/// `resume_editor_screen.dart`'s `_WizardStepBar` (R-7) exactly, scoped to
/// this screen's own, shorter step list.
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
                  key: ValueKey('beginnerResumeStep_${steps[index].name}'),
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
      // No "Step X of Y" label here (unlike a plain text row that would
      // fight the buttons for space on a narrow phone) - the step bar
      // above already shows progress via its chips + linear indicator, so
      // repeating it here would only risk overflow on a ~360-412dp screen
      // for zero added information.
      child: Row(
        children: [
          TextButton(
            onPressed: isBusy ? null : onBack,
            child: const Text('Back'),
          ),
          const Spacer(),
          // `Flexible` (not a bare `FilledButton.icon`) so "Generate resume"
          // ellipsizes rather than overflows the row on a narrow (~360dp)
          // phone - the widest label this button ever shows.
          Flexible(
            child: FilledButton.icon(
              key: const Key('beginnerResumeNextButton'),
              onPressed: (canGoNext && !isBusy) ? onNext : null,
              icon: isBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(isLast ? Icons.auto_awesome_rounded : Icons.chevron_right_rounded),
              label: Text(
                isBusy ? 'Generating…' : (isLast ? 'Generate resume' : 'Next'),
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
        Text(
          "Let's start with the basics.",
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
          key: const Key('beginnerNameField'),
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

class _RoleStep extends ConsumerWidget {
  const _RoleStep({
    required this.mode,
    required this.onModeChanged,
    required this.searchController,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.jdPasteController,
    required this.onChanged,
  });

  final _RoleInputMode mode;
  final ValueChanged<_RoleInputMode> onModeChanged;
  final TextEditingController searchController;
  final RoleCategory? selectedCategory;
  final ValueChanged<RoleCategory> onCategorySelected;
  final TextEditingController jdPasteController;
  final VoidCallback onChanged;

  Future<void> _useJdText(WidgetRef ref) async {
    final text = jdPasteController.text;
    if (text.trim().isEmpty) return;
    if (looksLikeJobTitle(text)) {
      // R-10 §3: a short pasted title never goes through the full JD
      // parser - the deterministic role matcher handles it directly, same
      // as picking a role from the list.
      onCategorySelected(const RoleCategoryMatcher().match(text));
      onModeChanged(_RoleInputMode.pickList);
      searchController.text = text.trim();
      return;
    }
    ref.read(jdImportControllerProvider.notifier).parseText(text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What role are you targeting?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<_RoleInputMode>(
          segments: const [
            ButtonSegment(value: _RoleInputMode.pickList, label: Text('I know the job role')),
            ButtonSegment(value: _RoleInputMode.jd, label: Text('I have the Job Description')),
          ],
          selected: {mode},
          onSelectionChanged: (selection) => onModeChanged(selection.first),
        ),
        const SizedBox(height: 16),
        if (mode == _RoleInputMode.pickList)
          _RolePicker(
            searchController: searchController,
            selectedCategory: selectedCategory,
            onCategorySelected: (category) {
              onCategorySelected(category);
              searchController.text = category.displayName;
              onChanged();
            },
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste the job description, or import a file. A short job '
                'title works too.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('beginnerJdPasteField'),
                controller: jdPasteController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Paste a job description or a job title, e.g. "Sales Executive"…',
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
                    key: const Key('beginnerJdUseTextButton'),
                    onPressed: () => _useJdText(ref),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Use this'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('beginnerJdImportButton'),
                    onPressed: () => ref.read(jdImportControllerProvider.notifier).pickAndParse(),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Import a file'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _JdStatus(),
            ],
          ),
      ],
    );
  }
}

/// Shows the shared `jdImportControllerProvider`'s current state - kept
/// visible, never hidden elsewhere on screen (R-10 §3/§12: "Show the JD
/// clearly on screen after it is added... Do not hide the JD somewhere
/// else").
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
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer,
                        ),
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
                    '${draft.requirements.length} requirement(s) detected - this will be used '
                    'to tailor suggestions after your resume is created.',
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

class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.searchController,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final TextEditingController searchController;
  final RoleCategory? selectedCategory;
  final ValueChanged<RoleCategory> onCategorySelected;

  List<RoleCategory> _filtered() {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) return RoleCategoryCatalog.all;
    return RoleCategoryCatalog.all
        .where((c) =>
            c.displayName.toLowerCase().contains(query) ||
            c.aliases.any((a) => a.contains(query)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('beginnerRoleSearchField'),
          controller: searchController,
          decoration: const InputDecoration(
            labelText: 'Search a role',
            hintText: 'e.g. "sales", "data entry", "customer support"',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        // Rebuilds the filtered chip list on every keystroke without the
        // parent needing to own the search text in its own State - a
        // `TextEditingController` is itself a `Listenable`.
        ListenableBuilder(
          listenable: searchController,
          builder: (context, _) {
            final results = _filtered();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      "Couldn't find that role - you can still continue with "
                      '"General Fresher" and adjust skills yourself.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in results)
                      ChoiceChip(
                        key: ValueKey('beginnerRoleOption_${category.id}'),
                        label: Text(category.displayName),
                        selected: selectedCategory?.id == category.id,
                        onSelected: (_) => onCategorySelected(category),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
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
          'e.g. BA, B.Com, B.Sc, BBA, MBA. Leave blank to skip this section entirely.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('beginnerDegreeField'),
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
          'Internship, part-time work, volunteering, or a previous job - '
          "if you don't have any, skip this and move on. Nothing here is "
          'invented for you.',
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
          key: const Key('beginnerAddExperienceButton'),
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
              decoration: const InputDecoration(
                labelText: 'When',
                hintText: 'e.g. Summer 2023',
                isDense: true,
              ),
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

class _SkillsStep extends StatelessWidget {
  const _SkillsStep({
    required this.roleCategory,
    required this.removedSuggestedSkills,
    required this.onSuggestedSkillToggled,
    required this.ownSkillController,
    required this.ownSkills,
    required this.onOwnSkillsChanged,
  });

  final RoleCategory roleCategory;
  final Set<String> removedSuggestedSkills;
  final void Function(String name, bool keep) onSuggestedSkillToggled;
  final TextEditingController ownSkillController;
  final List<String> ownSkills;
  final ValueChanged<List<String>> onOwnSkillsChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Skills', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const SectionHeading('Your own skills', dense: true),
        const SizedBox(height: 8),
        _ChipListEditor(
          key: const Key('beginnerOwnSkillsEditor'),
          hintText: 'Type a skill and add it',
          items: ownSkills,
          onChanged: onOwnSkillsChanged,
        ),
        const SizedBox(height: 20),
        SectionHeading('Suggested for ${roleCategory.displayName}', dense: true),
        const SizedBox(height: 4),
        Text(
          "These are common for this role - only kept ones are added to "
          "your resume. Remove anything that doesn't apply to you.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in roleCategory.suggestedSkills)
              FilterChip(
                key: ValueKey('beginnerSuggestedSkill_${suggestion.name}'),
                label: Text(suggestion.name),
                selected: !removedSuggestedSkills.contains(suggestion.name),
                onSelected: (keep) => onSuggestedSkillToggled(suggestion.name, keep),
              ),
          ],
        ),
      ],
    );
  }
}

/// A small "type text, tap add, see a removable chip" editor - shared shape
/// for own-skills/languages/certifications/achievements, so this pattern
/// exists once instead of four times.
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
            IconButton.filledTonal(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add',
            ),
          ],
        ),
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in widget.items)
                Chip(label: Text(item), onDeleted: () => _remove(item)),
            ],
          ),
        ],
      ],
    );
  }
}

class _OptionalListsStep extends StatelessWidget {
  const _OptionalListsStep({
    required this.languages,
    required this.onLanguagesChanged,
    required this.certifications,
    required this.onCertificationsChanged,
    required this.achievements,
    required this.onAchievementsChanged,
  });

  final List<String> languages;
  final ValueChanged<List<String>> onLanguagesChanged;
  final List<String> certifications;
  final ValueChanged<List<String>> onCertificationsChanged;
  final List<String> achievements;
  final ValueChanged<List<String>> onAchievementsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('A few more optional details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        const SectionHeading('Languages', dense: true),
        const SizedBox(height: 8),
        _ChipListEditor(
          key: const Key('beginnerLanguagesEditor'),
          hintText: 'e.g. English, Hindi',
          items: languages,
          onChanged: onLanguagesChanged,
        ),
        const SizedBox(height: 20),
        const SectionHeading('Certifications', dense: true),
        const SizedBox(height: 8),
        _ChipListEditor(
          key: const Key('beginnerCertificationsEditor'),
          hintText: 'e.g. Tally Certification',
          items: certifications,
          onChanged: onCertificationsChanged,
        ),
        const SizedBox(height: 20),
        const SectionHeading('Achievements', dense: true),
        const SizedBox(height: 8),
        _ChipListEditor(
          key: const Key('beginnerAchievementsEditor'),
          hintText: 'e.g. College quiz winner',
          items: achievements,
          onChanged: onAchievementsChanged,
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.roleLabel,
    required this.summaryController,
    required this.input,
    required this.isGenerating,
    required this.generateError,
  });

  final String roleLabel;
  final TextEditingController summaryController;
  final BeginnerResumeInput input;
  final bool isGenerating;
  final String? generateError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review your resume', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Everything below is exactly what will be added - nothing else. '
          'You can still edit anything after this.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _ReviewRow(label: 'Name', value: input.fullName.isEmpty ? '—' : input.fullName),
        _ReviewRow(label: 'Target role', value: roleLabel),
        _ReviewRow(
          label: 'Education',
          value: (input.degree == null || input.degree!.trim().isEmpty)
              ? 'Not provided - section will be skipped'
              : input.degree!,
        ),
        _ReviewRow(
          label: 'Experience',
          value: input.experienceEntries.where((e) => !e.isBlank).isEmpty
              ? 'None provided - section will be skipped'
              : '${input.experienceEntries.where((e) => !e.isBlank).length} entr(y/ies)',
        ),
        _ReviewRow(
          label: 'Skills',
          value: input.confirmedSkills.isEmpty
              ? 'None selected'
              : input.confirmedSkills.map((s) => s.name).join(', '),
        ),
        const SizedBox(height: 16),
        const SectionHeading('Professional summary', dense: true),
        const SizedBox(height: 4),
        Text(
          'Generated from what you provided above - edit freely, or tap '
          '"Improve with AI" for an optional rewrite.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        BulletSuggestionField(
          controller: summaryController,
          entryContextLabel: '$roleLabel resume summary',
          labelText: 'Summary',
          helperText: null,
        ),
        const SizedBox(height: 4),
        const AiDisclaimer(
          text: 'AI can make mistakes. Review and verify all generated content before using your resume.',
        ),
        if (generateError != null) ...[
          const SizedBox(height: 16),
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(generateError!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ),
        ],
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
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
