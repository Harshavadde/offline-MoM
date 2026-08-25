import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../../../providers/app_providers.dart';
import '../../../../services/toolkit/pdf_overlay.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/result_pdf_preview.dart';
import '../../../../shared/widgets/text_input_dialog.dart';
import '../providers/pdf_edit_providers.dart';
import '../widgets/signature_pad_dialog.dart';

/// PDF Edit (Productivity Toolkit productization pass, P0-3) - Add Text,
/// Signatures, Annotations, and Watermark, all built on the shared
/// `PdfOverlayElement`/`PdfOverlayService` foundation (P0-2/ADR-040), per
/// the productization audit's own explicit "one primitive, not five
/// features" recommendation.
///
/// Never destroys the original document until the user explicitly saves -
/// [PdfEditController] holds every placed annotation purely in memory
/// (`PdfEditState.annotationsByPage`) until `save()` is called, and even
/// then writes a *new* file - the source PDF the user picked is never
/// opened for writing.
class PdfEditScreen extends ConsumerStatefulWidget {
  const PdfEditScreen({super.key});

  @override
  ConsumerState<PdfEditScreen> createState() => _PdfEditScreenState();
}

class _PdfEditScreenState extends ConsumerState<PdfEditScreen> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfEditControllerProvider);

    ref.listen(pdfEditControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    if (state.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit PDF')),
        body: Center(
          child: EmptyState(
            icon: Icons.edit_document,
            title: 'Add text, signatures & annotations',
            message: 'Pick a PDF to start editing - nothing is changed until you '
                'explicitly save.',
            actionLabel: 'Choose PDF',
            onAction: () => ref.read(pdfEditControllerProvider.notifier).pickPdf(),
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
        title: Text(state.pages.length > 1 ? 'Page ${_currentPage + 1} of ${state.pages.length}' : 'Edit PDF'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Undo',
            onPressed: state.canUndo ? () => ref.read(pdfEditControllerProvider.notifier).undo() : null,
          ),
          IconButton(
            icon: const Icon(Icons.branding_watermark_outlined),
            tooltip: 'Watermark',
            onPressed: () => _showWatermarkDialog(context, ref),
          ),
          TextButton(
            onPressed: state.totalAnnotationCount == 0 || state.isBusy ? null : () => _preview(context, ref),
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: page == null
                  ? const Center(child: Text('This page could not be loaded.'))
                  : _PdfEditCanvas(
                      page: page,
                      annotations: state.annotationsByPage[_currentPage] ?? const [],
                      activeTool: state.activeTool,
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
            _PdfEditToolbar(
              activeTool: state.activeTool,
              onSelect: (tool) => _onSelectTool(context, ref, tool),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSelectTool(BuildContext context, WidgetRef ref, PdfEditTool tool) async {
    final controller = ref.read(pdfEditControllerProvider.notifier);
    if (tool == PdfEditTool.text) {
      final text = await showTextInputDialog(context, title: 'Add text', labelText: 'Text');
      if (text == null || text.trim().isEmpty) return;
      controller.addAnnotation(
        _currentPage,
        PdfOverlayText(text: text.trim(), x: 0.3, y: 0.3, fontSize: 18),
      );
      return;
    }
    if (tool == PdfEditTool.signature) {
      if (!context.mounted) return;
      await _showSignatureSheet(context, ref);
      return;
    }
    controller.selectTool(tool);
  }

  Future<void> _showSignatureSheet(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.draw_rounded),
              title: const Text('Draw signature'),
              onTap: () => Navigator.of(context).pop('draw'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('Type signature'),
              onTap: () => Navigator.of(context).pop('type'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Import image'),
              onTap: () => Navigator.of(context).pop('import'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    final controller = ref.read(pdfEditControllerProvider.notifier);
    switch (choice) {
      case 'draw':
        final bytes = await showSignaturePadDialog(context);
        if (bytes == null) return;
        controller.addAnnotation(
          _currentPage,
          PdfOverlayImage(bytes: bytes, x: 0.3, y: 0.6, width: 0.35, height: 0.12),
        );
      case 'type':
        if (!context.mounted) return;
        final text = await showTextInputDialog(context, title: 'Type signature', labelText: 'Full name');
        if (text == null || text.trim().isEmpty) return;
        controller.addAnnotation(
          _currentPage,
          PdfOverlayText(text: text.trim(), x: 0.3, y: 0.6, fontSize: 26, italic: true),
        );
      case 'import':
        final picked = await ref.read(toolkitImagePickerServiceProvider).pickFromGallery();
        if (picked == null) return;
        controller.addAnnotation(
          _currentPage,
          PdfOverlayImage(bytes: picked.bytes, x: 0.3, y: 0.6, width: 0.35, height: 0.12),
        );
    }
  }

  Future<void> _showWatermarkDialog(BuildContext context, WidgetRef ref) async {
    final text = await showTextInputDialog(
      context,
      title: 'Add watermark',
      labelText: 'Watermark text',
      helperText: 'Applied diagonally, semi-transparent, to every page.',
    );
    if (text == null || text.trim().isEmpty) return;
    ref.read(pdfEditControllerProvider.notifier).applyWatermark(text.trim());
  }

  Future<void> _preview(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(pdfEditControllerProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Preview', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 500,
              child: ResultPdfPreview(
                bytesLoader: controller.buildResultBytes,
                sourceName: 'edited.pdf',
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
                      final saved = await controller.save();
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      if (saved != null && context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Saved to Recent Files.')));
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfEditToolbar extends StatelessWidget {
  const _PdfEditToolbar({required this.activeTool, required this.onSelect});

  final PdfEditTool activeTool;
  final void Function(PdfEditTool tool) onSelect;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (PdfEditTool.text, Icons.text_fields_rounded, 'Text'),
      (PdfEditTool.signature, Icons.draw_outlined, 'Signature'),
      (PdfEditTool.highlight, Icons.border_color_rounded, 'Highlight'),
      (PdfEditTool.underline, Icons.format_underlined_rounded, 'Underline'),
      (PdfEditTool.strikethrough, Icons.strikethrough_s_rounded, 'Strike'),
      (PdfEditTool.freehand, Icons.gesture_rounded, 'Draw'),
      (PdfEditTool.rectangle, Icons.crop_square_rounded, 'Shape'),
      (PdfEditTool.arrow, Icons.north_east_rounded, 'Arrow'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final (tool, icon, label) in tools)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: _ToolButton(
                icon: icon,
                label: label,
                isActive: activeTool == tool,
                activeColor: scheme.primary,
                onTap: () => onSelect(tool),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(12),
          border: isActive ? Border.all(color: activeColor, width: 1.5) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? activeColor : scheme.onSurfaceVariant, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive ? activeColor : scheme.onSurfaceVariant,
                    fontWeight: isActive ? FontWeight.w600 : null,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// The interactive page canvas - fits the current page's rasterized image
/// into the available box (mirrors `ScanPageEditorScreen`'s exact
/// `_fitImageToBox` pattern, the established precedent in this codebase
/// for screen-space <-> source-space coordinate conversion), then renders
/// every committed annotation on top as a draggable (and, for images,
/// resizable) widget, plus live in-progress feedback for drag-to-draw
/// tools (highlight/underline/strikethrough/rectangle/arrow/freehand).
///
/// Every annotation's *stored* position/size is normalized (0.0-1.0,
/// `PdfOverlayElement`'s own contract) - screen-space drag deltas are
/// converted to normalized deltas by dividing by the current display
/// size, so placement is correct regardless of the page's own pixel
/// dimensions, the device's screen size, or how large the canvas happens
/// to be laid out at (there is no separate "zoom" control in this pass -
/// the canvas always fits the full page to the available box, so
/// "zoom level" and "display size" are the same thing here).
class _PdfEditCanvas extends ConsumerStatefulWidget {
  const _PdfEditCanvas({required this.page, required this.annotations, required this.activeTool});

  final PdfEditPage page;
  final List<PdfEditAnnotation> annotations;
  final PdfEditTool activeTool;

  @override
  ConsumerState<_PdfEditCanvas> createState() => _PdfEditCanvasState();
}

class _PdfEditCanvasState extends ConsumerState<_PdfEditCanvas> {
  Offset? _dragStart;
  Offset? _dragCurrent;
  List<Offset> _freehandPoints = [];

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
              onTapUp: (details) => _handleTap(details.localPosition, displaySize),
              onPanStart: (details) => _handlePanStart(details.localPosition),
              onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
              onPanEnd: (_) => _handlePanEnd(displaySize),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Image.memory(
                      widget.page.jpegBytes,
                      fit: BoxFit.fill,
                      // See pdf_redact_screen.dart's identical comment -
                      // the default filter visibly softens text when this
                      // rasterized page is scaled, independent of source DPI.
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  for (final annotation in widget.annotations)
                    _AnnotationWidget(annotation: annotation, displaySize: displaySize),
                  if (_dragStart != null && _dragCurrent != null && _isDragTool(widget.activeTool))
                    CustomPaint(
                      size: displaySize,
                      painter: _LivePreviewPainter(
                        tool: widget.activeTool,
                        start: _dragStart!,
                        current: _dragCurrent!,
                        freehandPoints: _freehandPoints,
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

  bool _isDragTool(PdfEditTool tool) => switch (tool) {
        PdfEditTool.highlight ||
        PdfEditTool.underline ||
        PdfEditTool.strikethrough ||
        PdfEditTool.freehand ||
        PdfEditTool.rectangle ||
        PdfEditTool.arrow =>
          true,
        _ => false,
      };

  void _handleTap(Offset position, Size displaySize) {
    // Point-placement tools (Text/Signature) are handled by their own
    // dialogs from the toolbar, never a bare canvas tap - avoids an
    // accidental tap creating an empty/default annotation with no
    // content to confirm first.
  }

  void _handlePanStart(Offset position) {
    if (!_isDragTool(widget.activeTool)) return;
    setState(() {
      _dragStart = position;
      _dragCurrent = position;
      _freehandPoints = [position];
    });
  }

  void _handlePanUpdate(Offset position) {
    if (_dragStart == null) return;
    setState(() {
      _dragCurrent = position;
      if (widget.activeTool == PdfEditTool.freehand) _freehandPoints.add(position);
    });
  }

  void _handlePanEnd(Size displaySize) {
    final start = _dragStart;
    final end = _dragCurrent;
    if (start == null || end == null) return;
    final controller = ref.read(pdfEditControllerProvider.notifier);
    final pageIndex = widget.page.pageIndex;

    switch (widget.activeTool) {
      case PdfEditTool.highlight:
        final rect = Rect.fromPoints(start, end);
        if (rect.width > 4 && rect.height > 4) {
          controller.addAnnotation(
            pageIndex,
            PdfOverlayRect(
              x: rect.left / displaySize.width,
              y: rect.top / displaySize.height,
              width: rect.width / displaySize.width,
              height: rect.height / displaySize.height,
              color: const PdfColor(1, 0.92, 0.23, 0.4),
            ),
          );
        }
      case PdfEditTool.underline:
      case PdfEditTool.strikethrough:
        final y = widget.activeTool == PdfEditTool.strikethrough
            ? (start.dy + end.dy) / 2 / displaySize.height
            : end.dy / displaySize.height;
        controller.addAnnotation(
          pageIndex,
          PdfOverlayLine(
            points: [
              (start.dx / displaySize.width, y),
              (end.dx / displaySize.width, y),
            ],
            color: widget.activeTool == PdfEditTool.strikethrough ? PdfColors.red : PdfColors.black,
            strokeWidth: 1.5,
          ),
        );
      case PdfEditTool.freehand:
        if (_freehandPoints.length > 1) {
          controller.addAnnotation(
            pageIndex,
            PdfOverlayLine(
              points: [for (final p in _freehandPoints) (p.dx / displaySize.width, p.dy / displaySize.height)],
              color: PdfColors.blue,
              strokeWidth: 2.5,
            ),
          );
        }
      case PdfEditTool.rectangle:
        final rect = Rect.fromPoints(start, end);
        if (rect.width > 4 && rect.height > 4) {
          controller.addAnnotation(
            pageIndex,
            PdfOverlayRect(
              x: rect.left / displaySize.width,
              y: rect.top / displaySize.height,
              width: rect.width / displaySize.width,
              height: rect.height / displaySize.height,
              color: PdfColors.deepPurple,
              filled: false,
              strokeWidth: 2,
            ),
          );
        }
      case PdfEditTool.arrow:
        if ((end - start).distance > 8) {
          controller.addAnnotation(pageIndex, _buildArrow(start, end, displaySize));
        }
      case PdfEditTool.text:
      case PdfEditTool.signature:
      case PdfEditTool.none:
        break;
    }

    setState(() {
      _dragStart = null;
      _dragCurrent = null;
      _freehandPoints = [];
    });
  }

  /// One continuous polyline (shaft + two short back-angled segments at
  /// the tip) - a real arrowhead built from the same `PdfOverlayLine`
  /// primitive every other line-based annotation already uses, not a new
  /// element type. The pen draws start -> end (the shaft), then jumps
  /// back to the tip to draw each barb - imperceptible for a solid
  /// stroke, since the "jump" retraces a point already drawn.
  PdfOverlayLine _buildArrow(Offset start, Offset end, Size displaySize) {
    final direction = (end - start);
    final length = direction.distance;
    final unit = direction / length;
    final barbLength = (length * 0.25).clamp(8.0, 24.0);
    // Perpendicular-ish barbs at +/-25 degrees from the reversed shaft.
    Offset rotate(Offset v, double radians) {
      final cos = _cos(radians);
      final sin = _sin(radians);
      return Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos);
    }

    final back = -unit;
    final barbLeft = end + rotate(back, 0.45) * barbLength;
    final barbRight = end + rotate(back, -0.45) * barbLength;

    Offset toNormalized(Offset p) => Offset(p.dx / displaySize.width, p.dy / displaySize.height);
    final points = [start, end, barbLeft, end, barbRight].map(toNormalized).map((o) => (o.dx, o.dy)).toList();
    return PdfOverlayLine(points: points, color: PdfColors.deepOrange, strokeWidth: 2.5);
  }

  static double _cos(double radians) => 1 - (radians * radians) / 2 + (radians * radians * radians * radians) / 24;
  static double _sin(double radians) => radians - (radians * radians * radians) / 6;

  Size _fitImageToBox(double imageWidth, double imageHeight, Size box) {
    final scale = (box.width / imageWidth).clamp(0.0, box.height / imageHeight);
    return Size(imageWidth * scale, imageHeight * scale);
  }
}

/// One placed annotation, rendered as a draggable (image annotations also
/// resizable, via a bottom-right corner handle) widget over the page -
/// mirrors `ScanPageEditorScreen`'s corner-handle drag pattern, generalized
/// from "4 fixed corners of one quad" to "any number of independent
/// annotations, each its own drag target."
class _AnnotationWidget extends ConsumerWidget {
  const _AnnotationWidget({required this.annotation, required this.displaySize});

  final PdfEditAnnotation annotation;
  final Size displaySize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final element = annotation.element;
    return switch (element) {
      PdfOverlayText() => _draggable(
          ref,
          x: element.x,
          y: element.y,
          child: Text(
            element.text,
            style: TextStyle(
              fontSize: element.fontSize,
              color: Color(element.color.toInt()),
              fontStyle: element.italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          onDragEnd: (dx, dy) => _updatePosition(ref, element.copyWith(x: dx, y: dy)),
        ),
      PdfOverlayImage() => _draggableResizable(ref, element),
      PdfOverlayRect() || PdfOverlayLine() => const SizedBox.shrink(), // committed via drag-to-draw only, not re-editable this pass
    };
  }

  Widget _draggable(
    WidgetRef ref, {
    required double x,
    required double y,
    required Widget child,
    required void Function(double dx, double dy) onDragEnd,
  }) {
    return Positioned(
      left: x * displaySize.width,
      top: y * displaySize.height,
      child: GestureDetector(
        onPanUpdate: (details) {
          final newX = ((x * displaySize.width) + details.delta.dx) / displaySize.width;
          final newY = ((y * displaySize.height) + details.delta.dy) / displaySize.height;
          onDragEnd(newX.clamp(0.0, 1.0), newY.clamp(0.0, 1.0));
        },
        onLongPress: () => ref.read(pdfEditControllerProvider.notifier).deleteAnnotation(annotation.id),
        child: child,
      ),
    );
  }

  Widget _draggableResizable(WidgetRef ref, PdfOverlayImage element) {
    final left = element.x * displaySize.width;
    final top = element.y * displaySize.height;
    final width = element.width * displaySize.width;
    final height = element.height * displaySize.height;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) {
          final newX = ((left + details.delta.dx) / displaySize.width).clamp(0.0, 1.0);
          final newY = ((top + details.delta.dy) / displaySize.height).clamp(0.0, 1.0);
          ref
              .read(pdfEditControllerProvider.notifier)
              .updateAnnotation(annotation.id, PdfOverlayImage(bytes: element.bytes, x: newX, y: newY, width: element.width, height: element.height));
        },
        onLongPress: () => ref.read(pdfEditControllerProvider.notifier).deleteAnnotation(annotation.id),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(width: width, height: height, child: Image.memory(element.bytes, fit: BoxFit.contain)),
            Positioned(
              right: -10,
              bottom: -10,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final newWidth = ((width + details.delta.dx) / displaySize.width).clamp(0.05, 1.0);
                  final newHeight = ((height + details.delta.dy) / displaySize.height).clamp(0.05, 1.0);
                  ref.read(pdfEditControllerProvider.notifier).updateAnnotation(
                        annotation.id,
                        PdfOverlayImage(bytes: element.bytes, x: element.x, y: element.y, width: newWidth, height: newHeight),
                      );
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent),
                  child: const Icon(Icons.open_in_full_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updatePosition(WidgetRef ref, PdfOverlayText updated) {
    ref.read(pdfEditControllerProvider.notifier).updateAnnotation(annotation.id, updated);
  }
}

class _LivePreviewPainter extends CustomPainter {
  _LivePreviewPainter({required this.tool, required this.start, required this.current, required this.freehandPoints});

  final PdfEditTool tool;
  final Offset start;
  final Offset current;
  final List<Offset> freehandPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    switch (tool) {
      case PdfEditTool.highlight:
        canvas.drawRect(Rect.fromPoints(start, current), paint..color = Colors.blueAccent.withValues(alpha: 0.3)..style = PaintingStyle.fill);
      case PdfEditTool.rectangle:
        canvas.drawRect(Rect.fromPoints(start, current), paint);
      case PdfEditTool.underline:
      case PdfEditTool.strikethrough:
      case PdfEditTool.arrow:
        canvas.drawLine(start, current, paint);
      case PdfEditTool.freehand:
        for (var i = 0; i < freehandPoints.length - 1; i++) {
          canvas.drawLine(freehandPoints[i], freehandPoints[i + 1], paint);
        }
      case PdfEditTool.text:
      case PdfEditTool.signature:
      case PdfEditTool.none:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LivePreviewPainter oldDelegate) => true;
}
