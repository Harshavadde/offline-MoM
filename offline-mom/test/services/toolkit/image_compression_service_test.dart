import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/toolkit/image_compression_service.dart';

/// A synthetic photo-like source image - a gradient plus noise-ish pattern
/// (not a flat color) so JPEG's DCT compression actually has real
/// high-frequency detail to discard as quality drops, the same way a real
/// photo would. A flat-color image compresses to a few hundred bytes at
/// any quality, which would make every quality level look identical and
/// defeat the point of testing the target-size search.
Uint8List _syntheticPhotoBytes({int width = 800, int height = 600}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (x * 255 ~/ width);
      final g = (y * 255 ~/ height);
      final b = ((x ^ y) % 256);
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return img.encodeJpg(image, quality: 100);
}

void main() {
  late Uint8List sourceBytes;

  setUpAll(() {
    sourceBytes = _syntheticPhotoBytes();
  });

  group('compressImage - target size', () {
    test('reaches a target well below the source size', () {
      const target = 20 * 1024;
      final result = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
          targetSizeBytes: target,
        ),
      );

      expect(result.reachedTarget, isTrue);
      expect(result.resultSizeBytes, lessThanOrEqualTo(target));
      expect(result.originalSizeBytes, sourceBytes.lengthInBytes);
    });

    test('picks the highest quality that still fits - result should be a '
        'meaningful fraction of the target, not far under it', () {
      const target = 30 * 1024;
      final result = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
          targetSizeBytes: target,
        ),
      );

      expect(result.reachedTarget, isTrue);
      expect(result.resultSizeBytes, lessThanOrEqualTo(target));
      // A binary search for the *highest* fitting quality should land
      // reasonably close to the target, not drastically under it (which
      // would suggest the search picked a far-too-low quality).
      expect(result.resultSizeBytes, greaterThan(target * 0.4));
    });

    test('an unreachably small target still returns a result, honestly '
        'flagged as not having reached it', () {
      const target = 50; // 50 bytes - no real photo can hit this.
      final result = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
          targetSizeBytes: target,
        ),
      );

      expect(result.reachedTarget, isFalse);
      expect(result.bytes, isNotEmpty);
      // Still decodable - a real, if not-small-enough, JPEG, not garbage.
      expect(img.decodeImage(result.bytes), isNotNull);
    });

    test('downscales when quality alone cannot reach a small target on a '
        'large source - result dimensions shrink from the original', () {
      final largeSource = _syntheticPhotoBytes(width: 2000, height: 1500);
      const target = 15 * 1024;
      final result = compressImage(
        ImageCompressionRequest(
          sourceBytes: largeSource,
          outputFormat: ImageOutputFormat.jpg,
          targetSizeBytes: target,
        ),
      );

      expect(result.resultSizeBytes, lessThanOrEqualTo(target));
      expect(result.width, lessThan(2000));
      expect(result.height, lessThan(1500));
    });
  });

  group('compressImage - explicit quality (no target)', () {
    test('a lower quality produces a smaller file than a higher one', () {
      final low = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
          quality: 20,
        ),
      );
      final high = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
          quality: 90,
        ),
      );

      expect(low.reachedTarget, isTrue);
      expect(low.resultSizeBytes, lessThan(high.resultSizeBytes));
    });
  });

  group('compressImage - resolution cap', () {
    test('maxWidth/maxHeight downscale before encoding', () {
      final result = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
          quality: 90,
          maxWidth: 200,
          maxHeight: 200,
        ),
      );

      expect(result.width, lessThanOrEqualTo(200));
      expect(result.height, lessThanOrEqualTo(200));
    });

    test('never upscales - a cap larger than the source leaves it unchanged',
        () {
      final result = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
          quality: 90,
          maxWidth: 5000,
          maxHeight: 5000,
        ),
      );

      expect(result.width, 800);
      expect(result.height, 600);
    });
  });

  group('compressImage - PNG (lossless)', () {
    test('always reports reachedTarget true - never lossily forced to fit',
        () {
      final result = compressImage(
        ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.png,
          targetSizeBytes: 1,
        ),
      );

      expect(result.reachedTarget, isTrue);
      expect(result.outputFormat, ImageOutputFormat.png);
      expect(img.decodePng(result.bytes), isNotNull);
    });
  });

  group('compressImage - failure paths', () {
    test('throws a clear exception for undecodable bytes, not a crash', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => compressImage(
          ImageCompressionRequest(
            sourceBytes: garbage,
            outputFormat: ImageOutputFormat.jpg,
            quality: 80,
          ),
        ),
        throwsA(isA<ImageCompressionException>()),
      );
    });
  });

  group('ImageCompressionRequest validation', () {
    test('throws if neither targetSizeBytes nor quality is given', () {
      expect(
        () => ImageCompressionRequest(
          sourceBytes: sourceBytes,
          outputFormat: ImageOutputFormat.jpg,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ImageCompressPresetSpecs', () {
    test('every preset except custom has a positive target and dimensions',
        () {
      for (final preset in ImageCompressionPreset.values) {
        final spec = ImageCompressPresetSpecs.specFor(preset);
        expect(spec.targetSizeBytes, greaterThan(0), reason: preset.name);
        expect(spec.maxWidth, greaterThan(0), reason: preset.name);
        expect(spec.maxHeight, greaterThan(0), reason: preset.name);
      }
    });
  });
}
