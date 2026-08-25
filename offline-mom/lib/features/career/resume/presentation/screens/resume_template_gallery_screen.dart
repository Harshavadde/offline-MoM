import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../services/resume/template/resume_template_spec.dart';
import '../providers/resume_editor_providers.dart';
import '../providers/resume_template_providers.dart';

/// Lets the user browse and pick which template (docs/v3/01-prd.md §8) a
/// resume renders with. Every card shows a **real** PDF-rendered
/// thumbnail (`templateResumeThumbnailProvider`, itself built from
/// `templateResumePdfBytesProvider` - real-device beta fix (Phase 7): the
/// *actual current resume being edited*, compiled live via the Editor's
/// own `compileSnapshot()`, rendered through the exact same
/// [ResumeTemplateRenderer] the final export/preview uses - never a fixed
/// sample resume and never a decorative hand-drawn mock, so the user sees
/// what *their own* resume looks like in each template before choosing.
/// Tapping a card opens [ResumeTemplateDetailScreen] for a larger real
/// preview and an explicit "Use This Template" confirm - selecting is
/// never silent and never happens on the grid tap alone.
class ResumeTemplateGalleryScreen extends ConsumerWidget {
  const ResumeTemplateGalleryScreen({super.key, required this.resumeId});

  final int resumeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(resumeTemplateCatalogProvider);
    final editorState = ref.watch(resumeEditorControllerProvider(resumeId));
    final currentTemplateId =
        editorState is ResumeEditorReady ? editorState.resume.templateId : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a template')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final spec = templates[index];
          return _TemplateCard(
            resumeId: resumeId,
            spec: spec,
            isSelected: spec.id == currentTemplateId,
            onTap: () => context.push(RoutePaths.resumeTemplateDetailPath(resumeId, spec.id)),
          );
        },
      ),
    );
  }
}

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({
    required this.resumeId,
    required this.spec,
    required this.isSelected,
    required this.onTap,
  });

  final int resumeId;
  final ResumeTemplateSpec spec;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TemplateThumbnail(resumeId: resumeId, templateId: spec.id, isSelected: isSelected),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spec.candidateType,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _AtsConfidenceChip(confidence: spec.atsConfidence),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The real, PDF-rendered preview image for one template's grid card -
/// [templateSampleThumbnailProvider] does the actual rendering/rasterizing;
/// this widget only handles the three states that produces (loading /
/// unavailable / ready) and the selected-state checkmark overlay.
class _TemplateThumbnail extends ConsumerWidget {
  const _TemplateThumbnail({required this.resumeId, required this.templateId, required this.isSelected});

  final int resumeId;
  final String templateId;
  final bool isSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnailAsync =
        ref.watch(templateResumeThumbnailProvider((resumeId: resumeId, templateId: templateId)));

    return Container(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumbnailAsync.when(
            loading: () => const Center(
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => _thumbnailUnavailable(context),
            data: (bytes) => bytes == null
                ? _thumbnailUnavailable(context)
                : Image.memory(bytes, fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
          if (isSelected)
            Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: scheme.primary,
                child: Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }

  /// Best-effort degradation, never a crash - `Printing.raster` isn't
  /// guaranteed on every platform (see `templateSampleThumbnailProvider`'s
  /// own doc comment). The template is still fully selectable and its
  /// real preview still works via [ResumeTemplateDetailScreen]'s
  /// [PdfPreview] - only this small grid thumbnail is affected.
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

class _AtsConfidenceChip extends StatelessWidget {
  const _AtsConfidenceChip({required this.confidence});

  final AtsConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (confidence) {
      AtsConfidence.maximum => ('Maximum ATS', Icons.verified_rounded, Colors.green.shade700),
      AtsConfidence.high => ('High ATS', Icons.check_circle_outline_rounded, Colors.blue.shade700),
      AtsConfidence.medium => ('Medium ATS', Icons.info_outline_rounded, Colors.orange.shade800),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
