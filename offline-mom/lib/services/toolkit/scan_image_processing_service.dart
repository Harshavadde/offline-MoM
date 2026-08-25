import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_compression_service.dart' show decodeToolkitImageOrThrow, ImageCompressionException;

/// A point in source-image pixel coordinates (not `dart:ui`'s `Offset` -
/// this whole file is pure Dart, unit-testable without a Flutter binding,
/// mirroring `image_compression_service.dart`'s existing discipline).
class ScanPoint {
  const ScanPoint(this.x, this.y);
  final double x;
  final double y;
}

/// The four corners of a document's outline within a captured/imported
/// page image, in source pixel coordinates, going clockwise from the
/// top-left - what the user drags into place over the preview before
/// "Perspective Correction" flattens it into a rectangle. A plain
/// axis-agnostic quadrilateral (not a `Rect`) since a photographed
/// document is essentially never perfectly axis-aligned - that skew is
/// exactly what this feature corrects.
class ScanQuad {
  const ScanQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// A quad covering the full image - the default before the user has
  /// dragged any corner, and a reasonable no-op fallback.
  factory ScanQuad.fullImage(int width, int height) {
    final w = width.toDouble();
    final h = height.toDouble();
    return ScanQuad(
      topLeft: const ScanPoint(0, 0),
      topRight: ScanPoint(w, 0),
      bottomRight: ScanPoint(w, h),
      bottomLeft: ScanPoint(0, h),
    );
  }

  final ScanPoint topLeft;
  final ScanPoint topRight;
  final ScanPoint bottomRight;
  final ScanPoint bottomLeft;
}

enum ScanRotation { none, clockwise90, clockwise180, clockwise270 }

class ScanImageProcessingException implements Exception {
  const ScanImageProcessingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Normalizes a freshly captured/imported image to JPEG (a gallery import
/// could be PNG/WebP/etc.) - every `ScannedPage` downstream of this is
/// always JPEG, so the rest of the Scanner pipeline (rotate/crop/perspective
/// correction/PDF generation) never needs to branch on source format.
Uint8List normalizeScannedPageToJpeg(Uint8List sourceBytes, {int quality = 90}) {
  final image = _decode(sourceBytes);
  return img.encodeJpg(image, quality: quality);
}

/// Rotates a scanned page image by a quarter-turn multiple. Pure rotation,
/// no resampling loss beyond re-encoding (rotation itself is lossless
/// pixel-shuffling for 90-degree multiples).
Uint8List rotateScannedPage(Uint8List jpegBytes, ScanRotation rotation, {int quality = 90}) {
  if (rotation == ScanRotation.none) return jpegBytes;
  final image = _decode(jpegBytes);
  final angle = switch (rotation) {
    ScanRotation.none => 0,
    ScanRotation.clockwise90 => 90,
    ScanRotation.clockwise180 => 180,
    ScanRotation.clockwise270 => 270,
  };
  final rotated = img.copyRotate(image, angle: angle);
  return img.encodeJpg(rotated, quality: quality);
}

/// A plain rectangular crop (no perspective correction) - for the simple
/// "trim the edges" case where the document is already axis-aligned in
/// the photo and a full 4-corner correction would be overkill.
Uint8List cropScannedPage(
  Uint8List jpegBytes,
  int left,
  int top,
  int width,
  int height, {
  int quality = 90,
}) {
  final image = _decode(jpegBytes);
  if (width <= 0 || height <= 0) {
    throw const ScanImageProcessingException('Crop area must be a positive size.');
  }
  final clampedLeft = left.clamp(0, image.width - 1);
  final clampedTop = top.clamp(0, image.height - 1);
  final clampedWidth = math.min(width, image.width - clampedLeft);
  final clampedHeight = math.min(height, image.height - clampedTop);
  final cropped = img.copyCrop(
    image,
    x: clampedLeft,
    y: clampedTop,
    width: clampedWidth,
    height: clampedHeight,
  );
  return img.encodeJpg(cropped, quality: quality);
}

/// Flattens the quadrilateral [quad] (the document's outline within
/// [jpegBytes], in source pixel coordinates) into an axis-aligned
/// rectangle - a real projective (perspective) transform via the classic
/// unit-square-to-quadrilateral closed-form derivation (Heckbert 1989,
/// "Fundamentals of Texture Mapping and Image Warping"; the transform is
/// applied in the *inverse* direction here - unit destination square to
/// the source quad - so every output pixel maps back to exactly one
/// source sample with no resampling holes, the standard technique for
/// this exact problem). Pure Dart, no OpenCV/native dependency - see
/// ADR-034 for why (avoiding another native/licensed dependency after
/// already ruling one out for PDF manipulation).
///
/// Output size defaults to the quad's own average edge lengths (rounded),
/// so a corrected page keeps roughly the proportions the user framed
/// rather than being forced into a fixed size.
Uint8List applyPerspectiveCorrection(
  Uint8List jpegBytes,
  ScanQuad quad, {
  int? outputWidth,
  int? outputHeight,
  int quality = 90,
}) {
  final source = _decode(jpegBytes);
  final size = _resolveOutputSize(quad, outputWidth, outputHeight);
  final mapping = _QuadMapping.forQuad(quad);

  final output = img.Image(width: size.$1, height: size.$2);
  for (var dy = 0; dy < size.$2; dy++) {
    final v = (dy + 0.5) / size.$2;
    for (var dx = 0; dx < size.$1; dx++) {
      final u = (dx + 0.5) / size.$1;
      final sample = mapping.mapUnitSquareToQuad(u, v);
      final pixel = _bilinearSample(source, sample.x, sample.y);
      output.setPixel(dx, dy, pixel);
    }
  }
  return img.encodeJpg(output, quality: quality);
}

img.Image _decode(Uint8List bytes) {
  try {
    return decodeToolkitImageOrThrow(bytes);
  } on ImageCompressionException catch (e) {
    throw ScanImageProcessingException(e.message);
  }
}

(int, int) _resolveOutputSize(ScanQuad quad, int? requestedWidth, int? requestedHeight) {
  if (requestedWidth != null && requestedHeight != null) {
    return (requestedWidth, requestedHeight);
  }
  double dist(ScanPoint a, ScanPoint b) =>
      math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
  final topWidth = dist(quad.topLeft, quad.topRight);
  final bottomWidth = dist(quad.bottomLeft, quad.bottomRight);
  final leftHeight = dist(quad.topLeft, quad.bottomLeft);
  final rightHeight = dist(quad.topRight, quad.bottomRight);
  final width = ((topWidth + bottomWidth) / 2).round().clamp(1, 10000);
  final height = ((leftHeight + rightHeight) / 2).round().clamp(1, 10000);
  return (width, height);
}

img.Color _bilinearSample(img.Image image, double x, double y) {
  final clampedX = x.clamp(0.0, image.width - 1.0);
  final clampedY = y.clamp(0.0, image.height - 1.0);
  final x0 = clampedX.floor();
  final y0 = clampedY.floor();
  final x1 = math.min(x0 + 1, image.width - 1);
  final y1 = math.min(y0 + 1, image.height - 1);
  final fx = clampedX - x0;
  final fy = clampedY - y0;

  final p00 = image.getPixel(x0, y0);
  final p10 = image.getPixel(x1, y0);
  final p01 = image.getPixel(x0, y1);
  final p11 = image.getPixel(x1, y1);

  double lerp(num a, num b, double t) => a + (b - a) * t;
  double channel(num c00, num c10, num c01, num c11) {
    final top = lerp(c00, c10, fx);
    final bottom = lerp(c01, c11, fx);
    return lerp(top, bottom, fy);
  }

  return img.ColorRgb8(
    channel(p00.r, p10.r, p01.r, p11.r).round(),
    channel(p00.g, p10.g, p01.g, p11.g).round(),
    channel(p00.b, p10.b, p01.b, p11.b).round(),
  );
}

/// The closed-form unit-square-to-quadrilateral projective mapping
/// (Heckbert 1989). Given normalized `(u, v)` in `[0, 1] x [0, 1]`
/// representing corners `(0,0)->P0, (1,0)->P1, (1,1)->P2, (0,1)->P3`,
/// returns the corresponding point inside the quad `P0..P3`.
class _QuadMapping {
  const _QuadMapping._(this._a, this._b, this._c, this._d, this._e, this._f, this._g, this._h);

  factory _QuadMapping.forQuad(ScanQuad quad) {
    final x0 = quad.topLeft.x, y0 = quad.topLeft.y;
    final x1 = quad.topRight.x, y1 = quad.topRight.y;
    final x2 = quad.bottomRight.x, y2 = quad.bottomRight.y;
    final x3 = quad.bottomLeft.x, y3 = quad.bottomLeft.y;

    final dx1 = x1 - x2, dx2 = x3 - x2, sx = x0 - x1 + x2 - x3;
    final dy1 = y1 - y2, dy2 = y3 - y2, sy = y0 - y1 + y2 - y3;

    final denom = dx1 * dy2 - dx2 * dy1;
    double g, h;
    if (denom.abs() < 1e-9) {
      // Degenerate to an affine map (the quad's opposite sides are
      // parallel enough that no genuine perspective term is needed) -
      // avoids a division by ~0 that would otherwise blow up the mapping.
      g = 0;
      h = 0;
    } else {
      g = (sx * dy2 - dx2 * sy) / denom;
      h = (dx1 * sy - sx * dy1) / denom;
    }

    final a = x1 - x0 + g * x1;
    final b = x3 - x0 + h * x3;
    final c = x0;
    final d = y1 - y0 + g * y1;
    final e = y3 - y0 + h * y3;
    final f = y0;

    return _QuadMapping._(a, b, c, d, e, f, g, h);
  }

  final double _a, _b, _c, _d, _e, _f, _g, _h;

  ScanPoint mapUnitSquareToQuad(double u, double v) {
    final denom = _g * u + _h * v + 1;
    final x = (_a * u + _b * v + _c) / denom;
    final y = (_d * u + _e * v + _f) / denom;
    return ScanPoint(x, y);
  }
}

/// `compute()`-passable request wrapping [applyPerspectiveCorrection]'s
/// arguments - `ScannerController` runs page edits through `compute()`
/// since the per-destination-pixel resampling loop is genuine, non-trivial
/// CPU work that shouldn't block the UI isolate, mirroring
/// `ImageCompressionService`'s existing `compute()`-wrapped-request
/// convention.
class PerspectiveCorrectionRequest {
  const PerspectiveCorrectionRequest({
    required this.jpegBytes,
    required this.quad,
    this.outputWidth,
    this.outputHeight,
    this.quality = 90,
  });

  final Uint8List jpegBytes;
  final ScanQuad quad;
  final int? outputWidth;
  final int? outputHeight;
  final int quality;
}

Uint8List runPerspectiveCorrection(PerspectiveCorrectionRequest request) =>
    applyPerspectiveCorrection(
      request.jpegBytes,
      request.quad,
      outputWidth: request.outputWidth,
      outputHeight: request.outputHeight,
      quality: request.quality,
    );

class CropRequest {
  const CropRequest({
    required this.jpegBytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.quality = 90,
  });

  final Uint8List jpegBytes;
  final int left;
  final int top;
  final int width;
  final int height;
  final int quality;
}

Uint8List runCrop(CropRequest request) => cropScannedPage(
      request.jpegBytes,
      request.left,
      request.top,
      request.width,
      request.height,
      quality: request.quality,
    );
