import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/toolkit/scan_image_processing_service.dart';

/// A synthetic image with a distinct solid color in each quadrant, so a
/// perspective/crop transform's correctness can be checked by sampling
/// specific pixels rather than just checking dimensions.
Uint8List _quadrantImage({int width = 400, int height = 300}) {
  final image = img.Image(width: width, height: height);
  final halfW = width ~/ 2;
  final halfH = height ~/ 2;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final img.Color color;
      if (x < halfW && y < halfH) {
        color = img.ColorRgb8(255, 0, 0); // top-left: red
      } else if (x >= halfW && y < halfH) {
        color = img.ColorRgb8(0, 255, 0); // top-right: green
      } else if (x < halfW && y >= halfH) {
        color = img.ColorRgb8(0, 0, 255); // bottom-left: blue
      } else {
        color = img.ColorRgb8(255, 255, 0); // bottom-right: yellow
      }
      image.setPixel(x, y, color);
    }
  }
  return img.encodeJpg(image, quality: 100);
}

void main() {
  group('applyPerspectiveCorrection', () {
    test('an identity quad (full image, axis-aligned) reproduces the '
        'source layout at the requested output size', () {
      final source = _quadrantImage();
      final quad = ScanQuad.fullImage(400, 300);

      final result = applyPerspectiveCorrection(
        source,
        quad,
        outputWidth: 400,
        outputHeight: 300,
      );

      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 400);
      expect(decoded.height, 300);
      // Sample well inside each quadrant (avoiding the exact boundary,
      // where bilinear sampling blends adjacent colors).
      expect(decoded.getPixel(50, 50).r, greaterThan(200)); // red quadrant
      expect(decoded.getPixel(350, 50).g, greaterThan(200)); // green quadrant
      expect(decoded.getPixel(50, 250).b, greaterThan(200)); // blue quadrant
      expect(decoded.getPixel(350, 250).r, greaterThan(200)); // yellow quadrant
      expect(decoded.getPixel(350, 250).g, greaterThan(200));
    });

    test('an axis-aligned sub-rectangle quad extracts just that region, '
        'equivalent to a crop', () {
      final source = _quadrantImage();
      // Just the top-left (red) quadrant, as a quad.
      const quad = ScanQuad(
        topLeft: ScanPoint(0, 0),
        topRight: ScanPoint(200, 0),
        bottomRight: ScanPoint(200, 150),
        bottomLeft: ScanPoint(0, 150),
      );

      final result = applyPerspectiveCorrection(
        source,
        quad,
        outputWidth: 200,
        outputHeight: 150,
      );

      final decoded = img.decodeJpg(result)!;
      // Every corner should now be red - the whole output is what used to
      // be only the top-left quadrant.
      expect(decoded.getPixel(10, 10).r, greaterThan(200));
      expect(decoded.getPixel(190, 10).r, greaterThan(200));
      expect(decoded.getPixel(10, 140).r, greaterThan(200));
      expect(decoded.getPixel(190, 140).r, greaterThan(200));
    });

    test('output size defaults to the quad\'s own average edge lengths '
        'when not explicitly requested', () {
      final source = _quadrantImage();
      const quad = ScanQuad(
        topLeft: ScanPoint(0, 0),
        topRight: ScanPoint(100, 0),
        bottomRight: ScanPoint(100, 50),
        bottomLeft: ScanPoint(0, 50),
      );

      final result = applyPerspectiveCorrection(source, quad);
      final decoded = img.decodeJpg(result)!;

      expect(decoded.width, 100);
      expect(decoded.height, 50);
    });

    test('a genuinely skewed (non-axis-aligned) quad still produces a '
        'valid, correctly-sized, decodable image', () {
      final source = _quadrantImage();
      // A trapezoid - top edge narrower than the bottom, simulating a
      // photographed page tilted away from the camera at the top.
      const quad = ScanQuad(
        topLeft: ScanPoint(80, 20),
        topRight: ScanPoint(320, 40),
        bottomRight: ScanPoint(360, 280),
        bottomLeft: ScanPoint(40, 260),
      );

      final result = applyPerspectiveCorrection(
        source,
        quad,
        outputWidth: 300,
        outputHeight: 400,
      );

      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 300);
      expect(decoded.height, 400);
      // The quad's own top-left corner (80,20) sits in the source image's
      // red quadrant (x<200, y<150) - the output's own top-left corner
      // should sample from near there.
      expect(decoded.getPixel(2, 2).r, greaterThan(200));
    });

    test('throws a clear exception for undecodable bytes, not a crash', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => applyPerspectiveCorrection(garbage, ScanQuad.fullImage(10, 10)),
        throwsA(isA<ScanImageProcessingException>()),
      );
    });
  });

  group('rotateScannedPage', () {
    test('a 90-degree rotation swaps width and height', () {
      final source = _quadrantImage(width: 400, height: 300);
      final rotated = rotateScannedPage(source, ScanRotation.clockwise90);
      final decoded = img.decodeJpg(rotated)!;
      expect(decoded.width, 300);
      expect(decoded.height, 400);
    });

    test('a 180-degree rotation keeps the same dimensions', () {
      final source = _quadrantImage(width: 400, height: 300);
      final rotated = rotateScannedPage(source, ScanRotation.clockwise180);
      final decoded = img.decodeJpg(rotated)!;
      expect(decoded.width, 400);
      expect(decoded.height, 300);
    });

    test('ScanRotation.none returns the exact same bytes untouched', () {
      final source = _quadrantImage();
      final result = rotateScannedPage(source, ScanRotation.none);
      expect(result, same(source));
    });
  });

  group('cropScannedPage', () {
    test('crops to the requested region', () {
      final source = _quadrantImage(width: 400, height: 300);
      final result = cropScannedPage(source, 0, 0, 200, 150);
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 200);
      expect(decoded.height, 150);
      expect(decoded.getPixel(10, 10).r, greaterThan(200)); // still red quadrant
    });

    test('clamps a crop region that extends past the image bounds', () {
      final source = _quadrantImage(width: 400, height: 300);
      final result = cropScannedPage(source, 350, 250, 200, 200);
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, lessThanOrEqualTo(50));
      expect(decoded.height, lessThanOrEqualTo(50));
    });

    test('throws for a non-positive crop size', () {
      final source = _quadrantImage();
      expect(
        () => cropScannedPage(source, 0, 0, 0, 100),
        throwsA(isA<ScanImageProcessingException>()),
      );
    });
  });
}
