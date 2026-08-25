import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/experience_block.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../delete_library_block_use_case.dart';
import '../providers/resume_block_library_providers.dart';
import '../providers/resume_editor_providers.dart';
import '../widgets/bullet_suggestion_field.dart';

/// Creates or edits one [ExperienceBlock] in the shared library. In create
/// mode ([blockId] null), saving inserts the block then attaches it to
/// [resumeId] via [ResumeEditorController.attachBlock]. In edit mode,
/// saving updates the library row directly - since a block is shared,
/// this affects every resume that references it, by design.
///
/// "Delete from library" is the *only* place this block can be deleted from
/// - it always calls [DeleteLibraryBlockUseCaseProvider] (never a direct
/// repository `delete()`), and is only ever shown in edit mode.
class ExperienceBlockEditorScreen extends ConsumerStatefulWidget {
  const ExperienceBlockEditorScreen({super.key, required this.resumeId, this.blockId});

  final int resumeId;
  final int? blockId;

  @override
  ConsumerState<ExperienceBlockEditorScreen> createState() => _ExperienceBlockEditorScreenState();
}

class _ExperienceBlockEditorScreenState extends ConsumerState<ExperienceBlockEditorScreen> {
  final _role = TextEditingController();
  final _company = TextEditingController();
  final _location = TextEditingController();
  final _startDate = TextEditingController();
  final _endDate = TextEditingController();
  final _bullets = TextEditingController();
  bool _seeded = false;
  bool _isSaving = false;
  // No dedicated UI yet to view/edit sub-projects here (Resume ->
  // Experience -> Project -> Project bullets architecture, migration v20) -
  // preserved as-is through save so editing an imported entry's role/
  // company/bullets never silently discards its nested sub-projects
  // (e.g. SciLab/ByHeart/Crossword under one role).
  List<ExperienceSubProject> _subProjects = const [];

  bool get _isCreate => widget.blockId == null;

  @override
  void dispose() {
    _role.dispose();
    _company.dispose();
    _location.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _bullets.dispose();
    super.dispose();
  }

  void _seed(ExperienceBlock block) {
    if (_seeded) return;
    _seeded = true;
    _role.text = block.role;
    _company.text = block.company;
    _location.text = block.location ?? '';
    _startDate.text = block.startDate;
    _endDate.text = block.endDate ?? '';
    _bullets.text = block.bullets.join('\n');
    _subProjects = block.subProjects;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final now = DateTime.now();
    final bullets =
        _bullets.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    try {
      if (_isCreate) {
        final id = await ref.read(experienceBlockRepositoryProvider).insert(ExperienceBlock(
              id: null,
              role: _role.text.trim(),
              company: _company.text.trim(),
              location: _location.text.trim().isEmpty ? null : _location.text.trim(),
              startDate: _startDate.text.trim(),
              endDate: _endDate.text.trim().isEmpty ? null : _endDate.text.trim(),
              bullets: bullets,
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(experienceBlockListProvider);
        await ref
            .read(resumeEditorControllerProvider(widget.resumeId).notifier)
            .attachBlock(ResumeBlockType.experience, id);
      } else {
        await ref.read(experienceBlockRepositoryProvider).update(ExperienceBlock(
              id: widget.blockId,
              role: _role.text.trim(),
              company: _company.text.trim(),
              location: _location.text.trim().isEmpty ? null : _location.text.trim(),
              startDate: _startDate.text.trim(),
              endDate: _endDate.text.trim().isEmpty ? null : _endDate.text.trim(),
              bullets: bullets,
              subProjects: _subProjects,
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(experienceBlockByIdProvider(widget.blockId!));
        ref.invalidate(experienceBlockListProvider);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _deleteFromLibrary() async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete from library?',
      message: 'This permanently deletes this block for every resume that '
          'uses it. It must not be attached to any resume first.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(resumeEditorControllerProvider(widget.resumeId).notifier)
          .deleteBlockFromLibrary(ResumeBlockType.experience, widget.blockId!);
      if (mounted) Navigator.of(context).pop();
    } on BlockInUseException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isCreate) {
      body = _form();
    } else {
      final blockAsync = ref.watch(experienceBlockByIdProvider(widget.blockId!));
      body = blockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(title: "Couldn't load this block", error: err),
        data: (block) {
          if (block == null) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Block not found',
              message: 'It may have been deleted.',
            );
          }
          _seed(block);
          return _form();
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? 'New experience' : 'Edit experience'),
        actions: [
          if (!_isCreate)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete from library',
              onPressed: _deleteFromLibrary,
            ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _save,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Save'),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        TextField(controller: _role, decoration: const InputDecoration(labelText: 'Role')),
        const SizedBox(height: 12),
        TextField(controller: _company, decoration: const InputDecoration(labelText: 'Company')),
        const SizedBox(height: 12),
        TextField(
          controller: _location,
          decoration: const InputDecoration(labelText: 'Location (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _startDate,
          decoration: const InputDecoration(labelText: 'Start date', helperText: 'YYYY-MM'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endDate,
          decoration: const InputDecoration(labelText: 'End date', helperText: 'YYYY-MM, blank = Present'),
        ),
        const SizedBox(height: 12),
        BulletSuggestionField(controller: _bullets, entryContextLabel: _entryContextLabel()),
        if (_subProjects.isNotEmpty) ...[
          const SizedBox(height: 20),
          _subProjectsReadOnlyPanel(),
        ],
      ],
    );
  }

  /// Read-only for now - no dedicated per-sub-project editing UI exists
  /// yet, so this exists only to make the nested sub-projects (Resume ->
  /// Experience -> Project -> Project bullets, migration v20) visible here
  /// rather than an invisible field that silently rides along unedited.
  /// [_save] already preserves [_subProjects] unchanged on every save.
  Widget _subProjectsReadOnlyPanel() {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '${_subProjects.length} sub-project${_subProjects.length == 1 ? '' : 's'} nested under this role',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Imported as-is and preserved when you save. Editing sub-projects individually isn\'t supported yet.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            for (final sub in _subProjects) ...[
              const Divider(height: 20),
              Text(sub.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              for (final bullet in sub.bullets)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('•  $bullet', style: theme.textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _entryContextLabel() {
    final role = _role.text.trim();
    final company = _company.text.trim();
    if (role.isEmpty && company.isEmpty) return 'this experience entry';
    if (company.isEmpty) return role;
    if (role.isEmpty) return company;
    return '$role at $company';
  }
}
