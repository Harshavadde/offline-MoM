import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_compression_service.dart' show decodeToolkitImageOrThrow;

export 'image_compression_service.dart' show ImageCompressionException;

/// Output format for [resizeImage] - a strict superset of
/// `ImageOutputFormat` (image_compression_service.dart): resizing has no
/// target-size search to run, so WebP's lossless-only limitation there
/// doesn't apply here - this is also where "Image Conversion" (a plain
/// re-encode with no size change beyond the resize itself) lives, rather
/// than as a fourth, largely-redundant top-level screen.
enum ImageResizeOutputFormat { jpg, png, webp }

extension ImageResizeOutputFormatExt on ImageResizeOutputFormat {
  String get extension => switch (this) {
        ImageResizeOutputFormat.jpg => 'jpg',
        ImageResizeOutputFormat.png => 'png',
        ImageResizeOutputFormat.webp => 'webp',
      };

  String get label => switch (this) {
        ImageResizeOutputFormat.jpg => 'JPG',
        ImageResizeOutputFormat.png => 'PNG',
        ImageResizeOutputFormat.webp => 'WebP',
      };
}

/// How the target dimensions in [ImageResizeRequest] are interpreted.
enum ImageResizeMode { percentage, width, height }

/// A fixed, high "visually lossless" default for JPEG output when the user
/// hasn't gone through the Compress tool's explicit quality controls - this
/// tool's job is changing dimensions, not trading off quality for size, so
/// it defaults to a quality that doesn't visibly degrade the image.
const _defaultResizeJpegQuality = 92;

/// Everything [resizeImage] needs - see `ImageCompressionRequest`'s
/// identical reasoning for why this is a plain, isolate-sendable value
/// object run via `compute()`.
@immutable
class ImageResizeRequest {
  ImageResizeRequest({
    required this.sourceBytes,
    required this.mode,
    required this.outputFormat,
    this.percentage,
    this.targetWidth,
    this.targetHeight,
    this.maintainAspectRatio = true,
  }) {
    switch (mode) {
      case ImageResizeMode.percentage:
        if (percentage == null || percentage! <= 0) {
          throw ArgumentError('percentage mode requires a positive percentage');
        }
      case ImageResizeMode.width:
        if (targetWidth == null || targetWidth! <= 0) {
          throw ArgumentError('width mode requires a positive targetWidth');
        }
      case ImageResizeMode.height:
        if (targetHeight == null || targetHeight! <= 0) {
          throw ArgumentError('height mode requires a positive targetHeight');
        }
    }
  }

  final Uint8List sourceBytes;
  final ImageResizeMode mode;
  final ImageResizeOutputFormat outputFormat;

  /// Percentage mode: e.g. `50` halves both dimensions. Always maintains
  /// aspect ratio (scaling both dimensions by the same factor is what
  /// "percentage" means) - [maintainAspectRatio] has no effect in this mode.
  final double? percentage;

  /// Width mode's target width in pixels.
  final int? targetWidth;

  /// Height mode's target height in pixels.
  final int? targetHeight;

  /// Width/height mode only: when `true` (the default), the other
  /// dimension is computed from the source's aspect ratio; when `false`,
  /// only the specified dimension is constrained and the image is
  /// stretched/squashed to exactly fill it in the other axis - an
  /// intentional, explicit choice a user can make, not a bug.
  final bool maintainAspectRatio;
}

@immutable
class ImageResizeResult {
  const ImageResizeResult({
    required this.bytes,
    required this.outputFormat,
    required this.originalSizeBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final ImageResizeOutputFormat outputFormat;
  final int originalSizeBytes;
  final int originalWidth;
  final int originalHeight;
  final int width;
  final int height;

  int get resultSizeBytes => bytes.lengthInBytes;
}

/// Resizes/converts [ImageResizeRequest.sourceBytes] (Student Toolkit,
/// V2 Phase 5A). Pure, deterministic, no I/O - see
/// `image_compression_service.dart`'s `compressImage` doc comment for why
/// this is designed as a plain top-level function callers run via
/// `compute()`, not a class method.
ImageResizeResult resizeImage(ImageResizeRequest request) {
  final decoded = decodeToolkitImageOrThrow(request.sourceBytes);
  final originalWidth = decoded.width;
  final originalHeight = decoded.height;

  int? width;
  int? height;
  bool maintainAspect;
  switch (request.mode) {
    case ImageResizeMode.percentage:
      final factor = request.percentage! / 100.0;
      width = (originalWidth * factor).round().clamp(1, originalWidth * 10);
      height = (originalHeight * factor).round().clamp(1, originalHeight * 10);
      maintainAspect = true;
    case ImageResizeMode.width:
      width = request.targetWidth;
      height = request.maintainAspectRatio ? null : originalHeight;
      maintainAspect = request.maintainAspectRatio;
    case ImageResizeMode.height:
      height = request.targetHeight;
      width = request.maintainAspectRatio ? null : originalWidth;
      maintainAspect = request.maintainAspectRatio;
  }

  final resized = img.copyResize(
    decoded,
    width: width,
    height: height,
    maintainAspect: maintainAspect,
    interpolation: img.Interpolation.average,
  );

  final bytes = switch (request.outputFormat) {
    ImageResizeOutputFormat.jpg => img.encodeJpg(resized, quality: _defaultResizeJpegQuality),
    ImageResizeOutputFormat.png => img.encodePng(resized),
    ImageResizeOutputFormat.webp => img.encodeWebP(resized),
  };

  return ImageResizeResult(
    bytes: bytes,
    outputFormat: request.outputFormat,
    originalSizeBytes: request.sourceBytes.lengthInBytes,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    width: resized.width,
    height: resized.height,
  );
}
