import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/toolkit/pdf_redaction.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/result_pdf_preview.dart';
import '../providers/pdf_redact_providers.dart';

/// Redact PDF (Productivity Toolkit productization pass, P0-4, ADR-042) -
/// draw one or more rectangular regions, then permanently overwrite their
/// pixels via `PdfRedactionService` (`pdf_redaction_service.dart`) - a
/// deliberately separate mechanism from Edit PDF's overlay-based tools
/// (P0-3/ADR-041). See that service's own doc comment for the security
/// argument: the redacted region's original pixel data does not exist
/// anywhere in the produced file, not merely covered by something drawn on
/// top of it.
///
/// Never destroys the original document until the user explicitly
/// confirms and saves - [PdfRedactController] holds every drawn region
/// purely in memory (`PdfRedactState.marksByPage`) until `save()` is
/// called, and even then writes a *new* file; the source PDF the user
/// picked is never opened for writing.
class PdfRedactScreen extends ConsumerStatefulWidget {
  const PdfRedactScreen({super.key});

  @override
  ConsumerState<PdfRedactScreen> createState() => _PdfRedactScreenState();
}

class _PdfRedactScreenState extends ConsumerState<PdfRedactScreen> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfRedactControllerProvider);

    ref.listen(pdfRedactControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    if (state.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Redact PDF')),
        body: Center(
          child: EmptyState(
            icon: Icons.hide_source_rounded,
            title: 'Permanently remove sensitive content',
            message: 'Pick a PDF, then draw a box over anything you want removed. '
                'Redaction permanently removes the selected content from the '
                'exported copy - it is not a visual cover-up, and it cannot be '
                'undone once saved.',
            actionLabel: 'Choose PDF',
            onAction: () => ref.read(pdfRedactControllerProvider.notifier).pickPdf(),
          ),
        ),
      );
    }

    if (state.isBusy && state.pages.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final page = _currentPage < state.pages.length ? state.pages[_currentPage] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(state.pages.length > 1 ? 'Page ${_currentPage + 1} of ${state.pages.length}' : 'Redact PDF'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Undo',
            onPressed: state.canUndo ? () => ref.read(pdfRedactControllerProvider.notifier).undo() : null,
          ),
          TextButton(
            onPressed: state.totalRegionCount == 0 || state.isBusy ? null : () => _preview(context, ref),
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const _PermanenceBanner(),
            Expanded(
              child: page == null
                  ? const Center(child: Text('This page could not be loaded.'))
                  : _PdfRedactCanvas(
                      page: page,
                      marks: state.marksByPage[_currentPage] ?? const [],
                    ),
            ),
            if (state.pages.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                    ),
                    Text('${_currentPage + 1} / ${state.pages.length}'),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed:
                          _currentPage < state.pages.length - 1 ? () => setState(() => _currentPage++) : null,
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Drag on the page to draw a redaction box. Drag a box to move it, its corner '
                'handle to resize it, or long-press it to remove it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _preview(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(pdfRedactControllerProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Preview', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text(
                    'This is the exact file that will be saved - the selected regions are '
                    'already permanently removed below, not just covered.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 500,
              child: ResultPdfPreview(
                bytesLoader: controller.buildResultBytes,
                sourceName: 'redacted.pdf',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Keep Editing'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      if (!context.mounted) return;
                      await _confirmAndSave(context, ref);
                    },
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndSave(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Permanently redact this PDF?',
      message: 'This permanently removes the selected content from the exported copy. '
          'The original file you picked is not changed, but this cannot be undone '
          'once the redacted copy is saved.',
      confirmLabel: 'Redact & Save',
    );
    if (!confirmed || !context.mounted) return;

    final controller = ref.read(pdfRedactControllerProvider.notifier);
    final saved = await controller.save();
    if (!context.mounted) return;
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Redacted copy saved to Recent Files.')));
    }
  }
}

class _PermanenceBanner extends StatelessWidget {
  const _PermanenceBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Redaction permanently removes the selected content from the exported copy.',
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The interactive page canvas - fits the current page's rasterized image
/// into the available box (same `_fitImageToBox` pattern as Edit PDF's own
/// canvas, `pdf_edit_screen.dart`, itself generalized from
/// `ScanPageEditorScreen`'s precedent), and renders every committed region
/// as a draggable+resizable box on top, plus live drag-to-draw feedback for
/// a brand new region. Unlike Edit PDF's multi-tool canvas, Redact has
/// exactly one interaction mode - drag always draws a new region - so there
/// is no tool-selection state here at all.
class _PdfRedactCanvas extends ConsumerStatefulWidget {
  const _PdfRedactCanvas({required this.page, required this.marks});

  final PdfRedactPage page;
  final List<PdfRedactMark> marks;

  @override
  ConsumerState<_PdfRedactCanvas> createState() => _PdfRedactCanvasState();
}

class _PdfRedactCanvasState extends ConsumerState<_PdfRedactCanvas> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = widget.page.width.toDouble();
        final imageHeight = widget.page.height.toDouble();
        final displaySize = _fitImageToBox(imageWidth, imageHeight, constraints.biggest);

        return Center(
          child: SizedBox(
            width: displaySize.width,
            height: displaySize.height,
            child: GestureDetector(
              onPanStart: (details) => setState(() {
                _dragStart = details.localPosition;
                _dragCurrent = details.localPosition;
              }),
              onPanUpdate: (details) => setState(() => _dragCurrent = details.localPosition),
              onPanEnd: (_) => _handlePanEnd(displaySize),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Image.memory(
                      widget.page.jpegBytes,
                      fit: BoxFit.fill,
                      // Flutter's default (FilterQuality.medium) visibly
                      // softens text when this rasterized page gets scaled
                      // to fit the screen/zoom - independent of the source
                      // raster's own DPI, which is why raising DPI alone
                      // didn't fix reported blurriness. `.high` uses a
                      // better resampling filter for exactly this "scale a
                      // detailed raster image" case.
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  for (final mark in widget.marks)
                    _RedactMarkWidget(mark: mark, displaySize: displaySize),
                  if (_dragStart != null && _dragCurrent != null)
                    Positioned.fromRect(
                      rect: Rect.fromPoints(_dragStart!, _dragCurrent!),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          border: Border.all(color: Colors.redAccent, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePanEnd(Size displaySize) {
    final start = _dragStart;
    final end = _dragCurrent;
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
    if (start == null || end == null) return;
    final rect = Rect.fromPoints(start, end);
    if (rect.width < 4 || rect.height < 4) return; // a stray tap, not a drawn box.

    final controller = ref.read(pdfRedactControllerProvider.notifier);
    controller.addRegion(
      widget.page.pageIndex,
      RedactionRegion(
        x: (rect.left / displaySize.width).clamp(0.0, 1.0),
        y: (rect.top / displaySize.height).clamp(0.0, 1.0),
        width: (rect.width / displaySize.width).clamp(0.0, 1.0),
        height: (rect.height / displaySize.height).clamp(0.0, 1.0),
      ),
    );
  }

  Size _fitImageToBox(double imageWidth, double imageHeight, Size box) {
    final scale = (box.width / imageWidth).clamp(0.0, box.height / imageHeight);
    return Size(imageWidth * scale, imageHeight * scale);
  }
}

/// One drawn redaction region - a solid black box (deliberately opaque, not
/// translucent like Edit PDF's Highlight - nothing about a redaction
/// preview should suggest the content beneath is still faintly visible),
/// draggable to move and resizable via a corner handle, mirroring
/// `_draggableResizable`'s exact pattern in `pdf_edit_screen.dart`.
class _RedactMarkWidget extends ConsumerWidget {
  const _RedactMarkWidget({required this.mark, required this.displaySize});

  final PdfRedactMark mark;
  final Size displaySize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final region = mark.region;
    final left = region.x * displaySize.width;
    final top = region.y * displaySize.height;
    final width = region.width * displaySize.width;
    final height = region.height * displaySize.height;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) {
          final newX = ((left + details.delta.dx) / displaySize.width).clamp(0.0, 1.0);
          final newY = ((top + details.delta.dy) / displaySize.height).clamp(0.0, 1.0);
          ref.read(pdfRedactControllerProvider.notifier).updateRegion(mark.id, region.copyWith(x: newX, y: newY));
        },
        onLongPress: () => ref.read(pdfRedactControllerProvider.notifier).deleteRegion(mark.id),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.redAccent, width: 1.5),
              ),
              child: width > 60 && height > 20
                  ? const Center(
                      child: Text('REDACTED', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1)),
                    )
                  : null,
            ),
            Positioned(
              right: -10,
              bottom: -10,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final newWidth = ((width + details.delta.dx) / displaySize.width).clamp(0.02, 1.0);
                  final newHeight = ((height + details.delta.dy) / displaySize.height).clamp(0.02, 1.0);
                  ref
                      .read(pdfRedactControllerProvider.notifier)
                      .updateRegion(mark.id, region.copyWith(width: newWidth, height: newHeight));
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                  child: const Icon(Icons.open_in_full_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
