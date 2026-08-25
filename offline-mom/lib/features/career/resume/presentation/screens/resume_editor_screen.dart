import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/custom_section_block.dart';
import '../../../../../models/resume_block_ref.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../models/skill_entry.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/resume/resume_text_export_service.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/text_input_dialog.dart';
import '../../delete_library_block_use_case.dart';
import '../providers/resume_block_library_providers.dart';
import '../providers/resume_editor_providers.dart';
import '../providers/resume_suggestion_providers.dart';
import '../providers/skill_entry_providers.dart';

enum _ResumeExportFormat { text, markdown }

/// Physical-Mobile-First Validation phase: the AppBar previously carried 6
/// separate action widgets (Suggestions/Versions/Choose Template/Preview/
/// Export/Save) plus the back button - on a ~360dp phone that left almost
/// no room for the resume title, which read as squeezed/near-illegible.
/// The 4 secondary actions collapse into [_EditorOverflowMenu]'s single
/// "more" menu; only "Choose a template" (this app's own current flagship
/// action) and "Preview" (the natural next step after editing) stay
/// visible as their own icons.
enum _ResumeMenuAction { suggestions, versions, exportText, exportMarkdown, saveVersion }

const _resumeTextExportService = ResumeTextExportService();

/// Builds and edits one Resume's live composition: Profile fields, and
/// every attached block section (Experience/Education/Project/
/// Certification/Skill) with attach/detach/reorder. "Save version" freezes
/// the current draft into a new [ResumeVersion]; "Preview" compiles that
/// same current draft directly, without saving anything - see
/// [ResumeEditorController]'s own doc comment for why those are two
/// independent actions.
class ResumeEditorScreen extends ConsumerWidget {
  const ResumeEditorScreen({super.key, required this.resumeId});

  final int resumeId;

  Future<void> _saveVersion(BuildContext context, WidgetRef ref) async {
    final label = await showTextInputDialog(
      context,
      title: 'Save version',
      labelText: 'Version label',
      helperText: 'e.g. "v1" or "Applied to Acme Corp"',
      confirmLabel: 'Save',
    );
    if (label == null || label.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(resumeEditorControllerProvider(resumeId).notifier).saveVersion(label);
      messenger.showSnackBar(const SnackBar(content: Text('Version saved.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  /// Shares the *current, unsaved* draft as plain text or Markdown - built
  /// from the same live-draft compile [ResumeEditorController.preview]
  /// itself uses (`compileSnapshot()`), never a saved [ResumeVersion] and
  /// never a fresh database read. Shares the text directly via `share_plus`
  /// rather than writing a file first - mirrors `ChatScreen._exportChat`'s
  /// exact TXT/Markdown handling
  /// (lib/features/chat/presentation/screens/chat_screen.dart), the one
  /// precedent this codebase already has for this export shape.
  Future<void> _exportResumeText(
    BuildContext context,
    WidgetRef ref,
    String resumeTitle,
    _ResumeExportFormat format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final snapshot =
          await ref.read(resumeEditorControllerProvider(resumeId).notifier).compileSnapshot();
      final text = format == _ResumeExportFormat.text
          ? _resumeTextExportService.buildPlainText(snapshot)
          : _resumeTextExportService.buildMarkdown(snapshot);
      await SharePlus.instance.share(ShareParams(text: text, subject: resumeTitle));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(resumeEditorControllerProvider(resumeId));

    return Scaffold(
      appBar: AppBar(
        title: Text(state is ResumeEditorReady ? state.resume.title : 'Resume'),
        actions: state is ResumeEditorReady
            ? [
                IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: 'Choose a template',
                  onPressed: () => context.push(RoutePaths.resumeTemplatesPath(resumeId)),
                ),
                IconButton(
                  icon: const Icon(Icons.visibility_outlined),
                  tooltip: 'Preview',
                  onPressed: () => context.push(RoutePaths.resumePreviewPath(resumeId)),
                ),
                _EditorOverflowMenu(
                  resumeId: resumeId,
                  isSaving: state.isSaving,
                  onSaveVersion: () => _saveVersion(context, ref),
                  onExport: (format) => _exportResumeText(context, ref, state.resume.title, format),
                ),
              ]
            : null,
      ),
      body: switch (state) {
        ResumeEditorLoading() => const Center(child: CircularProgressIndicator()),
        ResumeEditorLoadError(:final message) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: "Couldn't load this resume",
            message: message,
          ),
        ResumeEditorReady() => _EditorBody(resumeId: resumeId, state: state),
      },
    );
  }
}

/// One entry in the progressive wizard (R-7 §2) - each step isolates one
/// existing section widget so a first-time user fills the resume in
/// logical, one-at-a-time chunks instead of scrolling one long form. Every
/// field from the original single-scroll layout is still here - this only
/// changes how many are visible at once, never what's collected. The final
/// "Review" step deliberately renders every section together (the old
/// full-scroll layout, verbatim) as a last look before saving/exporting.
enum _WizardStep {
  profile('Profile', Icons.person_outline_rounded),
  experience('Experience', Icons.work_outline_rounded),
  education('Education', Icons.school_outlined),
  projects('Projects', Icons.folder_outlined),
  certifications('Certifications', Icons.verified_outlined),
  skills('Skills', Icons.star_outline_rounded),
  custom('Custom', Icons.notes_rounded),
  review('Review', Icons.checklist_rounded);

  const _WizardStep(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _EditorBody extends ConsumerStatefulWidget {
  const _EditorBody({required this.resumeId, required this.state});

  final int resumeId;
  final ResumeEditorReady state;

  @override
  ConsumerState<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends ConsumerState<_EditorBody> {
  int _step = 0;

  void _goTo(int step) => setState(() => _step = step.clamp(0, _WizardStep.values.length - 1));

  @override
  Widget build(BuildContext context) {
    final resumeId = widget.resumeId;
    final state = widget.state;
    final step = _WizardStep.values[_step];

    Widget stepContent() {
      return switch (step) {
        _WizardStep.profile => _ProfileCard(resumeId: resumeId, state: state),
        _WizardStep.experience =>
          _ExperienceSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.experience)),
        _WizardStep.education =>
          _EducationSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.education)),
        _WizardStep.projects =>
          _ProjectSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.project)),
        _WizardStep.certifications => _CertificationSection(
            resumeId: resumeId,
            refs: state.refsOf(ResumeBlockType.certification),
          ),
        _WizardStep.skills =>
          _SkillSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.skill)),
        _WizardStep.custom => _CustomSectionSection(
            resumeId: resumeId,
            refs: state.refsOf(ResumeBlockType.customSection),
          ),
        // Review: every section together, exactly like the pre-wizard
        // single-scroll layout - a deliberate final look at the whole
        // resume, not a ninth kind of content.
        _WizardStep.review => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileCard(resumeId: resumeId, state: state),
              const SizedBox(height: 20),
              _ExperienceSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.experience)),
              const SizedBox(height: 20),
              _EducationSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.education)),
              const SizedBox(height: 20),
              _ProjectSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.project)),
              const SizedBox(height: 20),
              _CertificationSection(
                resumeId: resumeId,
                refs: state.refsOf(ResumeBlockType.certification),
              ),
              const SizedBox(height: 20),
              _SkillSection(resumeId: resumeId, refs: state.refsOf(ResumeBlockType.skill)),
              const SizedBox(height: 20),
              _CustomSectionSection(
                resumeId: resumeId,
                refs: state.refsOf(ResumeBlockType.customSection),
              ),
            ],
          ),
      };
    }

    return Column(
      children: [
        _WizardStepBar(current: _step, onStepTapped: _goTo),
        if (state.actionError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.actionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            key: ValueKey(_step),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [stepContent()],
          ),
        ),
        _WizardNavBar(
          step: step,
          stepIndex: _step,
          totalSteps: _WizardStep.values.length,
          onBack: _step > 0 ? () => _goTo(_step - 1) : null,
          onNext: _step < _WizardStep.values.length - 1 ? () => _goTo(_step + 1) : null,
        ),
      ],
    );
  }
}

/// A tappable row naming every step and highlighting the current one -
/// R-7 §2's "clearly show progress". Tapping any step jumps straight to it
/// (useful once a resume already exists and the user is editing one
/// section, not filling the whole thing in order again).
class _WizardStepBar extends StatelessWidget {
  const _WizardStepBar({required this.current, required this.onStepTapped});

  final int current;
  final void Function(int step) onStepTapped;

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
              itemCount: _WizardStep.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final step = _WizardStep.values[index];
                final isCurrent = index == current;
                return ChoiceChip(
                  key: ValueKey('resumeWizardStep_${step.name}'),
                  avatar: Icon(step.icon, size: 16),
                  label: Text(step.label),
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
              child: LinearProgressIndicator(
                value: (current + 1) / _WizardStep.values.length,
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Back/Next controls plus a "Step X of N" label - the resume itself is
/// already saved field-by-field as the user edits (same live-persist
/// behavior every section here already had), so moving between steps or
/// leaving the screen entirely never loses anything; this bar is purely
/// navigation, not a gate on saving.
class _WizardNavBar extends StatelessWidget {
  const _WizardNavBar({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onBack,
    required this.onNext,
  });

  final _WizardStep step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

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
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Back'),
          ),
          const Spacer(),
          Text(
            'Step ${stepIndex + 1} of $totalSteps · ${step.label}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (onNext != null)
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
              label: Text(stepIndex == totalSteps - 2 ? 'Review' : 'Next'),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text('All set', style: TextStyle(color: scheme.primary)),
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAddExisting, required this.onCreateNew});

  final String title;
  final VoidCallback onAddExisting;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        PopupMenuButton<void>(
          icon: const Icon(Icons.add_circle_outline_rounded),
          tooltip: 'Add',
          itemBuilder: (context) => [
            PopupMenuItem(onTap: onAddExisting, child: const Text('Add existing')),
            PopupMenuItem(onTap: onCreateNew, child: const Text('Create new')),
          ],
        ),
      ],
    );
  }
}

Future<void> _handleBlockAction(
  BuildContext context,
  WidgetRef ref, {
  required int resumeId,
  required ResumeBlockType blockType,
  required int blockId,
  required String action,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(resumeEditorControllerProvider(resumeId).notifier);

  switch (action) {
    case 'remove':
      // Physical-Mobile-First Validation phase: previously unguarded -
      // a thrown exception here surfaced as an unhandled Future rejection
      // from a PopupMenuItem.onSelected callback, so the menu just closed
      // with no visible feedback and no way to tell "remove" had silently
      // failed. Same shape as the 'delete' branch's own existing
      // try/catch below.
      try {
        await notifier.detachBlock(blockType, blockId);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    case 'delete':
      final confirmed = await showDestructiveConfirmDialog(
        context,
        title: 'Delete from library?',
        message: 'This permanently deletes the block for every resume that '
            'uses it. Detach it from every resume first if it\'s still in '
            'use.',
      );
      if (!confirmed) return;
      try {
        await notifier.deleteBlockFromLibrary(blockType, blockId);
        messenger.showSnackBar(const SnackBar(content: Text('Deleted from library.')));
      } on BlockInUseException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
  }
}

Future<void> _editBullets(
  BuildContext context,
  WidgetRef ref, {
  required int resumeId,
  required ResumeBlockType blockType,
  required int blockId,
  required List<String> currentBullets,
}) async {
  final controller = TextEditingController(text: currentBullets.join('\n'));
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Customize for this resume'),
      content: TextField(
        controller: controller,
        maxLines: 8,
        minLines: 4,
        decoration: const InputDecoration(
          labelText: 'One bullet per line',
          helperText: 'Only affects this resume - the shared block is unchanged.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(''),
          child: const Text('Reset to original'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null || !context.mounted) return;

  // Physical-Mobile-First Validation phase: previously unguarded - a
  // failed save here (locked DB, disk error) closed the dialog with the
  // edit discarded and no visible sign anything went wrong.
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(resumeEditorControllerProvider(resumeId).notifier);
  try {
    if (result.trim().isEmpty) {
      await notifier.setBlockOverride(blockType, blockId, null);
      return;
    }
    final bullets = result.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    await notifier.setBlockOverride(blockType, blockId, bullets);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({required this.resumeId, required this.state});

  final int resumeId;
  final ResumeEditorReady state;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final TextEditingController _title;
  late final TextEditingController _targetRole;
  late final TextEditingController _fullName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _location;

  @override
  void initState() {
    super.initState();
    final resume = widget.state.resume;
    _title = TextEditingController(text: resume.title);
    _targetRole = TextEditingController(text: resume.targetRole ?? '');
    _fullName = TextEditingController(text: resume.fullName);
    _email = TextEditingController(text: resume.email ?? '');
    _phone = TextEditingController(text: resume.phone ?? '');
    _location = TextEditingController(text: resume.location ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _targetRole.dispose();
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Resume title')),
            const SizedBox(height: 12),
            TextField(
              controller: _targetRole,
              decoration: const InputDecoration(
                labelText: 'Target role',
                helperText: 'e.g. "Senior Backend Engineer" - used later to tailor this resume to a job description.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _fullName, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 12),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: widget.state.isSaving
                    ? null
                    : () {
                        ref
                            .read(resumeEditorControllerProvider(widget.resumeId).notifier)
                            .updateProfile(
                              title: _title.text.trim(),
                              targetRole: _targetRole.text.trim().isEmpty ? null : _targetRole.text.trim(),
                              fullName: _fullName.text.trim(),
                              email: _email.text.trim().isEmpty ? null : _email.text.trim(),
                              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                              location: _location.text.trim().isEmpty ? null : _location.text.trim(),
                              links: widget.state.resume.links,
                            );
                      },
                child: const Text('Save profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExperienceSection extends ConsumerWidget {
  const _ExperienceSection({required this.resumeId, required this.refs});

  final int resumeId;
  final List<ResumeBlockRef> refs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(experienceBlockListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Experience',
          onAddExisting: () => _pickExisting(
            context,
            ref,
            title: 'Add experience',
            options: libraryAsync.valueOrNull ?? const [],
            alreadyAttached: refs.map((r) => r.blockId).toSet(),
            labelOf: (b) => '${b.role} - ${b.company}',
            idOf: (b) => b.id!,
            onPicked: (id) => ref
                .read(resumeEditorControllerProvider(resumeId).notifier)
                .attachBlock(ResumeBlockType.experience, id),
          ),
          onCreateNew: () => context.push(RoutePaths.resumeExperienceBlockNewPath(resumeId)),
        ),
        const SizedBox(height: 8),
        if (refs.isEmpty)
          const _EmptySectionHint(message: 'No experience added yet.')
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...refs];
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              ref.read(resumeEditorControllerProvider(resumeId).notifier).reorderSection(reordered);
            },
            children: [
              for (final blockRef in refs)
                Consumer(
                  key: ValueKey('experience-${blockRef.id}'),
                  builder: (context, ref, _) {
                    final blockAsync = ref.watch(experienceBlockByIdProvider(blockRef.blockId));
                    return blockAsync.when(
                      loading: () => const ListTile(title: Text('Loading...')),
                      error: (e, _) => ListTile(title: Text(friendlyErrorMessage(e))),
                      data: (block) {
                        if (block == null) return const ListTile(title: Text('Block not found'));
                        return ListTile(
                          title: Text('${block.role} - ${block.company}'),
                          subtitle: Text(
                            '${block.startDate} - ${block.endDate ?? 'Present'}'
                            '${blockRef.overrideJson != null ? ' - customized for this resume' : ''}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'customize') {
                                _editBullets(
                                  context,
                                  ref,
                                  resumeId: resumeId,
                                  blockType: ResumeBlockType.experience,
                                  blockId: block.id!,
                                  currentBullets: blockRef.overrideJson != null
                                      ? _decodeOverride(blockRef.overrideJson!) ?? block.bullets
                                      : block.bullets,
                                );
                              } else if (action == 'edit') {
                                context.push(RoutePaths.resumeExperienceBlockEditPath(resumeId, block.id!));
                              } else {
                                _handleBlockAction(
                                  context,
                                  ref,
                                  resumeId: resumeId,
                                  blockType: ResumeBlockType.experience,
                                  blockId: block.id!,
                                  action: action,
                                );
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'customize', child: Text('Customize for this resume')),
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'remove', child: Text('Remove from resume')),
                              PopupMenuItem(value: 'delete', child: Text('Delete from library')),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _EducationSection extends ConsumerWidget {
  const _EducationSection({required this.resumeId, required this.refs});

  final int resumeId;
  final List<ResumeBlockRef> refs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(educationBlockListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Education',
          onAddExisting: () => _pickExisting(
            context,
            ref,
            title: 'Add education',
            options: libraryAsync.valueOrNull ?? const [],
            alreadyAttached: refs.map((r) => r.blockId).toSet(),
            labelOf: (b) => '${b.degree} - ${b.institution}',
            idOf: (b) => b.id!,
            onPicked: (id) => ref
                .read(resumeEditorControllerProvider(resumeId).notifier)
                .attachBlock(ResumeBlockType.education, id),
          ),
          onCreateNew: () => context.push(RoutePaths.resumeEducationBlockNewPath(resumeId)),
        ),
        const SizedBox(height: 8),
        if (refs.isEmpty)
          const _EmptySectionHint(message: 'No education added yet.')
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...refs];
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              ref.read(resumeEditorControllerProvider(resumeId).notifier).reorderSection(reordered);
            },
            children: [
              for (final blockRef in refs)
                Consumer(
                  key: ValueKey('education-${blockRef.id}'),
                  builder: (context, ref, _) {
                    final blockAsync = ref.watch(educationBlockByIdProvider(blockRef.blockId));
                    return blockAsync.when(
                      loading: () => const ListTile(title: Text('Loading...')),
                      error: (e, _) => ListTile(title: Text(friendlyErrorMessage(e))),
                      data: (block) {
                        if (block == null) return const ListTile(title: Text('Block not found'));
                        return ListTile(
                          title: Text('${block.degree} - ${block.institution}'),
                          subtitle: Text(
                            '${block.startDate} - ${block.endDate ?? 'Present'}'
                            '${blockRef.overrideJson != null ? ' - customized for this resume' : ''}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'customize') {
                                _editBullets(
                                  context,
                                  ref,
                                  resumeId: resumeId,
                                  blockType: ResumeBlockType.education,
                                  blockId: block.id!,
                                  currentBullets: blockRef.overrideJson != null
                                      ? _decodeOverride(blockRef.overrideJson!) ?? block.details
                                      : block.details,
                                );
                              } else if (action == 'edit') {
                                context.push(RoutePaths.resumeEducationBlockEditPath(resumeId, block.id!));
                              } else {
                                _handleBlockAction(
                                  context,
                                  ref,
                                  resumeId: resumeId,
                                  blockType: ResumeBlockType.education,
                                  blockId: block.id!,
                                  action: action,
                                );
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'customize', child: Text('Customize for this resume')),
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'remove', child: Text('Remove from resume')),
                              PopupMenuItem(value: 'delete', child: Text('Delete from library')),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _ProjectSection extends ConsumerWidget {
  const _ProjectSection({required this.resumeId, required this.refs});

  final int resumeId;
  final List<ResumeBlockRef> refs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(projectBlockListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Projects',
          onAddExisting: () => _pickExisting(
            context,
            ref,
            title: 'Add project',
            options: libraryAsync.valueOrNull ?? const [],
            alreadyAttached: refs.map((r) => r.blockId).toSet(),
            labelOf: (b) => b.name,
            idOf: (b) => b.id!,
            onPicked: (id) => ref
                .read(resumeEditorControllerProvider(resumeId).notifier)
                .attachBlock(ResumeBlockType.project, id),
          ),
          onCreateNew: () => context.push(RoutePaths.resumeProjectBlockNewPath(resumeId)),
        ),
        const SizedBox(height: 8),
        if (refs.isEmpty)
          const _EmptySectionHint(message: 'No projects added yet.')
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...refs];
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              ref.read(resumeEditorControllerProvider(resumeId).notifier).reorderSection(reordered);
            },
            children: [
              for (final blockRef in refs)
                Consumer(
                  key: ValueKey('project-${blockRef.id}'),
                  builder: (context, ref, _) {
                    final blockAsync = ref.watch(projectBlockByIdProvider(blockRef.blockId));
                    return blockAsync.when(
                      loading: () => const ListTile(title: Text('Loading...')),
                      error: (e, _) => ListTile(title: Text(friendlyErrorMessage(e))),
                      data: (block) {
                        if (block == null) return const ListTile(title: Text('Block not found'));
                        return ListTile(
                          title: Text(block.name),
                          subtitle: Text(
                            blockRef.overrideJson != null ? 'Customized for this resume' : (block.link ?? ''),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'customize') {
                                _editBullets(
                                  context,
                                  ref,
                                  resumeId: resumeId,
                                  blockType: ResumeBlockType.project,
                                  blockId: block.id!,
                                  currentBullets: blockRef.overrideJson != null
                                      ? _decodeOverride(blockRef.overrideJson!) ?? block.bullets
                                      : block.bullets,
                                );
                              } else if (action == 'edit') {
                                context.push(RoutePaths.resumeProjectBlockEditPath(resumeId, block.id!));
                              } else {
                                _handleBlockAction(
                                  context,
                                  ref,
                                  resumeId: resumeId,
                                  blockType: ResumeBlockType.project,
                                  blockId: block.id!,
                                  action: action,
                                );
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'customize', child: Text('Customize for this resume')),
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'remove', child: Text('Remove from resume')),
                              PopupMenuItem(value: 'delete', child: Text('Delete from library')),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _CertificationSection extends ConsumerWidget {
  const _CertificationSection({required this.resumeId, required this.refs});

  final int resumeId;
  final List<ResumeBlockRef> refs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(certificationBlockListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Certifications',
          onAddExisting: () => _pickExisting(
            context,
            ref,
            title: 'Add certification',
            options: libraryAsync.valueOrNull ?? const [],
            alreadyAttached: refs.map((r) => r.blockId).toSet(),
            labelOf: (b) => '${b.name} - ${b.issuer}',
            idOf: (b) => b.id!,
            onPicked: (id) => ref
                .read(resumeEditorControllerProvider(resumeId).notifier)
                .attachBlock(ResumeBlockType.certification, id),
          ),
          onCreateNew: () => context.push(RoutePaths.resumeCertificationBlockNewPath(resumeId)),
        ),
        const SizedBox(height: 8),
        if (refs.isEmpty)
          const _EmptySectionHint(message: 'No certifications added yet.')
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...refs];
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              ref.read(resumeEditorControllerProvider(resumeId).notifier).reorderSection(reordered);
            },
            children: [
              for (final blockRef in refs)
                Consumer(
                  key: ValueKey('certification-${blockRef.id}'),
                  builder: (context, ref, _) {
                    final blockAsync = ref.watch(certificationBlockByIdProvider(blockRef.blockId));
                    return blockAsync.when(
                      loading: () => const ListTile(title: Text('Loading...')),
                      error: (e, _) => ListTile(title: Text(friendlyErrorMessage(e))),
                      data: (block) {
                        if (block == null) return const ListTile(title: Text('Block not found'));
                        return ListTile(
                          title: Text(block.name),
                          subtitle: Text(block.issuer),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                context.push(RoutePaths.resumeCertificationBlockEditPath(resumeId, block.id!));
                              } else {
                                _handleBlockAction(
                                  context,
                                  ref,
                                  resumeId: resumeId,
                                  blockType: ResumeBlockType.certification,
                                  blockId: block.id!,
                                  action: action,
                                );
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'remove', child: Text('Remove from resume')),
                              PopupMenuItem(value: 'delete', child: Text('Delete from library')),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _SkillSection extends ConsumerWidget {
  const _SkillSection({required this.resumeId, required this.refs});

  final int resumeId;
  final List<ResumeBlockRef> refs;

  Future<void> _createSkill(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    var category = SkillCategory.technical;
    final result = await showDialog<(String, SkillCategory)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('New skill'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Skill name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SkillCategory>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: SkillCategory.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (value) => setState(() => category = value ?? category),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop((nameController.text.trim(), category)),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.$1.isEmpty || !context.mounted) return;

    // Beta blocker fix: this insert previously had no error handling at
    // all - a thrown exception here (locked DB, disk error, concurrent
    // write) surfaced as an unhandled Future rejection from a
    // PopupMenuItem.onTap callback, so the dialog just closed with no
    // visible feedback and no way to tell "add skill" had silently failed
    // (docs/v3/implementation/03-decisions.md). Mirrors
    // ResumeEditorScreen._saveVersion's own try/catch + snackbar shape.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ref.read(skillEntryRepositoryProvider).insert(
            SkillEntry(id: null, name: result.$1, category: result.$2, createdAt: DateTime.now()),
          );
      ref.invalidate(skillEntryListProvider);
      await ref
          .read(resumeEditorControllerProvider(resumeId).notifier)
          .attachBlock(ResumeBlockType.skill, id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _addExistingSkill(BuildContext context, WidgetRef ref, List<SkillEntry> all) async {
    final attachedIds = refs.map((r) => r.blockId).toSet();
    final available = all.where((s) => !attachedIds.contains(s.id)).toList();
    final picked = await showDialog<SkillEntry>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Add existing skill'),
        children: [
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Every skill in your library is already on this resume.'),
            ),
          for (final skill in available)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(skill),
              child: Text('${skill.name} (${skill.category.name})'),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;

    // Physical-Mobile-First Validation phase: previously unguarded - see
    // _createSkill's own "Beta blocker fix" comment above, which this
    // sibling flow had been missed by.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(resumeEditorControllerProvider(resumeId).notifier)
          .attachBlock(ResumeBlockType.skill, picked.id!);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(skillEntryListProvider);
    final library = {for (final s in libraryAsync.valueOrNull ?? const []) s.id: s};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Skills', style: Theme.of(context).textTheme.titleMedium)),
            PopupMenuButton<void>(
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'Add',
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: const Text('Add existing'),
                  onTap: () => _addExistingSkill(context, ref, libraryAsync.valueOrNull ?? const []),
                ),
                PopupMenuItem(
                  child: const Text('Create new'),
                  onTap: () => _createSkill(context, ref),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (refs.isEmpty)
          const _EmptySectionHint(message: 'No skills added yet.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final blockRef in refs)
                if (library[blockRef.blockId] != null)
                  InputChip(
                    label: Text(library[blockRef.blockId]!.name),
                    // Physical-Mobile-First Validation phase: previously
                    // unguarded - a failed detach here left the chip
                    // sitting there with no explanation of why it didn't
                    // disappear.
                    onDeleted: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref
                            .read(resumeEditorControllerProvider(resumeId).notifier)
                            .detachBlock(ResumeBlockType.skill, blockRef.blockId);
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                      }
                    },
                  ),
            ],
          ),
      ],
    );
  }
}

/// Generic/custom sections (beta data-fidelity requirement,
/// docs/v3/implementation/03-decisions.md) - a section this app has no
/// dedicated typed layout for (Awards, Publications, Volunteer Experience,
/// ...), most often arriving via import, but also directly creatable here
/// so a manually-built resume can carry one too. Deliberately the smallest
/// clean shape that prevents data loss: one dialog (title + one entry per
/// line) for both create and edit, no separate "add existing from
/// library" picker or dedicated block-editor route the way
/// Project/Certification have - a custom section's whole reason to exist
/// is that it's a one-off, not a reusable credential.
class _CustomSectionSection extends ConsumerWidget {
  const _CustomSectionSection({required this.resumeId, required this.refs});

  final int resumeId;
  final List<ResumeBlockRef> refs;

  Future<void> _createSection(BuildContext context, WidgetRef ref) async {
    final result = await _showCustomSectionDialog(context, title: 'New section');
    if (result == null || result.$1.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now();
      final id = await ref.read(customSectionBlockRepositoryProvider).insert(
            CustomSectionBlock(id: null, title: result.$1, entries: result.$2, createdAt: now, updatedAt: now),
          );
      ref.invalidate(customSectionBlockListProvider);
      await ref
          .read(resumeEditorControllerProvider(resumeId).notifier)
          .attachBlock(ResumeBlockType.customSection, id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _editSection(BuildContext context, WidgetRef ref, CustomSectionBlock block) async {
    final result = await _showCustomSectionDialog(
      context,
      title: 'Edit section',
      initialTitle: block.title,
      initialEntries: block.entries,
    );
    if (result == null || result.$1.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customSectionBlockRepositoryProvider).update(
            block.copyWith(title: result.$1, entries: result.$2, updatedAt: DateTime.now()),
          );
      ref.invalidate(customSectionBlockByIdProvider(block.id!));
      ref.invalidate(customSectionBlockListProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<(String, List<String>)?> _showCustomSectionDialog(
    BuildContext context, {
    required String title,
    String initialTitle = '',
    List<String> initialEntries = const [],
  }) {
    final titleController = TextEditingController(text: initialTitle);
    final entriesController = TextEditingController(text: initialEntries.join('\n'));
    return showDialog<(String, List<String>)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Section title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: entriesController,
              maxLines: 6,
              minLines: 3,
              decoration: const InputDecoration(
                labelText: 'One entry per line',
                helperText: 'e.g. an award, a publication, a language.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop((
              titleController.text.trim(),
              entriesController.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList(),
            )),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Additional sections', style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'Add section',
              onPressed: () => _createSection(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (refs.isEmpty)
          const _EmptySectionHint(
            message: 'No additional sections. Custom sections found while importing a '
                'resume (Awards, Publications, ...) also appear here.',
          )
        else
          for (final blockRef in refs)
            Consumer(
              key: ValueKey('custom-section-${blockRef.id}'),
              builder: (context, ref, _) {
                final blockAsync = ref.watch(customSectionBlockByIdProvider(blockRef.blockId));
                return blockAsync.when(
                  loading: () => const ListTile(title: Text('Loading...')),
                  error: (e, _) => ListTile(title: Text(friendlyErrorMessage(e))),
                  data: (block) {
                    if (block == null) return const ListTile(title: Text('Block not found'));
                    return ListTile(
                      title: Text(block.title),
                      subtitle: Text('${block.entries.length} ${block.entries.length == 1 ? 'entry' : 'entries'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') {
                            _editSection(context, ref, block);
                          } else {
                            _handleBlockAction(
                              context,
                              ref,
                              resumeId: resumeId,
                              blockType: ResumeBlockType.customSection,
                              blockId: block.id!,
                              action: action,
                            );
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'remove', child: Text('Remove from resume')),
                          PopupMenuItem(value: 'delete', child: Text('Delete from library')),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      ],
    );
  }
}

class _EmptySectionHint extends StatelessWidget {
  const _EmptySectionHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// Physical-Mobile-First Validation phase: consolidates the 4 secondary
/// editor actions (AI Suggestions, Versions, Export, Save version) into
/// one overflow menu, so the AppBar stops crowding out the resume title
/// on a narrow phone (see [_ResumeMenuAction]'s own doc comment). Still
/// badges the menu's own icon with the resume's pending-suggestion count
/// (the same signal `_SuggestionsAction` used to give directly) so "there
/// are suggestions waiting" stays visible without opening the menu, and
/// repeats the count in that item's own label once the menu is open -
/// never silent, never buried without a visible reason to look. Reads
/// [pendingSuggestionCountProvider] directly rather than threading the
/// count through [ResumeEditorController]'s own state, since the two
/// concerns (the live draft vs. how many AI suggestions are waiting) are
/// independent and don't need to share a controller.
class _EditorOverflowMenu extends ConsumerWidget {
  const _EditorOverflowMenu({
    required this.resumeId,
    required this.isSaving,
    required this.onSaveVersion,
    required this.onExport,
  });

  final int resumeId;
  final bool isSaving;
  final VoidCallback onSaveVersion;
  final void Function(_ResumeExportFormat format) onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(pendingSuggestionCountProvider(resumeId));
    final count = countAsync.valueOrNull ?? 0;

    return PopupMenuButton<_ResumeMenuAction>(
      tooltip: 'More',
      icon: Badge(
        label: Text('$count'),
        isLabelVisible: count > 0,
        child: const Icon(Icons.more_vert_rounded),
      ),
      onSelected: (action) {
        switch (action) {
          case _ResumeMenuAction.suggestions:
            context.push(RoutePaths.resumeSuggestionsPath(resumeId));
          case _ResumeMenuAction.versions:
            context.push(RoutePaths.resumeVersionsPath(resumeId));
          case _ResumeMenuAction.exportText:
            onExport(_ResumeExportFormat.text);
          case _ResumeMenuAction.exportMarkdown:
            onExport(_ResumeExportFormat.markdown);
          case _ResumeMenuAction.saveVersion:
            onSaveVersion();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ResumeMenuAction.suggestions,
          child: Text(count > 0 ? 'AI suggestions ($count)' : 'AI suggestions'),
        ),
        const PopupMenuItem(value: _ResumeMenuAction.versions, child: Text('Versions')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: _ResumeMenuAction.exportText, child: Text('Export as text')),
        const PopupMenuItem(value: _ResumeMenuAction.exportMarkdown, child: Text('Export as Markdown')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ResumeMenuAction.saveVersion,
          enabled: !isSaving,
          child: const Text('Save version'),
        ),
      ],
    );
  }
}

List<String>? _decodeOverride(String overrideJson) {
  try {
    final decoded = jsonDecode(overrideJson);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
  } catch (_) {
    // Malformed - fall back to the caller's own default (the library
    // block's original content), same safety fallback
    // `ResumeCompilerService._resolveStringListOverride` uses.
  }
  return null;
}

Future<void> _pickExisting<T>(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required List<T> options,
  required Set<int> alreadyAttached,
  required String Function(T) labelOf,
  required int Function(T) idOf,
  required Future<void> Function(int id) onPicked,
}) async {
  final available = options.where((o) => !alreadyAttached.contains(idOf(o))).toList();
  final picked = await showDialog<T>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(title),
      children: [
        if (available.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('Every block in your library is already on this resume.'),
          ),
        for (final option in available)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(option),
            child: Text(labelOf(option)),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;

  // Physical-Mobile-First Validation phase: previously `onPicked` was a
  // plain `void Function`, so its callers' actually-async attachBlock()
  // call had its returned Future silently discarded rather than awaited -
  // a failure surfaced as an unhandled Future rejection with no visible
  // feedback, for every one of Experience/Education/Project/Certification's
  // "add existing" flows (all four share this one helper).
  final messenger = ScaffoldMessenger.of(context);
  try {
    await onPicked(idOf(picked));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
  }
}
