import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/certification_block.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../delete_library_block_use_case.dart';
import '../providers/resume_block_library_providers.dart';
import '../providers/resume_editor_providers.dart';

/// Creates or edits one [CertificationBlock] in the shared library - mirrors
/// [ExperienceBlockEditorScreen]'s exact shape and reasoning. Unlike
/// Experience/Education/Project, certifications have no bullet content and
/// so no "Customize for this resume" override is ever offered for them
/// (see [ResumeCompilerService.compile]'s own doc comment).
class CertificationBlockEditorScreen extends ConsumerStatefulWidget {
  const CertificationBlockEditorScreen({super.key, required this.resumeId, this.blockId});

  final int resumeId;
  final int? blockId;

  @override
  ConsumerState<CertificationBlockEditorScreen> createState() =>
      _CertificationBlockEditorScreenState();
}

class _CertificationBlockEditorScreenState extends ConsumerState<CertificationBlockEditorScreen> {
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _issuedDate = TextEditingController();
  final _credentialUrl = TextEditingController();
  bool _seeded = false;
  bool _isSaving = false;

  bool get _isCreate => widget.blockId == null;

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _issuedDate.dispose();
    _credentialUrl.dispose();
    super.dispose();
  }

  void _seed(CertificationBlock block) {
    if (_seeded) return;
    _seeded = true;
    _name.text = block.name;
    _issuer.text = block.issuer;
    _issuedDate.text = block.issuedDate ?? '';
    _credentialUrl.text = block.credentialUrl ?? '';
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final now = DateTime.now();
    try {
      if (_isCreate) {
        final id = await ref.read(certificationBlockRepositoryProvider).insert(CertificationBlock(
              id: null,
              name: _name.text.trim(),
              issuer: _issuer.text.trim(),
              issuedDate: _issuedDate.text.trim().isEmpty ? null : _issuedDate.text.trim(),
              credentialUrl:
                  _credentialUrl.text.trim().isEmpty ? null : _credentialUrl.text.trim(),
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(certificationBlockListProvider);
        await ref
            .read(resumeEditorControllerProvider(widget.resumeId).notifier)
            .attachBlock(ResumeBlockType.certification, id);
      } else {
        await ref.read(certificationBlockRepositoryProvider).update(CertificationBlock(
              id: widget.blockId,
              name: _name.text.trim(),
              issuer: _issuer.text.trim(),
              issuedDate: _issuedDate.text.trim().isEmpty ? null : _issuedDate.text.trim(),
              credentialUrl:
                  _credentialUrl.text.trim().isEmpty ? null : _credentialUrl.text.trim(),
              createdAt: now,
              updatedAt: now,
            ));
        ref.invalidate(certificationBlockByIdProvider(widget.blockId!));
        ref.invalidate(certificationBlockListProvider);
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
          .deleteBlockFromLibrary(ResumeBlockType.certification, widget.blockId!);
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
      final blockAsync = ref.watch(certificationBlockByIdProvider(widget.blockId!));
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
        title: Text(_isCreate ? 'New certification' : 'Edit certification'),
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
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Certification name')),
        const SizedBox(height: 12),
        TextField(controller: _issuer, decoration: const InputDecoration(labelText: 'Issuer')),
        const SizedBox(height: 12),
        TextField(
          controller: _issuedDate,
          decoration: const InputDecoration(labelText: 'Issued date (optional)', helperText: 'YYYY-MM'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _credentialUrl,
          decoration: const InputDecoration(labelText: 'Credential URL (optional)'),
        ),
      ],
    );
  }
}
