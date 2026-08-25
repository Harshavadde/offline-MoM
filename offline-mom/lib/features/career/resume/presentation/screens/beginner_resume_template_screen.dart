import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../services/resume/template/resume_template_catalog.dart';
import '../../../../../services/resume/template/resume_template_spec.dart';
import '../providers/resume_template_providers.dart';

/// R-10 §10: a simple 3-template chooser for the Beginner Resume flow -
/// only [ResumeArchetypeIds.entryLevelStudent] (whose own `candidateType`
/// literally reads "Students and recent graduates whose education is more
/// relevant than a thin work history"), [ResumeArchetypeIds.classicSingleColumn],
/// and [ResumeArchetypeIds.modernAccentColumn] - all three
/// `AtsConfidence.maximum`. Deliberately narrower than
/// [ResumeTemplateGalleryScreen]'s full grid (which offers the 5 beta
/// -enabled templates and excludes `entryLevelStudent` entirely) rather
/// than a change to that screen's own selection - reuses
/// [ResumeTemplateCatalog.specById] directly, which (unlike
/// [ResumeTemplateCatalog.enabled]) is never filtered by beta status, so a
/// resume can use `entryLevelStudent` here even though it isn't offered in
/// the main gallery.
///
/// Reuses every rendering/selection piece the main gallery already uses -
/// [templateResumeThumbnailProvider] (the real, live-rendered PDF preview)
/// and [ResumeTemplateSelectionController.select] (the same single
/// -repository `Resume.templateId` update) - no second rendering path.
/// Tapping a card selects it immediately and opens the standard Resume
/// Editor, rather than a separate confirm step - the Editor's own "Choose a
/// template" action is always there afterward if the user wants to
/// reconsider, so a `Grid tap -> larger preview -> confirm` step (the main
/// gallery's own shape) would just add friction for a 3-option choice.
class BeginnerResumeTemplateScreen extends ConsumerWidget {
  const BeginnerResumeTemplateScreen({super.key, required this.resumeId});

  final int resumeId;

  static const _archetypeIds = [
    ResumeArchetypeIds.entryLevelStudent,
    ResumeArchetypeIds.classicSingleColumn,
    ResumeArchetypeIds.modernAccentColumn,
  ];

  /// [ResumeTemplateSpec.id] is a composite `'archetypeId-tokenPresetId'`
  /// (e.g. `'entry-level-student-warm'`), never the bare archetype id -
  /// [ResumeTemplateCatalog.specById] only matches that composite form and
  /// falls back to [ResumeTemplateCatalog.defaultSpec] (Classic) for
  /// anything else, so this looks specs up by [ResumeTemplateSpec.archetypeId]
  /// instead, preserving [_archetypeIds]' own order rather than
  /// [ResumeTemplateCatalog.all]'s.
  static List<ResumeTemplateSpec> _specs() => [
        for (final archetypeId in _archetypeIds)
          ResumeTemplateCatalog.all.firstWhere((s) => s.archetypeId == archetypeId),
      ];

  Future<void> _select(BuildContext context, WidgetRef ref, ResumeTemplateSpec spec) async {
    await ref.read(resumeTemplateSelectionControllerProvider(resumeId).notifier).select(spec);
    // R-11 P0 fix: `context.go(...)` replaced the ENTIRE navigation stack
    // with just the Editor route - silently discarding the real back
    // -history that got here (Home -> Resume List -> this screen), which
    // left the phone's back button with nothing to return to (real-device
    // report: "trapped inside Resume creation", no way back to Home).
    // `pushReplacement` swaps only this screen for the Editor, same
    // established pattern `ResumeTemplateDetailScreen._useThisTemplate`'s
    // own doc comment already documents and `JdToResumeScreen._createResume`
    // already uses - Home and Resume List stay in the stack underneath, so
    // back/pop from the Editor correctly returns to Resume List, then Home.
    if (context.mounted) context.pushReplacement(RoutePaths.resumeEditorPath(resumeId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = _specs();
    final selectionState = ref.watch(resumeTemplateSelectionControllerProvider(resumeId));

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a look for your resume')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'All three are ATS-friendly. You can always change this later '
              'from the resume editor.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          if (selectionState.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                selectionState.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.62,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: specs.length,
              itemBuilder: (context, index) {
                final spec = specs[index];
                return _BeginnerTemplateCard(
                  resumeId: resumeId,
                  spec: spec,
                  isBusy: selectionState.isBusy,
                  onTap: selectionState.isBusy ? null : () => _select(context, ref, spec),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BeginnerTemplateCard extends ConsumerWidget {
  const _BeginnerTemplateCard({
    required this.resumeId,
    required this.spec,
    required this.isBusy,
    required this.onTap,
  });

  final int resumeId;
  final ResumeTemplateSpec spec;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnailAsync =
        ref.watch(templateResumeThumbnailProvider((resumeId: resumeId, templateId: spec.id)));

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
                child: thumbnailAsync.when(
                  loading: () => const Center(
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => _thumbnailUnavailable(context),
                  data: (bytes) => bytes == null
                      ? _thumbnailUnavailable(context)
                      : Image.memory(bytes, fit: BoxFit.cover, alignment: Alignment.topCenter),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                spec.displayName,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnailUnavailable(BuildContext context) {
    return Center(
      child: Icon(
        Icons.description_outlined,
        size: 40,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }
}
