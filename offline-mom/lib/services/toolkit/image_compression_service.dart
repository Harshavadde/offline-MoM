import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Output container format for a compressed image.
///
/// WebP is deliberately **not** offered as a compression target (only as a
/// plain conversion elsewhere) - `package:image` 4.9.1's `encodeWebP` is
/// lossless-only (VP8L), with no quality parameter to search over, so it
/// cannot participate in the target-size algorithm below the same way
/// JPEG's quality parameter can. PNG is included for completeness (some
/// presets/users want a lossless output) but is lossless too - see
/// [ImageCompressionResult.reachedTarget]'s doc comment for what that means
/// for PNG specifically.
enum ImageOutputFormat { jpg, png }

extension ImageOutputFormatExt on ImageOutputFormat {
  String get extension => switch (this) {
        ImageOutputFormat.jpg => 'jpg',
        ImageOutputFormat.png => 'png',
      };
}

/// A named starting point for the common "I need this photo under N KB for
/// a form" problem (Student Toolkit, V2 Phase 5A) - each preset is a
/// reasonable, general default, **not** an authoritative rule for any
/// specific institution/exam/form (those vary too widely to hard-code
/// safely - see each preset's own doc comment and the mandatory in-app
/// disclaimer `ImageCompressPresetSpecs.disclaimer`).
enum ImageCompressionPreset {
  passport,
  scholarship,
  governmentExam,
  collegeAdmission,
  jobApplication,
  visa,
  emailAttachment,
  custom,
}

extension ImageCompressionPresetLabel on ImageCompressionPreset {
  String get label => switch (this) {
        ImageCompressionPreset.passport => 'Passport',
        ImageCompressionPreset.scholarship => 'Scholarship',
        ImageCompressionPreset.governmentExam => 'Government Exam',
        ImageCompressionPreset.collegeAdmission => 'College Admission',
        ImageCompressionPreset.jobApplication => 'Job Application',
        ImageCompressionPreset.visa => 'Visa',
        ImageCompressionPreset.emailAttachment => 'Email Attachment',
        ImageCompressionPreset.custom => 'Custom',
      };
}

/// One preset's concrete target - what `ImageCompressPresetSpecs.specFor`
/// resolves each [ImageCompressionPreset] to.
class ImageCompressionSpec {
  const ImageCompressionSpec({
    required this.targetSizeBytes,
    required this.maxWidth,
    required this.maxHeight,
  });

  final int targetSizeBytes;
  final int maxWidth;
  final int maxHeight;
}

/// Concrete values behind each preset. Deliberately general/conservative
/// (smaller side, not larger) - a file that's smaller than a form strictly
/// requires is nearly always accepted; one that's larger is rejected
/// outright, so erring small is the safer default when the exact rule is
/// unknown.
class ImageCompressPresetSpecs {
  ImageCompressPresetSpecs._();

  /// Shown once, prominently, wherever presets are offered - real
  /// requirements vary by institution/exam/country and change over time;
  /// these are starting points, not guarantees.
  static const disclaimer =
      'These are general starting points, not official rules - always '
      "check the exact size/dimension requirement on the form or portal "
      "you're submitting to.";

  static ImageCompressionSpec specFor(ImageCompressionPreset preset) => switch (preset) {
        // Most passport-photo portals ask for well under 100KB at a
        // roughly square crop - 50KB / 600x600 is a safely small default.
        ImageCompressionPreset.passport =>
          const ImageCompressionSpec(targetSizeBytes: 50 * 1024, maxWidth: 600, maxHeight: 600),
        ImageCompressionPreset.scholarship =>
          const ImageCompressionSpec(targetSizeBytes: 100 * 1024, maxWidth: 1000, maxHeight: 1000),
        // Government exam portals are notorious for very small, strict
        // limits (often 20-50KB) - defaulting small on purpose.
        ImageCompressionPreset.governmentExam =>
          const ImageCompressionSpec(targetSizeBytes: 50 * 1024, maxWidth: 800, maxHeight: 800),
        ImageCompressionPreset.collegeAdmission => const ImageCompressionSpec(
            targetSizeBytes: 200 * 1024, maxWidth: 1200, maxHeight: 1200),
        ImageCompressionPreset.jobApplication =>
          const ImageCompressionSpec(targetSizeBytes: 200 * 1024, maxWidth: 1000, maxHeight: 1000),
        // Visa photo specs commonly cap around 240KB at a 2x2in / 600x600px
        // square.
        ImageCompressionPreset.visa =>
          const ImageCompressionSpec(targetSizeBytes: 200 * 1024, maxWidth: 600, maxHeight: 600),
        ImageCompressionPreset.emailAttachment => const ImageCompressionSpec(
            targetSizeBytes: 1024 * 1024, maxWidth: 1920, maxHeight: 1920),
        // Custom has no fixed spec - the caller supplies its own request
        // directly rather than going through this lookup.
        ImageCompressionPreset.custom =>
          const ImageCompressionSpec(targetSizeBytes: 1024 * 1024, maxWidth: 1920, maxHeight: 1920),
      };
}

/// Everything [compressImage] needs - a plain, isolate-sendable value
/// object (no closures/BuildContext), since the actual work runs off the
/// main isolate via [compute] (Performance requirement: decoding/encoding
/// a large image is real CPU work that would otherwise jank the UI thread).
@immutable
class ImageCompressionRequest {
  ImageCompressionRequest({
    required this.sourceBytes,
    required this.outputFormat,
    this.targetSizeBytes,
    this.quality,
    this.maxWidth,
    this.maxHeight,
  }) {
    // A real, always-enforced check (Phase 4B established why `assert`
    // alone isn't good enough here: it's stripped from release builds
    // entirely) - this is reachable from real UI input (Advanced Mode's
    // target-KB field vs. quality slider), not just an internal invariant.
    if (targetSizeBytes == null && quality == null) {
      throw ArgumentError('either a target size or an explicit quality must be given');
    }
  }

  final Uint8List sourceBytes;
  final ImageOutputFormat outputFormat;

  /// When set, [compressImage] searches for the highest JPEG quality whose
  /// encoded size is at or under this many bytes (binary search, bounded
  /// iteration count - see [compressImage]'s doc comment). Ignored for
  /// [ImageOutputFormat.png] (lossless - see
  /// [ImageCompressionResult.reachedTarget]).
  final int? targetSizeBytes;

  /// Used directly (no search) when [targetSizeBytes] is null - "Advanced
  /// Mode"'s explicit quality slider.
  final int? quality;

  /// Optional resolution cap, applied (aspect-ratio-preserving) before
  /// quality search/encoding - most presets set this; Advanced Mode makes
  /// it optional.
  final int? maxWidth;
  final int? maxHeight;
}

/// What [compressImage] produces.
@immutable
class ImageCompressionResult {
  const ImageCompressionResult({
    required this.bytes,
    required this.outputFormat,
    required this.originalSizeBytes,
    required this.width,
    required this.height,
    required this.reachedTarget,
  });

  final Uint8List bytes;
  final ImageOutputFormat outputFormat;
  final int originalSizeBytes;
  final int width;
  final int height;

  /// True if a [ImageCompressionRequest.targetSizeBytes] was given and
  /// [bytes] is at or under it. Always `true` for a plain-quality request
  /// (nothing to fail to reach) and, deliberately, for
  /// [ImageOutputFormat.png] requests specifically (PNG is lossless - this
  /// service does not lossily degrade a PNG's pixels just to hit a byte
  /// target, only resizes it per [ImageCompressionRequest.maxWidth]/
  /// [maxHeight] - the caller's UI is expected to show the real achieved
  /// size either way, never silently claim a target was hit when it
  /// wasn't).
  final bool reachedTarget;

  int get resultSizeBytes => bytes.lengthInBytes;
}

/// The actual minimum JPEG quality this service will encode at - below this
/// point image quality degrades badly enough that a smaller file isn't
/// worth what it costs visually; a target this service can't reach even at
/// this floor is reported via [ImageCompressionResult.reachedTarget]
/// (`false`), never silently exceeded.
const _minJpegQuality = 10;
const _maxJpegQuality = 95;

/// How many times [compressImage] will downscale-and-retry before giving up
/// on reaching [ImageCompressionRequest.targetSizeBytes] - each retry
/// computes a new resolution analytically (see [compressImage]'s doc
/// comment), so this bounds the number of encode passes, not the total
/// size reduction achievable; in practice 2-4 iterations reach almost any
/// realistic target, this just guarantees termination for a pathological
/// one.
const _maxDownscaleRetries = 8;

/// Decodes [bytes] as an image, normalizing every failure mode
/// `package:image` has (some formats return `null` on unrecognized data;
/// others - confirmed for at least its PSD format-sniffer against very
/// short/malformed input - throw a raw `RangeError` while merely *checking*
/// whether the data might be that format) into one clear
/// [ImageCompressionException], so a corrupted or unsupported file a user
/// picks is always a graceful, catchable failure, never an uncaught crash.
img.Image decodeToolkitImageOrThrow(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    throw const ImageCompressionException(
      'This file could not be read as an image - it may be corrupted or in '
      'an unsupported format.',
    );
  }
  return decoded;
}

/// Compresses [ImageCompressionRequest.sourceBytes] to a target size or an
/// explicit quality (Student Toolkit, V2 Phase 5A). Pure, deterministic,
/// no I/O - callers run this via `compute()` to keep the decode/encode work
/// (real CPU cost for a multi-megapixel photo) off the UI isolate; this
/// function itself is the `compute()`-compatible top-level entry point.
///
/// Target-size algorithm: binary-search JPEG quality between
/// [_minJpegQuality] and [_maxJpegQuality] for the highest quality whose
/// encoded size is at or under the target. If even [_minJpegQuality] still
/// exceeds the target at the current resolution, downscale and repeat, up
/// to [_maxDownscaleRetries] times - covers the realistic case (a preset's
/// small target combined with a large source photo) where quality
/// reduction alone can't reach it. Each downscale step is computed
/// analytically rather than by a fixed percentage: JPEG size at a fixed
/// quality scales roughly with pixel count, so the next resolution is
/// `current * sqrt(target / currentFloorSize) * 0.9` (a 10% safety margin,
/// since the relationship isn't perfectly linear) - this reaches a
/// reachable target in a small, bounded number of encode passes instead of
/// creeping down by a fixed fraction each time, which either wastes passes
/// (steps too small) or overshoots (steps too large) depending on how far
/// off the starting resolution is. If the target still isn't reached after
/// every retry, returns the smallest result achieved with
/// [ImageCompressionResult.reachedTarget] `false` - never a silent lie
/// about the actual output size.
ImageCompressionResult compressImage(ImageCompressionRequest request) {
  final decoded = decodeToolkitImageOrThrow(request.sourceBytes);

  var working = decoded;
  final maxWidth = request.maxWidth;
  final maxHeight = request.maxHeight;
  if (maxWidth != null || maxHeight != null) {
    if (working.width > (maxWidth ?? working.width) ||
        working.height > (maxHeight ?? working.height)) {
      working = img.copyResize(
        working,
        width: maxWidth,
        height: maxHeight,
        maintainAspect: true,
        interpolation: img.Interpolation.average,
      );
    }
  }

  if (request.outputFormat == ImageOutputFormat.png) {
    final bytes = img.encodePng(working);
    return ImageCompressionResult(
      bytes: bytes,
      outputFormat: ImageOutputFormat.png,
      originalSizeBytes: request.sourceBytes.lengthInBytes,
      width: working.width,
      height: working.height,
      reachedTarget: true,
    );
  }

  final targetSizeBytes = request.targetSizeBytes;
  if (targetSizeBytes == null) {
    final bytes = img.encodeJpg(working, quality: request.quality!);
    return ImageCompressionResult(
      bytes: bytes,
      outputFormat: ImageOutputFormat.jpg,
      originalSizeBytes: request.sourceBytes.lengthInBytes,
      width: working.width,
      height: working.height,
      reachedTarget: true,
    );
  }

  Uint8List? best;
  var attemptImage = working;
  for (var retry = 0; retry <= _maxDownscaleRetries; retry++) {
    final atFloor = _encodeAtQuality(attemptImage, _minJpegQuality);
    if (atFloor.lengthInBytes <= targetSizeBytes) {
      best = _binarySearchQuality(attemptImage, targetSizeBytes);
      return ImageCompressionResult(
        bytes: best,
        outputFormat: ImageOutputFormat.jpg,
        originalSizeBytes: request.sourceBytes.lengthInBytes,
        width: attemptImage.width,
        height: attemptImage.height,
        reachedTarget: true,
      );
    }
    // Even the quality floor is still over target at this resolution -
    // the smallest result seen so far is the floor-quality encode itself.
    best = atFloor;
    if (retry == _maxDownscaleRetries) break;
    // Analytic next step (see this function's doc comment): JPEG size at a
    // fixed quality scales roughly with pixel count, so scale each linear
    // dimension by sqrt(target / currentSize), with a 10% safety margin
    // and a floor/ceiling so one pathological ratio can't produce a
    // no-op or a jump straight to 1x1.
    final ratio =
        (math.sqrt(targetSizeBytes / atFloor.lengthInBytes) * 0.9).clamp(0.2, 0.9);
    final nextWidth = (attemptImage.width * ratio).round();
    final nextHeight = (attemptImage.height * ratio).round();
    if (nextWidth < 40 || nextHeight < 40) break;
    attemptImage = img.copyResize(
      attemptImage,
      width: nextWidth,
      height: nextHeight,
      interpolation: img.Interpolation.average,
    );
  }

  return ImageCompressionResult(
    bytes: best!,
    outputFormat: ImageOutputFormat.jpg,
    originalSizeBytes: request.sourceBytes.lengthInBytes,
    width: attemptImage.width,
    height: attemptImage.height,
    reachedTarget: false,
  );
}

Uint8List _encodeAtQuality(img.Image image, int quality) => img.encodeJpg(image, quality: quality);

Uint8List _binarySearchQuality(img.Image image, int targetSizeBytes) {
  var lo = _minJpegQuality;
  var hi = _maxJpegQuality;
  var best = _encodeAtQuality(image, _minJpegQuality);
  while (lo <= hi) {
    final mid = lo + ((hi - lo) ~/ 2);
    final candidate = _encodeAtQuality(image, mid);
    if (candidate.lengthInBytes <= targetSizeBytes) {
      best = candidate;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best;
}

/// Thrown by [compressImage] when [ImageCompressionRequest.sourceBytes]
/// can't be decoded at all - a real, expected failure path (a corrupted
/// file, an unsupported format image_picker still let through), not a bug.
class ImageCompressionException implements Exception {
  const ImageCompressionException(this.message);
  final String message;

  @override
  String toString() => message;
}
