import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/result_pdf_preview.dart';
import '../providers/pdf_organize_providers.dart';
import '../toolkit_snackbars.dart';

/// Page Management (Productivity Toolkit productization pass, P0-5,
/// ADR-043) - Rotate/Delete/Extract/Insert/Duplicate/Replace/Reorder pages
/// of an existing PDF, then rebuild it. Supersedes the earlier "Organize
/// Pages" (reorder + extract only) screen in place - same route/tool tile,
/// a strict capability superset built on the shared `PdfPageComposerService`.
class PdfOrganizeScreen extends ConsumerWidget {
  const PdfOrganizeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfOrganizeControllerProvider);
    final notifier = ref.read(pdfOrganizeControllerProvider.notifier);

    ref.listen<PdfOrganizeState>(pdfOrganizeControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final hasResult = state.resultBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch ((hasResult, state.hasSelection)) {
          (true, _) => 'Result',
          (false, true) => '${state.selectionCount} selected',
          (false, false) => state.isEmpty ? 'Page Manager' : '${state.slots.length} page${state.slots.length == 1 ? '' : 's'}',
        }),
        leading: !hasResult && state.hasSelection
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear selection',
                onPressed: notifier.clearSelection,
              )
            : null,
        actions: [
          if (!hasResult && state.source != null) ...[
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo',
              onPressed: state.canUndo ? notifier.undo : null,
            ),
            PopupMenuButton<_OrganizeMenuAction>(
              onSelected: (action) => _handleMenuAction(context, ref, action),
              itemBuilder: (context) => [
                if (state.selectionCount < state.slots.length)
                  const PopupMenuItem(value: _OrganizeMenuAction.selectAll, child: Text('Select all')),
                const PopupMenuItem(value: _OrganizeMenuAction.rotateAll90, child: Text('Rotate all 90°')),
                const PopupMenuItem(value: _OrganizeMenuAction.insertPdf, child: Text('Insert PDF…')),
                const PopupMenuItem(value: _OrganizeMenuAction.insertImage, child: Text('Insert image…')),
                const PopupMenuItem(value: _OrganizeMenuAction.startOver, child: Text('Start over')),
              ],
            ),
          ] else if (state.source != null)
            IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Start over', onPressed: notifier.reset),
        ],
      ),
      body: SafeArea(
        child: switch ((state.source, hasResult)) {
          (null, _) => _PickPrompt(isBusy: state.isBusy, onPick: notifier.pickPdf),
          (_, false) => _PageListBody(state: state, notifier: notifier),
          (_, true) => _ResultBody(state: state, notifier: notifier),
        },
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, WidgetRef ref, _OrganizeMenuAction action) async {
    final notifier = ref.read(pdfOrganizeControllerProvider.notifier);
    switch (action) {
      case _OrganizeMenuAction.selectAll:
        notifier.selectAll();
      case _OrganizeMenuAction.rotateAll90:
        notifier.rotateAll(1);
      case _OrganizeMenuAction.insertPdf:
        await notifier.insertPdf(position: InsertPosition.atEnd);
      case _OrganizeMenuAction.insertImage:
        await notifier.insertImage(position: InsertPosition.atEnd);
      case _OrganizeMenuAction.startOver:
        notifier.reset();
    }
  }
}

enum _OrganizeMenuAction { selectAll, rotateAll90, insertPdf, insertImage, startOver }

double _rotationRadians(PdfPageRotation rotation) => switch (rotation) {
      PdfPageRotation.none => 0,
      PdfPageRotation.rotate90 => 1.5707963267948966, // pi/2
      PdfPageRotation.rotate180 => 3.141592653589793, // pi
      PdfPageRotation.rotate270 => 4.71238898038469, // 3*pi/2
    };

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({required this.isBusy, required this.onPick});
  final bool isBusy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    if (isBusy) return const Center(child: CircularProgressIndicator());
    return EmptyState(
      icon: Icons.auto_stories_rounded,
      title: 'Manage pages',
      message: 'Rotate, delete, duplicate, extract, insert, replace, or reorder pages, then rebuild the PDF.',
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

class _PageListBody extends StatelessWidget {
  const _PageListBody({required this.state, required this.notifier});
  final PdfOrganizeState state;
  final PdfOrganizeController notifier;

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
              final selected = state.selectedIds.contains(slot.id);
              final scheme = Theme.of(context).colorScheme;
              return Card(
                key: ValueKey(slot.id),
                margin: const EdgeInsets.only(bottom: 8),
                shape: selected
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: scheme.primary, width: 2),
                      )
                    : null,
                child: ListTile(
                  onTap: () => notifier.toggleSelect(slot.id),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Transform.rotate(
                          angle: _rotationRadians(slot.rotation),
                          child: Image.memory(
                            slot.jpegBytes,
                            width: 40,
                            height: 52,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: scheme.primary,
                            child: Icon(Icons.check_rounded, size: 12, color: scheme.onPrimary),
                          ),
                        ),
                    ],
                  ),
                  title: Text(slot.originalPageNumber != null ? 'Page ${slot.originalPageNumber}' : 'Added page'),
                  subtitle: Text(
                    slot.rotation == PdfPageRotation.none
                        ? 'Position ${index + 1}'
                        : 'Position ${index + 1} · rotated ${_rotationLabel(slot.rotation)}',
                  ),
                  trailing: const Icon(Icons.drag_handle_rounded),
                ),
              );
            },
          ),
        ),
        if (state.hasSelection) _ContextualActionBar(notifier: notifier),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: state.slots.isEmpty ? null : notifier.applyChanges,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Apply Changes'),
          ),
        ),
      ],
    );
  }

  String _rotationLabel(PdfPageRotation rotation) => switch (rotation) {
        PdfPageRotation.none => '',
        PdfPageRotation.rotate90 => '90°',
        PdfPageRotation.rotate180 => '180°',
        PdfPageRotation.rotate270 => '270°',
      };
}

/// The selection-dependent action row (Rotate/Duplicate/Extract/Replace/
/// Delete) - only shown once at least one page is selected, mirroring the
/// mega-spec's own "contextual toolbar... do not overload the screen with
/// dozens of buttons" instruction: nothing here is visible until it's
/// actually actionable.
class _ContextualActionBar extends StatelessWidget {
  const _ContextualActionBar({required this.notifier});
  final PdfOrganizeController notifier;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _ActionButton(icon: Icons.rotate_left_rounded, label: 'Rotate L', onTap: () => notifier.rotateSelected(3)),
          _ActionButton(icon: Icons.rotate_right_rounded, label: 'Rotate R', onTap: () => notifier.rotateSelected(1)),
          _ActionButton(icon: Icons.copy_rounded, label: 'Duplicate', onTap: notifier.duplicateSelected),
          _ActionButton(icon: Icons.content_cut_rounded, label: 'Extract', onTap: notifier.extractSelected),
          _ActionButton(icon: Icons.find_replace_rounded, label: 'Replace', onTap: () => _showReplaceSheet(context, notifier)),
          _ActionButton(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            onTap: notifier.deleteSelected,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Future<void> _showReplaceSheet(BuildContext context, PdfOrganizeController notifier) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Replace with a PDF page'),
              onTap: () => Navigator.of(context).pop('pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Replace with an image'),
              onTap: () => Navigator.of(context).pop('image'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'pdf') await notifier.replaceSelectedWithPdf();
    if (choice == 'image') await notifier.replaceSelectedWithImage();
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap, this.isDestructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isDestructive ? scheme.error : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.state, required this.notifier});
  final PdfOrganizeState state;
  final PdfOrganizeController notifier;

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
          child: ResultPdfPreview(
            bytesLoader: () async => state.resultBytes!,
            sourceName: 'organized.pdf',
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
                    Text('${state.resultPageCount}', style: Theme.of(context).textTheme.titleMedium),
                    const Text('Pages'),
                  ]),
                  Column(children: [
                    Text(formatFileSize(state.resultBytes!.lengthInBytes),
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
