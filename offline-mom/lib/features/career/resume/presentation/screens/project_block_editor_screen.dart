import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/project_block.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../delete_library_block_use_case.dart';
import '../providers/resume_block_library_providers.dart';
import '../providers/resume_editor_providers.dart';
import '../widgets/bullet_suggestion_field.dart';

/// Creates or edits one [ProjectBlock] in the shared library - mirrors
/// [ExperienceBlockEditorScreen]'s exact shape and reasoning.
class ProjectBlockEditorScreen extends ConsumerStatefulWidget {
  const ProjectBlockEditorScreen({super.key, required this.resumeId, this.blockId});

  final int resumeId;
  final int? blockId;

  @override
  ConsumerState<ProjectBlockEditorScreen> createState() => _ProjectBlockEditorScreenState();
}

class _ProjectBlockEditorScreenState extends ConsumerState<ProjectBlockEditorScreen> {
  final _name = TextEditingController();
  final _link = TextEditingController();
  final _bullets = TextEditingController();
  bool _seeded = false;
  bool _isSaving = false;

  bool get _isCreate => widget.blockId == null;

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    _bullets.dispose();
    super.dispose();
  }

  void _seed(ProjectBlock block) {
    if (_seeded) return;
    _seeded = true;
    _name.text = block.name;
    _link.text = block.link ?? '';
    _bullets.text = block.bullets.join('\n');
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final now = DateTime.now();
    final bullets =
        _bullets.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    try {
      if (_isCreate) {
        final id = await ref.read(projectBlockRepositoryProvider).insert(ProjectBlock(
              id: null,
              name: _name.text.trim(),
              link: _link.text.trim().isEmpty ? null : _link.text.trim(),
              bullets: bullets,
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(projectBlockListProvider);
        await ref
            .read(resumeEditorControllerProvider(widget.resumeId).notifier)
            .attachBlock(ResumeBlockType.project, id);
      } else {
        await ref.read(projectBlockRepositoryProvider).update(ProjectBlock(
              id: widget.blockId,
              name: _name.text.trim(),
              link: _link.text.trim().isEmpty ? null : _link.text.trim(),
              bullets: bullets,
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(projectBlockByIdProvider(widget.blockId!));
        ref.invalidate(projectBlockListProvider);
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
          .deleteBlockFromLibrary(ResumeBlockType.project, widget.blockId!);
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
      final blockAsync = ref.watch(projectBlockByIdProvider(widget.blockId!));
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
        title: Text(_isCreate ? 'New project' : 'Edit project'),
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
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Project name')),
        const SizedBox(height: 12),
        TextField(controller: _link, decoration: const InputDecoration(labelText: 'Link (optional)')),
        const SizedBox(height: 12),
        BulletSuggestionField(
          controller: _bullets,
          entryContextLabel: _name.text.trim().isEmpty ? 'this project' : _name.text.trim(),
        ),
      ],
    );
  }
}
