import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../services/ocr/searchable_pdf_builder_service.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../providers/images_to_pdf_providers.dart';
import '../providers/ocr_providers.dart';
import '../toolkit_snackbars.dart';

/// Images -> PDF (Productivity Toolkit productization pass, P0-6) - select
/// one or more images (gallery or file picker), reorder/rotate/remove them,
/// then build one PDF. Select -> Preview/Reorder -> Optional Edit ->
/// Generate PDF -> Preview Result -> Save, per this pass's own explicit
/// flow - nothing is written to disk until the user explicitly saves.
class ImagesToPdfScreen extends ConsumerWidget {
  const ImagesToPdfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imagesToPdfControllerProvider);
    final notifier = ref.read(imagesToPdfControllerProvider.notifier);

    ref.listen<ImagesToPdfState>(imagesToPdfControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final hasResult = state.resultBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasResult ? 'Result' : (state.isEmpty ? 'Images to PDF' : '${state.slots.length} image${state.slots.length == 1 ? '' : 's'}')),
        actions: [
          if (!hasResult && !state.isEmpty) ...[
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo',
              onPressed: state.canUndo ? notifier.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: notifier.reset,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: switch ((state.isEmpty, hasResult)) {
          (true, _) => _PickPrompt(isBusy: state.isBusy, notifier: notifier),
          (false, false) => _ImageListBody(state: state, notifier: notifier, ref: ref),
          (false, true) => _ResultBody(state: state, notifier: notifier),
        },
      ),
    );
  }
}

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({required this.isBusy, required this.notifier});
  final bool isBusy;
  final ImagesToPdfController notifier;

  @override
  Widget build(BuildContext context) {
    if (isBusy) return const Center(child: CircularProgressIndicator());
    return EmptyState(
      icon: Icons.image_outlined,
      title: 'Combine images into one PDF',
      message: 'Pick one or more photos - each becomes its own page, sized to '
          'match that photo\'s own orientation (portrait stays portrait, '
          'landscape stays landscape).',
      actions: [
        FilledButton.icon(
          onPressed: notifier.addImages,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from Gallery'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: notifier.addImagesFromFiles,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose from Files'),
        ),
      ],
    );
  }
}

double _rotationRadians(PdfPageRotation rotation) => switch (rotation) {
      PdfPageRotation.none => 0,
      PdfPageRotation.rotate90 => 1.5707963267948966,
      PdfPageRotation.rotate180 => 3.141592653589793,
      PdfPageRotation.rotate270 => 4.71238898038469,
    };

class _ImageListBody extends StatelessWidget {
  const _ImageListBody({required this.state, required this.notifier, required this.ref});
  final ImagesToPdfState state;
  final ImagesToPdfController notifier;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (state.isBusy) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            itemCount: state.slots.length,
            onReorderItem: notifier.reorderSlot,
            itemBuilder: (context, index) {
              final slot = state.slots[index];
              return Card(
                key: ValueKey(slot.id),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Transform.rotate(
                      angle: _rotationRadians(slot.rotation),
                      child: Image.memory(slot.jpegBytes, width: 44, height: 56, fit: BoxFit.cover),
                    ),
                  ),
                  title: Text('Page ${index + 1}'),
                  subtitle: Text('${slot.width}×${slot.height}${slot.rotation == PdfPageRotation.none ? '' : ' · rotated'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.rotate_left_rounded),
                        tooltip: 'Rotate left',
                        onPressed: () => notifier.rotateSlot(slot.id, 3),
                      ),
                      IconButton(
                        icon: const Icon(Icons.rotate_right_rounded),
                        tooltip: 'Rotate right',
                        onPressed: () => notifier.rotateSlot(slot.id, 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Remove',
                        onPressed: () => notifier.removeSlot(slot.id),
                      ),
                      const Icon(Icons.drag_handle_rounded),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: notifier.addImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add More'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: FilledButton.icon(
            onPressed: state.slots.isEmpty ? null : notifier.generatePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Generate PDF'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: OutlinedButton.icon(
            onPressed: state.slots.isEmpty
                ? null
                : () async {
                    final pages = [
                      for (final slot in state.slots)
                        OcrSourcePage(
                          jpegBytes: slot.jpegBytes,
                          width: slot.width,
                          height: slot.height,
                          rotation: slot.rotation,
                        ),
                    ];
                    await ref.read(ocrSessionControllerProvider.notifier).start(
                          pages: pages,
                          documentName: 'Images (${state.slots.length})',
                        );
                    if (!context.mounted) return;
                    context.push(RoutePaths.toolkitOcr);
                  },
            icon: const Icon(Icons.text_fields_rounded),
            label: const Text('Generate Searchable PDF'),
          ),
        ),
      ],
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.state, required this.notifier});
  final ImagesToPdfState state;
  final ImagesToPdfController notifier;

  @override
  Widget build(BuildContext context) {
    final saved = state.savedFile != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: notifier.discardResult,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Keep Editing'),
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (format) async => state.resultBytes!,
            canDebug: false,
            allowPrinting: false,
            useActions: false,
            onError: (context, error) => ErrorState(title: 'Preview unavailable', error: error),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(children: [
                    Text('${state.slots.length}', style: Theme.of(context).textTheme.titleMedium),
                    const Text('Pages'),
                  ]),
                  Column(children: [
                    Text(formatFileSize(state.resultBytes!.lengthInBytes), style: Theme.of(context).textTheme.titleMedium),
                    const Text('PDF Size'),
                  ]),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: saved
                ? null
                : () async {
                    await notifier.save();
                    if (!context.mounted) return;
                    showSavedToRecentFilesSnackBar(context);
                  },
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(saved ? Icons.check_rounded : Icons.save_alt_rounded, key: ValueKey(saved)),
            ),
            label: Text(saved ? 'Saved' : 'Save'),
          ),
        ),
      ],
    );
  }
}
