import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/pdf_split_providers.dart';
import '../toolkit_snackbars.dart';

/// Split PDF (V2 Phase 5B) - pick one PDF, choose "every N pages" or tap
/// between page thumbnails to mark split points, then produce and save
/// several output PDFs at once.
class PdfSplitScreen extends ConsumerWidget {
  const PdfSplitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfSplitControllerProvider);
    final notifier = ref.read(pdfSplitControllerProvider.notifier);

    ref.listen<PdfSplitState>(pdfSplitControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split PDF'),
        actions: [
          if (state.source != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: notifier.reset,
            ),
        ],
      ),
      body: SafeArea(
        child: switch ((state.source, state.outputs.isNotEmpty)) {
          (null, _) => _PickPrompt(isBusy: state.isBusy, onPick: notifier.pickPdf),
          (_, false) => _ConfigureBody(state: state, notifier: notifier),
          (_, true) => _OutputsBody(state: state, notifier: notifier),
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
      icon: Icons.call_split_rounded,
      title: 'Divide a PDF into separate files',
      message: 'Split by a fixed number of pages, or mark your own breakpoints.',
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

class _ConfigureBody extends StatelessWidget {
  const _ConfigureBody({required this.state, required this.notifier});
  final PdfSplitState state;
  final PdfSplitController notifier;

  @override
  Widget build(BuildContext context) {
    if (state.isBusy) return const Center(child: CircularProgressIndicator());
    final groups = state.pageGroups;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${state.pageCount} pages', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<PdfSplitMode>(
                segments: const [
                  ButtonSegment(value: PdfSplitMode.everyNPages, label: Text('Every N pages')),
                  ButtonSegment(value: PdfSplitMode.customBreakpoints, label: Text('Tap to split')),
                ],
                selected: {state.mode},
                onSelectionChanged: (s) => notifier.setMode(s.first),
              ),
              if (state.mode == PdfSplitMode.everyNPages) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Pages per file:'),
                    Expanded(
                      child: Slider(
                        value: state.everyN.toDouble(),
                        min: 1,
                        max: state.pageCount.clamp(1, 50).toDouble(),
                        divisions: state.pageCount.clamp(1, 50) > 1 ? state.pageCount.clamp(1, 50) - 1 : 1,
                        label: '${state.everyN}',
                        onChanged: (v) => notifier.setEveryN(v.round()),
                      ),
                    ),
                    Text('${state.everyN}'),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Tap between two pages below to mark where a new file starts.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              const SizedBox(height: 4),
              Text('Will produce ${groups.length} file${groups.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemCount: state.pageThumbnails.length,
            itemBuilder: (context, index) {
              final thumb = state.pageThumbnails[index];
              final isBreakpoint = state.splitAfterPageIndices.contains(thumb.pageIndex);
              return GestureDetector(
                onTap: state.mode == PdfSplitMode.customBreakpoints
                    ? () => notifier.toggleBreakpointAfter(thumb.pageIndex)
                    : null,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isBreakpoint
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: isBreakpoint ? 3 : 1,
                          ),
                        ),
                        child: Image.memory(thumb.jpegBytes, fit: BoxFit.cover, filterQuality: FilterQuality.high),
                      ),
                    ),
                    Text('${thumb.pageIndex + 1}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: notifier.split,
            icon: const Icon(Icons.call_split_rounded),
            label: const Text('Split'),
          ),
        ),
      ],
    );
  }
}

class _OutputsBody extends StatelessWidget {
  const _OutputsBody({required this.state, required this.notifier});
  final PdfSplitState state;
  final PdfSplitController notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.outputs.length,
            itemBuilder: (context, index) {
              final output = state.outputs[index];
              final saved = state.savedOutputIndices.contains(index);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf_rounded),
                  title: Text(output.label),
                  subtitle: Text(
                    '${output.pageCount} page${output.pageCount == 1 ? '' : 's'} · '
                    '${formatFileSize(output.bytes.lengthInBytes)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.ios_share_rounded),
                        tooltip: 'Share',
                        onPressed: () => notifier.shareOutput(index),
                      ),
                      IconButton(
                        icon: Icon(saved ? Icons.check_circle_rounded : Icons.save_alt_rounded),
                        tooltip: saved ? 'Saved' : 'Save',
                        onPressed: saved
                            ? null
                            : () async {
                                await notifier.saveOutput(index);
                                if (!context.mounted) return;
                                showSavedToRecentFilesSnackBar(context);
                              },
                      ),
                    ],
                  ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All files saved to Recent Files.')),
              );
            },
            icon: const Icon(Icons.save_alt_rounded),
            label: Text('Save All (${state.outputs.length})'),
          ),
        ),
      ],
    );
  }
}
