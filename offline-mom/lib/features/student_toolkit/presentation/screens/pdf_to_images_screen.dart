import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/pdf_to_images_providers.dart';
import '../toolkit_snackbars.dart';

/// PDF -> Images (Productivity Toolkit productization pass, P0-6) - export
/// all or selected pages of a PDF as JPEG image files. Select PDF -> page
/// grid (select which pages) -> Export (with progress + cancel) -> results
/// list (save/share individually or all at once).
class PdfToImagesScreen extends ConsumerWidget {
  const PdfToImagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfToImagesControllerProvider);
    final notifier = ref.read(pdfToImagesControllerProvider.notifier);

    ref.listen<PdfToImagesState>(pdfToImagesControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(state.hasResults ? 'Exported Pages' : (state.isEmpty ? 'PDF to Images' : '${state.pageCount} pages')),
        actions: [
          if (!state.hasResults && state.source != null)
            IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Start over', onPressed: notifier.reset),
          if (state.hasResults)
            IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Start over', onPressed: notifier.reset),
        ],
      ),
      body: SafeArea(
        child: switch ((state.source, state.hasResults)) {
          (null, _) => _PickPrompt(isBusy: state.isBusy, onPick: notifier.pickPdf),
          (_, false) => _PageSelectionBody(state: state, notifier: notifier),
          (_, true) => _ResultsBody(state: state, notifier: notifier),
        },
      ),
    );
  }
}

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({required this.isBusy, required this.onPick});
  final bool isBusy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    if (isBusy) return const Center(child: CircularProgressIndicator());
    return EmptyState(
      icon: Icons.perm_media_outlined,
      title: 'Export PDF pages as images',
      message: 'Pick a PDF, then choose which pages to save as JPEG images - all of them, or just a few.',
      actions: [
        FilledButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose a PDF'),
        ),
      ],
    );
  }
}

class _PageSelectionBody extends StatelessWidget {
  const _PageSelectionBody({required this.state, required this.notifier});
  final PdfToImagesState state;
  final PdfToImagesController notifier;

  @override
  Widget build(BuildContext context) {
    if (state.isBusy && state.progress == null) return const Center(child: CircularProgressIndicator());
    if (state.isBusy && state.progress != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 12),
              Text('Exporting ${(state.progress! * 100).round()}%'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: notifier.cancelExport,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('${state.selectedPageIndices.length} of ${state.pageCount} selected', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(onPressed: notifier.selectAll, child: const Text('All')),
              TextButton(onPressed: notifier.selectNone, child: const Text('None')),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: state.pageThumbnails.length,
            itemBuilder: (context, index) {
              final thumb = state.pageThumbnails[index];
              final selected = state.selectedPageIndices.contains(thumb.pageIndex);
              return GestureDetector(
                onTap: () => notifier.toggleSelect(thumb.pageIndex),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Image.memory(thumb.jpegBytes, fit: BoxFit.cover, filterQuality: FilterQuality.high),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: Text('${thumb.pageIndex + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: CircleAvatar(radius: 10, backgroundColor: scheme.primary, child: Icon(Icons.check_rounded, size: 13, color: scheme.onPrimary)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: state.selectedPageIndices.isEmpty ? null : notifier.exportSelected,
            icon: const Icon(Icons.image_outlined),
            label: Text('Export ${state.selectedPageIndices.length} Page${state.selectedPageIndices.length == 1 ? '' : 's'}'),
          ),
        ),
      ],
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({required this.state, required this.notifier});
  final PdfToImagesState state;
  final PdfToImagesController notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
            itemCount: state.results.length,
            itemBuilder: (context, index) {
              final output = state.results[index];
              final saved = state.savedOutputIndices.contains(index);
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Image.memory(output.jpegBytes, fit: BoxFit.cover, filterQuality: FilterQuality.high)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('Page ${output.pageIndex + 1}\n${formatFileSize(output.jpegBytes.lengthInBytes)}', style: Theme.of(context).textTheme.labelSmall)),
                          IconButton(
                            icon: Icon(saved ? Icons.check_circle_rounded : Icons.save_alt_rounded, size: 18),
                            tooltip: saved ? 'Saved' : 'Save',
                            onPressed: saved
                                ? null
                                : () async {
                                    await notifier.saveOutput(index);
                                    if (!context.mounted) return;
                                    showSavedToRecentFilesSnackBar(context);
                                  },
                          ),
                          IconButton(
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            tooltip: 'Share',
                            onPressed: () => notifier.shareOutput(index),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () async {
              await notifier.saveAll();
              if (!context.mounted) return;
              showSavedToRecentFilesSnackBar(context);
            },
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Save All'),
          ),
        ),
      ],
    );
  }
}
