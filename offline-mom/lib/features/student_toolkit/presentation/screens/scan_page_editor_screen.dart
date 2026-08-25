import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/toolkit/scan_image_processing_service.dart';
import '../../../../services/toolkit/scanner_pdf_service.dart';
import '../providers/scanner_providers.dart';

/// Full-screen "adjust page" editor for one scanned page - four draggable
/// corner handles double as both "Crop Page" and "Perspective Correction"
/// from the product brief: dragging all four corners into an axis-aligned
/// rectangle *is* a plain crop, and [applyPerspectiveCorrection]'s
/// quad-to-rectangle warp is a strict superset of that - one real,
/// coherent tool rather than two separate screens for what a photographed
/// document actually needs (the common case is genuine perspective skew,
/// not just axis-aligned trimming). Pushed via `Navigator.push` (not a
/// `go_router` route) since it edits state that lives entirely inside the
/// scan session `ScannerController` already owns - not a distinct
/// navigable destination.
class ScanPageEditorScreen extends ConsumerStatefulWidget {
  const ScanPageEditorScreen({super.key, required this.pageId});

  final String pageId;

  @override
  ConsumerState<ScanPageEditorScreen> createState() => _ScanPageEditorScreenState();
}

class _ScanPageEditorScreenState extends ConsumerState<ScanPageEditorScreen> {
  static const double _displayPadding = 24;
  static const double _handleTouchRadius = 22;

  /// Corner positions in *display* coordinates (relative to the image
  /// box's own top-left) - converted to source pixel coordinates only
  /// when actually applying the correction.
  late List<Offset> _corners;
  Size? _displaySize;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final page = state.pages.where((p) => p.id == widget.pageId).firstOrNull;

    if (page == null) {
      return const Scaffold(body: Center(child: Text('This page no longer exists.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust Page'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_90_degrees_cw_rounded),
            tooltip: 'Rotate 90°',
            onPressed: state.isBusy
                ? null
                : () async {
                    await ref
                        .read(scannerControllerProvider.notifier)
                        .rotatePage(page.id, ScanRotation.clockwise90);
                    setState(() {
                      _displaySize = null; // recompute corners for the new dimensions
                    });
                  },
          ),
          TextButton(
            onPressed: _displaySize == null
                ? null
                : () => setState(() => _corners = _fullImageCorners(_displaySize!)),
            child: const Text('Reset'),
          ),
        ],
      ),
      body: state.isBusy
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(_displayPadding),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final displaySize = _fitImageToBox(
                            page.width.toDouble(),
                            page.height.toDouble(),
                            constraints.biggest,
                          );
                          if (_displaySize != displaySize) {
                            _displaySize = displaySize;
                            _corners = _fullImageCorners(displaySize);
                          }
                          return Center(
                            child: SizedBox(
                              width: displaySize.width,
                              height: displaySize.height,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: Image.memory(
                                      page.jpegBytes,
                                      fit: BoxFit.fill,
                                      filterQuality: FilterQuality.high,
                                    ),
                                  ),
                                  CustomPaint(
                                    size: displaySize,
                                    painter: _QuadOverlayPainter(_corners),
                                  ),
                                  for (var i = 0; i < _corners.length; i++)
                                    _cornerHandle(i, displaySize),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Drag the four corners to trace the document\'s edges - the app '
                      'will flatten it into a straight rectangle.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      onPressed: () => _applyAndClose(page),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _cornerHandle(int index, Size displaySize) {
    final corner = _corners[index];
    return Positioned(
      left: corner.dx - _handleTouchRadius,
      top: corner.dy - _handleTouchRadius,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final updated = corner + details.delta;
            _corners[index] = Offset(
              updated.dx.clamp(0.0, displaySize.width),
              updated.dy.clamp(0.0, displaySize.height),
            );
          });
        },
        child: Container(
          width: _handleTouchRadius * 2,
          height: _handleTouchRadius * 2,
          alignment: Alignment.center,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyAndClose(ScannedPage page) async {
    final displaySize = _displaySize!;
    final scaleX = page.width / displaySize.width;
    final scaleY = page.height / displaySize.height;
    final quad = ScanQuad(
      topLeft: ScanPoint(_corners[0].dx * scaleX, _corners[0].dy * scaleY),
      topRight: ScanPoint(_corners[1].dx * scaleX, _corners[1].dy * scaleY),
      bottomRight: ScanPoint(_corners[2].dx * scaleX, _corners[2].dy * scaleY),
      bottomLeft: ScanPoint(_corners[3].dx * scaleX, _corners[3].dy * scaleY),
    );
    await ref.read(scannerControllerProvider.notifier).applyPerspectiveCorrection(page.id, quad);
    if (!mounted) return;
    final error = ref.read(scannerControllerProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop();
  }

  List<Offset> _fullImageCorners(Size size) => [
        const Offset(0, 0),
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ];

  Size _fitImageToBox(double imageWidth, double imageHeight, Size box) {
    final scale = (box.width / imageWidth).clamp(0.0, box.height / imageHeight);
    return Size(imageWidth * scale, imageHeight * scale);
  }
}

class _QuadOverlayPainter extends CustomPainter {
  _QuadOverlayPainter(this.corners);

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amberAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _QuadOverlayPainter oldDelegate) => oldDelegate.corners != corners;
}
