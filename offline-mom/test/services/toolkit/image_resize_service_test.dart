import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/toolkit/image_resize_service.dart';

Uint8List _sourceBytes({int width = 800, int height = 400}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 140, 160));
  return img.encodeJpg(image, quality: 95);
}

void main() {
  late Uint8List sourceBytes;

  setUpAll(() {
    sourceBytes = _sourceBytes();
  });

  group('resizeImage - percentage mode', () {
    test('50% halves both dimensions', () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.percentage,
          percentage: 50,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
      );

      expect(result.originalWidth, 800);
      expect(result.originalHeight, 400);
      expect(result.width, 400);
      expect(result.height, 200);
    });

    test('200% doubles both dimensions (upscaling is a valid, explicit '
        'user choice for this tool, unlike compression)', () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.percentage,
          percentage: 200,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
      );

      expect(result.width, 1600);
      expect(result.height, 800);
    });
  });

  group('resizeImage - width mode', () {
    test('maintains aspect ratio by default', () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.width,
          targetWidth: 400,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
      );

      expect(result.width, 400);
      // Original aspect ratio is 2:1 (800x400) - height should follow.
      expect(result.height, 200);
    });

    test('with aspect ratio unlocked, height stays at the original value',
        () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.width,
          targetWidth: 400,
          maintainAspectRatio: false,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
      );

      expect(result.width, 400);
      expect(result.height, 400); // stretched, not proportional
    });
  });

  group('resizeImage - height mode', () {
    test('maintains aspect ratio by default', () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.height,
          targetHeight: 100,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
      );

      expect(result.height, 100);
      expect(result.width, 200);
    });
  });

  group('resizeImage - output format conversion', () {
    test('jpg output decodes as jpg', () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.percentage,
          percentage: 50,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
      );
      expect(img.JpegDecoder().isValidFile(result.bytes), isTrue);
    });

    test('png output decodes as png', () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.percentage,
          percentage: 50,
          outputFormat: ImageResizeOutputFormat.png,
        ),
      );
      expect(img.decodePng(result.bytes), isNotNull);
    });

    test('webp output decodes back to an image of the same dimensions', () {
      final result = resizeImage(
        ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.percentage,
          percentage: 50,
          outputFormat: ImageResizeOutputFormat.webp,
        ),
      );
      final decoded = img.decodeWebP(result.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, result.width);
      expect(decoded.height, result.height);
    });
  });

  group('resizeImage - validation', () {
    test('percentage mode requires a positive percentage', () {
      expect(
        () => ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.percentage,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
        throwsArgumentError,
      );
    });

    test('width mode requires a positive targetWidth', () {
      expect(
        () => ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.width,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
        throwsArgumentError,
      );
    });

    test('height mode requires a positive targetHeight', () {
      expect(
        () => ImageResizeRequest(
          sourceBytes: sourceBytes,
          mode: ImageResizeMode.height,
          outputFormat: ImageResizeOutputFormat.jpg,
        ),
        throwsArgumentError,
      );
    });
  });

  group('resizeImage - failure paths', () {
    test('throws a clear exception for undecodable bytes, not a crash', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => resizeImage(
          ImageResizeRequest(
            sourceBytes: garbage,
            mode: ImageResizeMode.percentage,
            percentage: 50,
            outputFormat: ImageResizeOutputFormat.jpg,
          ),
        ),
        throwsA(isA<ImageCompressionException>()),
      );
    });
  });
}
