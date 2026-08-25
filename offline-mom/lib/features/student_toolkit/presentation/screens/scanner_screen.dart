import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../services/ocr/searchable_pdf_builder_service.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../providers/ocr_providers.dart';
import '../providers/scanner_providers.dart';
import '../toolkit_snackbars.dart';
import 'scan_page_editor_screen.dart';

/// Scanner (V2 Phase 5B) - capture/import multiple pages, reorder/rotate/
/// adjust each one, generate a single PDF, then save/share/rename/
/// duplicate/delete like every other Recent Files entry. A multi-page
/// editable session (see `ScannerState`'s own doc comment for why this
/// screen switches on session shape rather than a sealed pipeline state).
class ScannerScreen extends ConsumerWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scannerControllerProvider);
    final notifier = ref.read(scannerControllerProvider.notifier);

    ref.listen<ScannerState>(scannerControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final hasGeneratedPdf = state.generatedPdfBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasGeneratedPdf ? 'Generated PDF' : 'Scan Document'),
        actions: [
          if (state.pages.isNotEmpty || hasGeneratedPdf)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: () => _confirmReset(context, notifier),
            ),
        ],
      ),
      body: SafeArea(
        child: switch ((state.pages.isEmpty, hasGeneratedPdf)) {
          (true, _) => _EmptyPrompt(
              isBusy: state.isBusy,
              onCamera: notifier.captureFromCamera,
              onGallerySingle: notifier.importFromGallerySingle,
              onGalleryMultiple: notifier.importMultipleFromGallery,
            ),
          (false, false) => _PageListBody(state: state, notifier: notifier),
          (false, true) => _ResultBody(state: state, notifier: notifier, ref: ref),
        },
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, ScannerController notifier) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Start over?',
      message: 'This discards every page in this scan session. Already-saved PDFs are not affected.',
      confirmLabel: 'Start Over',
    );
    if (confirmed) notifier.reset();
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({
    required this.isBusy,
    required this.onCamera,
    required this.onGallerySingle,
    required this.onGalleryMultiple,
  });

  final bool isBusy;
  final VoidCallback onCamera;
  final VoidCallback onGallerySingle;
  final VoidCallback onGalleryMultiple;

  @override
  Widget build(BuildContext context) {
    if (isBusy) return const Center(child: CircularProgressIndicator());
    return EmptyState(
      icon: Icons.document_scanner_rounded,
      title: 'Scan a document',
      message: 'Notes, forms, certificates, mark sheets, ID cards and more '
          '- entirely on this device, nothing is ever uploaded.',
      actions: [
        FilledButton.icon(
          onPressed: onCamera,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Capture with Camera'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onGalleryMultiple,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Import from Gallery'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onGallerySingle,
          child: const Text('Add one photo at a time instead'),
        ),
      ],
    );
  }
}

class _PageListBody extends StatelessWidget {
  const _PageListBody({required this.state, required this.notifier});

  final ScannerState state;
  final ScannerController notifier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${state.pages.length} page${state.pages.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (state.canUndoDelete)
                TextButton.icon(
                  onPressed: notifier.undoDeletePage,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Undo delete'),
                ),
            ],
          ),
        ),
        Expanded(
          child: state.isBusy
              ? const Center(child: CircularProgressIndicator())
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  itemCount: state.pages.length,
                  onReorderItem: notifier.reorderPage,
                  itemBuilder: (context, index) {
                    final page = state.pages[index];
                    return Card(
                      key: ValueKey(page.id),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            page.jpegBytes,
                            width: 44,
                            height: 56,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        title: Text('Page ${index + 1}'),
                        subtitle: Text('${page.width}×${page.height}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.crop_rounded),
                              tooltip: 'Adjust / Crop',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ScanPageEditorScreen(pageId: page.id),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              tooltip: 'Delete page',
                              color: scheme.error,
                              onPressed: () => notifier.deletePage(page.id),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.drag_handle_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy ? null : notifier.importMultipleFromGallery,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add Page'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isBusy ? null : notifier.generatePdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generate PDF'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.state, required this.notifier, required this.ref});

  final ScannerState state;
  final ScannerController notifier;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final saved = state.savedFile != null;
    return Column(
      children: [
        Expanded(
          child: PdfPreview(
            build: (format) async => state.generatedPdfBytes!,
            canDebug: false,
            allowPrinting: false,
            useActions: false,
            // Toolkit productization pass, P0-1: see pdf_merge_screen.dart's
            // identical fix for the root cause (release-mode ErrorWidget
            // strips its own message, leaving a bare textless box).
            onError: (context, error) => ErrorState(
              title: 'Preview unavailable',
              error: error,
            ),
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
                  _stat(context, '${state.pages.length}', 'Pages'),
                  _stat(context, formatFileSize(state.generatedPdfBytes!.lengthInBytes), 'PDF Size'),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              FilledButton.icon(
                onPressed: saved
                    ? null
                    : () async {
                        await notifier.save();
                        if (!context.mounted) return;
                        showSavedToRecentFilesSnackBar(context);
                      },
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    saved ? Icons.check_rounded : Icons.save_alt_rounded,
                    key: ValueKey(saved),
                  ),
                ),
                label: Text(saved ? 'Saved' : 'Save'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final pages = [
                    for (final page in state.pages)
                      OcrSourcePage(jpegBytes: page.jpegBytes, width: page.width, height: page.height),
                  ];
                  await ref.read(ocrSessionControllerProvider.notifier).start(
                        pages: pages,
                        documentName: 'Scan ${state.pages.length} page${state.pages.length == 1 ? '' : 's'}',
                      );
                  if (!context.mounted) return;
                  context.push(RoutePaths.toolkitOcr);
                },
                icon: const Icon(Icons.text_fields_rounded),
                label: const Text('Save Searchable PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: notifier.share,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
