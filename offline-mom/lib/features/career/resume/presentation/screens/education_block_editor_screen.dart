import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/education_block.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../delete_library_block_use_case.dart';
import '../providers/resume_block_library_providers.dart';
import '../providers/resume_editor_providers.dart';
import '../widgets/bullet_suggestion_field.dart';

/// Creates or edits one [EducationBlock] in the shared library - mirrors
/// [ExperienceBlockEditorScreen]'s exact shape and reasoning.
class EducationBlockEditorScreen extends ConsumerStatefulWidget {
  const EducationBlockEditorScreen({super.key, required this.resumeId, this.blockId});

  final int resumeId;
  final int? blockId;

  @override
  ConsumerState<EducationBlockEditorScreen> createState() => _EducationBlockEditorScreenState();
}

class _EducationBlockEditorScreenState extends ConsumerState<EducationBlockEditorScreen> {
  final _institution = TextEditingController();
  final _degree = TextEditingController();
  final _fieldOfStudy = TextEditingController();
  final _startDate = TextEditingController();
  final _endDate = TextEditingController();
  final _details = TextEditingController();
  bool _seeded = false;
  bool _isSaving = false;

  bool get _isCreate => widget.blockId == null;

  @override
  void dispose() {
    _institution.dispose();
    _degree.dispose();
    _fieldOfStudy.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _details.dispose();
    super.dispose();
  }

  void _seed(EducationBlock block) {
    if (_seeded) return;
    _seeded = true;
    _institution.text = block.institution;
    _degree.text = block.degree;
    _fieldOfStudy.text = block.fieldOfStudy ?? '';
    _startDate.text = block.startDate;
    _endDate.text = block.endDate ?? '';
    _details.text = block.details.join('\n');
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final now = DateTime.now();
    final details =
        _details.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    try {
      if (_isCreate) {
        final id = await ref.read(educationBlockRepositoryProvider).insert(EducationBlock(
              id: null,
              institution: _institution.text.trim(),
              degree: _degree.text.trim(),
              fieldOfStudy: _fieldOfStudy.text.trim().isEmpty ? null : _fieldOfStudy.text.trim(),
              startDate: _startDate.text.trim(),
              endDate: _endDate.text.trim().isEmpty ? null : _endDate.text.trim(),
              details: details,
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(educationBlockListProvider);
        await ref
            .read(resumeEditorControllerProvider(widget.resumeId).notifier)
            .attachBlock(ResumeBlockType.education, id);
      } else {
        await ref.read(educationBlockRepositoryProvider).update(EducationBlock(
              id: widget.blockId,
              institution: _institution.text.trim(),
              degree: _degree.text.trim(),
              fieldOfStudy: _fieldOfStudy.text.trim().isEmpty ? null : _fieldOfStudy.text.trim(),
              startDate: _startDate.text.trim(),
              endDate: _endDate.text.trim().isEmpty ? null : _endDate.text.trim(),
              details: details,
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(educationBlockByIdProvider(widget.blockId!));
        ref.invalidate(educationBlockListProvider);
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
          .deleteBlockFromLibrary(ResumeBlockType.education, widget.blockId!);
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
      final blockAsync = ref.watch(educationBlockByIdProvider(widget.blockId!));
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
        title: Text(_isCreate ? 'New education' : 'Edit education'),
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
        TextField(controller: _institution, decoration: const InputDecoration(labelText: 'Institution')),
        const SizedBox(height: 12),
        TextField(controller: _degree, decoration: const InputDecoration(labelText: 'Degree')),
        const SizedBox(height: 12),
        TextField(
          controller: _fieldOfStudy,
          decoration: const InputDecoration(labelText: 'Field of study (optional)'),
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
        BulletSuggestionField(
          controller: _details,
          entryContextLabel: _entryContextLabel(),
          labelText: 'Details (optional)',
          helperText: 'Honors, GPA, coursework - one per line',
        ),
      ],
    );
  }

  String _entryContextLabel() {
    final degree = _degree.text.trim();
    final institution = _institution.text.trim();
    if (degree.isEmpty && institution.isEmpty) return 'this education entry';
    if (institution.isEmpty) return degree;
    if (degree.isEmpty) return institution;
    return '$degree, $institution';
  }
}
