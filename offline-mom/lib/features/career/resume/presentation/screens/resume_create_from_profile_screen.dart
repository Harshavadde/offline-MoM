import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/resume_block_ref.dart';
import '../../../../../models/resume_block_type.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../providers/resume_block_library_providers.dart';
import '../providers/resume_editor_providers.dart';
import '../providers/resume_providers.dart';
import '../providers/skill_entry_providers.dart';

/// "Create Resume from Profile" (Product Validation phase,
/// docs/v3/implementation/03-decisions.md) - "MASTER PROFILE -> CREATE
/// RESUME -> ...". Reads the profile's *live* composition via the same
/// [resumeEditorControllerProvider] the Editor itself uses (read-only
/// here - this screen never calls any of its mutating methods), so the
/// list shown is always exactly what the profile actually contains, never
/// a second, potentially-stale copy of that data.
///
/// Every item defaults to selected - "no data should disappear" (the
/// product requirement) is satisfied by starting from "everything
/// included" and letting the user opt entries *out*, never starting from
/// an empty selection the user has to opt into.
class ResumeCreateFromProfileScreen extends ConsumerStatefulWidget {
  const ResumeCreateFromProfileScreen({super.key});

  @override
  ConsumerState<ResumeCreateFromProfileScreen> createState() =>
      _ResumeCreateFromProfileScreenState();
}

class _ResumeCreateFromProfileScreenState extends ConsumerState<ResumeCreateFromProfileScreen> {
  final _titleController = TextEditingController(text: 'New Resume');
  final Set<int> _excludedRefIds = {};
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _create(int profileId, List<ResumeBlockRef> allRefs) async {
    if (_isCreating) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isCreating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final selected = allRefs.where((r) => !_excludedRefIds.contains(r.id)).toList();
      final newId = await ref.read(createResumeFromProfileUseCaseProvider)(
        title: title,
        selectedRefs: selected,
      );
      if (mounted) context.pushReplacement(RoutePaths.resumeEditorPath(newId));
    } catch (e) {
      if (mounted) setState(() => _isCreating = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileResumeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Resume from Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: "Couldn't load your profile",
          message: friendlyErrorMessage(err),
        ),
        data: (profile) {
          if (profile == null) {
            return const EmptyState(
              icon: Icons.badge_outlined,
              title: 'No profile yet',
              message: 'Set up My Profile first, then come back here to create a '
                  'resume from it.',
            );
          }

          final editorState = ref.watch(resumeEditorControllerProvider(profile.id!));
          if (editorState is! ResumeEditorReady) {
            return const Center(child: CircularProgressIndicator());
          }
          final allRefs = editorState.blockRefs;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Resume title'),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  children: [
                    for (final type in ResumeBlockType.values)
                      _SelectableSection(
                        type: type,
                        refs: editorState.refsOf(type),
                        excludedRefIds: _excludedRefIds,
                        onToggle: (refId, included) => setState(() {
                          if (included) {
                            _excludedRefIds.remove(refId);
                          } else {
                            _excludedRefIds.add(refId);
                          }
                        }),
                      ),
                    if (allRefs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text(
                          'Your profile has no sections yet - this resume will start '
                          'with just your contact details. Add sections to My Profile '
                          'first if you want them available here.',
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton.icon(
                  onPressed: _isCreating ? null : () => _create(profile.id!, allRefs),
                  icon: _isCreating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                  label: const Text('Create Resume'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectableSection extends ConsumerWidget {
  const _SelectableSection({
    required this.type,
    required this.refs,
    required this.excludedRefIds,
    required this.onToggle,
  });

  final ResumeBlockType type;
  final List<ResumeBlockRef> refs;
  final Set<int> excludedRefIds;
  final void Function(int refId, bool included) onToggle;

  String _sectionTitle() => switch (type) {
        ResumeBlockType.experience => 'Experience',
        ResumeBlockType.education => 'Education',
        ResumeBlockType.project => 'Projects',
        ResumeBlockType.certification => 'Certifications',
        ResumeBlockType.skill => 'Skills',
        ResumeBlockType.customSection => 'Additional sections',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (refs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(_sectionTitle(), style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final blockRef in refs)
          _SelectableEntry(
            blockRef: blockRef,
            included: !excludedRefIds.contains(blockRef.id),
            onToggle: (included) => onToggle(blockRef.id!, included),
          ),
      ],
    );
  }
}

class _SelectableEntry extends ConsumerWidget {
  const _SelectableEntry({required this.blockRef, required this.included, required this.onToggle});

  final ResumeBlockRef blockRef;
  final bool included;
  final void Function(bool included) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = switch (blockRef.blockType) {
      ResumeBlockType.experience => ref.watch(experienceBlockByIdProvider(blockRef.blockId)).when(
            data: (b) => b == null ? null : '${b.role} - ${b.company}',
            loading: () => null,
            error: (_, __) => null,
          ),
      ResumeBlockType.education => ref.watch(educationBlockByIdProvider(blockRef.blockId)).when(
            data: (b) => b == null ? null : '${b.degree} - ${b.institution}',
            loading: () => null,
            error: (_, __) => null,
          ),
      ResumeBlockType.project => ref.watch(projectBlockByIdProvider(blockRef.blockId)).when(
            data: (b) => b?.name,
            loading: () => null,
            error: (_, __) => null,
          ),
      ResumeBlockType.certification =>
        ref.watch(certificationBlockByIdProvider(blockRef.blockId)).when(
              data: (b) => b == null ? null : '${b.name} - ${b.issuer}',
              loading: () => null,
              error: (_, __) => null,
            ),
      ResumeBlockType.skill => ref.watch(skillEntryListProvider).when(
            data: (skills) {
              final match = skills.where((s) => s.id == blockRef.blockId).firstOrNull;
              return match?.name;
            },
            loading: () => null,
            error: (_, __) => null,
          ),
      ResumeBlockType.customSection =>
        ref.watch(customSectionBlockByIdProvider(blockRef.blockId)).when(
              data: (b) => b?.title,
              loading: () => null,
              error: (_, __) => null,
            ),
    };

    return CheckboxListTile(
      value: included,
      onChanged: (value) => onToggle(value ?? true),
      title: Text(label ?? 'Loading…'),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
