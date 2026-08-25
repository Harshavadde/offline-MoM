import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Draw-signature capture (Productivity Toolkit productization pass, P0-3,
/// Signatures #24-25) - a full-screen dialog capturing one or more
/// finger/stylus strokes, rendered to a transparent-background PNG (never
/// JPEG, which has no alpha channel - the signature must show *through*
/// to the page underneath once placed) via `package:image`'s own drawing
/// primitives, the same dependency already used everywhere else in this
/// app's image pipeline (Compress/Resize/Scanner) - no new dependency.
///
/// Returns null if the user cancels without drawing anything meaningful;
/// otherwise the encoded PNG bytes, ready to become a [PdfOverlayImage].
Future<Uint8List?> showSignaturePadDialog(BuildContext context) {
  return showDialog<Uint8List>(
    context: context,
    builder: (context) => const Dialog(
      insetPadding: EdgeInsets.all(16),
      child: _SignaturePadContent(),
    ),
  );
}

class _SignaturePadContent extends StatefulWidget {
  const _SignaturePadContent();

  @override
  State<_SignaturePadContent> createState() => _SignaturePadContentState();
}

class _SignaturePadContentState extends State<_SignaturePadContent> {
  // One sublist per continuous stroke (a pen-up/pen-down boundary) - drawn
  // as separate line segments so lifting and starting a new stroke never
  // draws a spurious connecting line between them.
  final List<List<Offset>> _strokes = [];
  Size? _padSize;

  bool get _hasContent => _strokes.any((s) => s.length > 1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Draw your signature', style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(
                onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 2,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _padSize = constraints.biggest;
                return GestureDetector(
                  onPanStart: (details) => setState(() => _strokes.add([details.localPosition])),
                  onPanUpdate: (details) => setState(() => _strokes.last.add(details.localPosition)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: CustomPaint(painter: _SignaturePainter(_strokes, scheme.onSurface)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _hasContent ? _done : null,
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _done() {
    final size = _padSize;
    if (size == null) return;
    final bytes = _renderToPng(_strokes, size);
    Navigator.of(context).pop(bytes);
  }

  static Uint8List _renderToPng(List<List<Offset>> strokes, Size size) {
    final image = img.Image(
      width: size.width.round().clamp(1, 4096),
      height: size.height.round().clamp(1, 4096),
      numChannels: 4,
    );
    // Fully transparent canvas - the whole point of a signature overlay
    // is that only the ink itself is opaque, everything else lets the
    // page underneath show through once placed.
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    final ink = img.ColorRgba8(20, 20, 20, 255);
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        img.drawLine(
          image,
          x1: stroke[i].dx.round(),
          y1: stroke[i].dy.round(),
          x2: stroke[i + 1].dx.round(),
          y2: stroke[i + 1].dy.round(),
          color: ink,
          thickness: 3,
          antialias: true,
        );
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, this.color);
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => oldDelegate.strokes != strokes;
}
