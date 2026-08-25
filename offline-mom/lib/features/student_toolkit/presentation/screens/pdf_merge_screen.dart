import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/result_pdf_preview.dart';
import '../providers/pdf_merge_providers.dart';
import '../toolkit_snackbars.dart';

/// Merge PDFs (V2 Phase 5B) - a queue-building session (add/remove/
/// reorder files, then merge once), mirroring `ScannerScreen`'s "session,
/// not pipeline" structure.
class PdfMergeScreen extends ConsumerWidget {
  const PdfMergeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfMergeControllerProvider);
    final notifier = ref.read(pdfMergeControllerProvider.notifier);

    ref.listen<PdfMergeState>(pdfMergeControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final merged = state.mergedBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(merged ? 'Merged PDF' : 'Merge PDFs'),
        actions: [
          if (state.items.isNotEmpty || merged)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: notifier.reset,
            ),
        ],
      ),
      body: SafeArea(
        child: merged
            ? _ResultBody(state: state, notifier: notifier)
            : _QueueBody(state: state, notifier: notifier),
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.state, required this.notifier});
  final PdfMergeState state;
  final PdfMergeController notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: state.isBusy
              ? const Center(child: CircularProgressIndicator())
              : state.items.isEmpty
                  ? const EmptyState(
                      icon: Icons.call_merge_rounded,
                      title: 'Add files to merge',
                      message: 'Pick two or more PDFs or images - they\'ll be combined '
                          'into one PDF, in the order you add them.',
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      itemCount: state.items.length,
                      onReorderItem: notifier.reorderItem,
                      itemBuilder: (context, index) {
                        final item = state.items[index];
                        return Card(
                          key: ValueKey(item.id),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(item.isPdf
                                ? Icons.picture_as_pdf_rounded
                                : Icons.image_outlined),
                            title: Text(item.fileName, overflow: TextOverflow.ellipsis),
                            subtitle: Text(formatFileSize(item.sizeBytes)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: 'Remove',
                                  onPressed: () => notifier.removeItem(item.id),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy ? null : notifier.addFiles,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Files'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isBusy || state.items.length < 2 ? null : notifier.merge,
                  icon: const Icon(Icons.call_merge_rounded),
                  label: const Text('Merge'),
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
  const _ResultBody({required this.state, required this.notifier});
  final PdfMergeState state;
  final PdfMergeController notifier;

  @override
  Widget build(BuildContext context) {
    final saved = state.savedFile != null;
    return Column(
      children: [
        Expanded(
          child: ResultPdfPreview(
            bytesLoader: () async => state.mergedBytes!,
            sourceName: 'merged.pdf',
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
                    Text('${state.items.length}', style: Theme.of(context).textTheme.titleMedium),
                    const Text('Files merged'),
                  ]),
                  Column(children: [
                    Text('${state.mergedPageCount}', style: Theme.of(context).textTheme.titleMedium),
                    const Text('Pages'),
                  ]),
                  Column(children: [
                    Text(formatFileSize(state.mergedBytes!.lengthInBytes),
                        style: Theme.of(context).textTheme.titleMedium),
                    const Text('PDF Size'),
                  ]),
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
}
