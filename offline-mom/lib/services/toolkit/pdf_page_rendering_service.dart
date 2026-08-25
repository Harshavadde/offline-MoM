import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfrx;

import '../../core/utils/toolkit_paths.dart';

/// One PDF page, already rasterized and JPEG-compressed to a toolkit temp
/// file - the caller owns this file and must delete it (directly, or via
/// [clearToolkitTempFiles] as a safety net) once done with it.
class RasterizedPdfPage {
  const RasterizedPdfPage({
    required this.tempFilePath,
    required this.width,
    required this.height,
    required this.pageIndex,
  });

  final String tempFilePath;
  final int width;
  final int height;

  /// 0-based index into the source PDF's page list.
  final int pageIndex;
}

class PdfRenderingException implements Exception {
  const PdfRenderingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The shared foundation every PDF Tool (Compress/Merge/Split/Organize)
/// reads existing PDF pages through - see ADR-034,
/// docs/v2/implementation/03-decisions.md, for why rasterize-and-rebuild is
/// this app's PDF-manipulation strategy.
abstract class PdfPageRenderingService {
  /// Rasterizes [pageIndices] (or every page, if null) of [pdfBytes] at
  /// [dpi], JPEG-encoding each page at [jpegQuality] and writing it to a
  /// toolkit temp file before yielding it - one page resident in memory at
  /// a time. Throws [PdfRenderingException] if [pdfBytes] isn't a
  /// renderable PDF.
  ///
  /// [pageIndices] selects *which* pages to rasterize, not their yielded
  /// order - deduplicated and rasterized in ascending order regardless of
  /// the order passed in. Each [RasterizedPdfPage.pageIndex] tells the
  /// caller which source page it is; a caller that needs a specific final
  /// order (e.g. "Organize"'s reordering) resequences the returned pages
  /// itself, keyed by [RasterizedPdfPage.pageIndex], rather than trusting
  /// rasterization order.
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 90,
    // Crops each page down to its own content's bounding box (plus a small
    // margin) instead of the source page's full physical size - see
    // [detectContentBounds]. Off by default (every existing caller is
    // unaffected); opt-in per caller, not per-service, so Organize keeps
    // producing pages sized to the original document unchanged while
    // Merge/Compress/Split/Redact/Edit/View (the tools this was actually
    // requested for) opt in explicitly at their own call sites.
    bool cropToContent = false,
  });
}

/// The default preview DPI used for page-thumbnail grids (Organize/Split
/// page pickers) - low enough to stay fast and small in memory even for a
/// many-page document, since a thumbnail only needs to be recognizable, not
/// print-quality.
const double kPdfThumbnailDpi = 72;

/// The default DPI used when a rasterized page is the actual output
/// (Merge/Organize/Split/Redact/Edit/View PDF's final pages).
///
/// History: originally 150, bumped to 200 after real device testing showed
/// visibly soft/blurry text on a modern high-PPI phone screen once zoomed -
/// a deliberately moderate first bump. Further real-device testing at
/// 200dpi still showed noticeable softness, so this moved again to 300dpi -
/// the standard "print/scan quality" tier document scanners and OCR
/// pipelines have used for decades specifically because it's dense enough
/// that text stays crisp at typical zoom levels. Each rasterized page is
/// still held one at a time (see `PdfiumPdfPageRenderingService`'s own
/// streaming design, `rendered.dispose()` immediately after encoding) and
/// discarded before the next page starts, so this raises peak per-page
/// memory and file size, not peak *document* memory - a many-page PDF does
/// not hold multiple 300dpi pages in memory simultaneously.
/// `PdfCompressionService` does NOT use this constant - every compression
/// preset (`PdfCompressPresetSpecs`) specifies its own, deliberately lower
/// dpi/quality as the whole point of that tool, and is completely
/// unaffected by this value.
const double kPdfOutputDpi = 300;

/// Rasterizes via `package:pdfrx_engine`'s PDFium bindings (real, bundled,
/// actively-maintained PDF rendering - the same rendering core Chrome
/// uses), fully on-device, MIT-licensed.
///
/// **Why not Android's/iOS's own OS-level PDF renderer** (what this class
/// replaced, previously reached via `package:printing`'s `Printing.raster`,
/// `android.graphics.pdf.PdfRenderer` under the hood): confirmed root
/// cause of a real bug (a resume PDF with embedded, subsetted TrueType
/// fonts rasterizing to a near-blank page - most visible text and content
/// missing, verified by extracting the produced page image directly and
/// comparing it against the same source PDF rendered by a
/// spec-compliant reference engine, which reproduced it correctly).
/// Android's built-in `PdfRenderer` has known, longstanding gaps
/// rendering certain embedded/subsetted font encodings; `printing`'s own
/// Android implementation (`android.print.PdfConvert`, vendored from AOSP)
/// is a thin wrapper around that exact OS API, not an independent engine -
/// switching to a different Flutter plugin that *also* wraps the same OS
/// API (e.g. `pdfx`, confirmed by reading its own Android source) would
/// not have fixed this. PDFium is a real, independent, far more complete
/// rendering engine, bundled with the app rather than depending on
/// whatever the OS happens to ship.
class PdfiumPdfPageRenderingService implements PdfPageRenderingService {
  @override
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 90,
    bool cropToContent = false,
  }) async* {
    pdfrx.PdfDocument? document;
    try {
      try {
        document = await pdfrx.PdfDocument.openData(pdfBytes, sourceName: 'toolkit-source.pdf');
      } catch (_) {
        throw const PdfRenderingException(
          'Could not read this PDF - it may be corrupted, password-protected, or not a valid PDF file.',
        );
      }

      final pages = document.pages;
      // Sorted + deduplicated + range-checked so rasterization order is
      // always ascending regardless of what order the caller listed pages
      // in, and a stray out-of-range index (should never happen from a
      // trusted caller, but costs nothing to guard) can't crash rendering.
      final indices = pageIndices == null
          ? List<int>.generate(pages.length, (i) => i)
          : (pageIndices.toSet().toList()..sort())
              .where((i) => i >= 0 && i < pages.length)
              .toList();

      var yielded = 0;
      for (final pageIndex in indices) {
        final page = pages[pageIndex];
        final widthPx = (page.width / 72.0 * dpi).round().clamp(1, 1 << 16);
        final heightPx = (page.height / 72.0 * dpi).round().clamp(1, 1 << 16);
        final rendered = await page.render(
          width: widthPx,
          height: heightPx,
          // Opaque white background - this page is always about to be
          // flattened onto a white page background anyway (see
          // encodeRasterAsJpeg's own compositing step below), so any
          // transparency in the source page composites correctly here too
          // rather than defaulting to black/undefined.
          backgroundColor: 0xFFFFFFFF,
        );
        if (rendered == null) {
          throw PdfRenderingException('Page ${pageIndex + 1} of this PDF could not be rendered.');
        }
        try {
          final request = RasterEncodeRequest(
            width: rendered.width,
            height: rendered.height,
            pixels: rendered.pixels,
            quality: jpegQuality,
            channelOrder: RasterChannelOrder.bgra,
          );
          final String tempPath;
          final int outWidth, outHeight;
          if (cropToContent) {
            final result = await compute(encodeRasterAsCroppedJpeg, request);
            tempPath = await newToolkitTempFilePath('jpg');
            await File(tempPath).writeAsBytes(result.jpegBytes);
            outWidth = result.width;
            outHeight = result.height;
          } else {
            final jpegBytes = await compute(encodeRasterAsJpeg, request);
            tempPath = await newToolkitTempFilePath('jpg');
            await File(tempPath).writeAsBytes(jpegBytes);
            outWidth = rendered.width;
            outHeight = rendered.height;
          }
          yield RasterizedPdfPage(
            tempFilePath: tempPath,
            width: outWidth,
            height: outHeight,
            pageIndex: pageIndex,
          );
          yielded++;
        } finally {
          rendered.dispose();
        }
      }
      if (yielded == 0) {
        throw const PdfRenderingException('This PDF has no pages that could be read.');
      }
    } finally {
      await document?.dispose();
    }
  }
}

/// The raw pixel byte layout a rasterizer produced - PDFium
/// (`pdfrx_engine`) yields BGRA8888; the platform-native renderer this
/// class previously wrapped yielded RGBA8888. [encodeRasterAsJpeg] accepts
/// either so the same, already-correct alpha-compositing logic (R-6) never
/// needs a second copy.
enum RasterChannelOrder { rgba, bgra }

/// Public (not `_`-prefixed) and `@visibleForTesting` specifically so
/// [encodeRasterAsJpeg]'s alpha-compositing behavior (R-6) is directly
/// unit-testable with synthetic pixel data - a real rasterizer has no
/// implementation under `flutter test`, but the pure-Dart conversion step
/// downstream of it always has been testable, and now is.
@visibleForTesting
class RasterEncodeRequest {
  const RasterEncodeRequest({
    required this.width,
    required this.height,
    required this.pixels,
    required this.quality,
    this.channelOrder = RasterChannelOrder.rgba,
  });

  final int width;
  final int height;
  final Uint8List pixels;
  final int quality;
  final RasterChannelOrder channelOrder;
}

/// Shared by [encodeRasterAsJpeg] and [encodeRasterAsCroppedJpeg] - decodes
/// the raw rasterizer output and flattens it onto an opaque white
/// background (R-6 fix; see [encodeRasterAsJpeg]'s own doc comment for the
/// full reasoning), stopping short of JPEG encoding so a crop can still be
/// applied to the *decoded* image first when needed.
img.Image _decodeAndCompositeOnWhite(RasterEncodeRequest request) {
  final raw = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: request.pixels.buffer,
    numChannels: 4,
    format: img.Format.uint8,
    order: request.channelOrder == RasterChannelOrder.bgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
  );
  final white = img.Image(width: request.width, height: request.height, numChannels: 3);
  img.fill(white, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(white, raw);
}

@visibleForTesting
Uint8List encodeRasterAsJpeg(RasterEncodeRequest request) {
  // R-6 fix: a rasterized PDF page can legitimately contain non-fully-
  // opaque pixels (anti-aliased glyph/vector edges, any transparency the
  // page itself defines) - but JPEG has no alpha channel at all.
  // `img.encodeJpg` on a 4-channel image simply drops the alpha channel
  // and keeps whatever raw R/G/B values happen to sit underneath it; for
  // a translucent pixel those are not the page's real visible color (they
  // were only ever meant to be seen *blended with whatever is behind
  // them*), so encoding them directly bakes in a washed-out/discolored
  // appearance across the whole page. Compositing onto an opaque white
  // background first (`img.compositeImage`, real per-pixel alpha
  // blending) is the textbook-correct RGBA-to-JPEG conversion for a
  // document page, whose backdrop is always meant to be white.
  final composited = _decodeAndCompositeOnWhite(request);
  return img.encodeJpg(composited, quality: request.quality);
}

/// The result of [encodeRasterAsCroppedJpeg] - unlike [encodeRasterAsJpeg],
/// the output's pixel dimensions genuinely differ from the input's (that's
/// the whole point of cropping), so the caller needs them back alongside
/// the bytes to build a correctly-sized output page.
@visibleForTesting
class CroppedRasterResult {
  const CroppedRasterResult({required this.jpegBytes, required this.width, required this.height});
  final Uint8List jpegBytes;
  final int width;
  final int height;
}

/// Crops the rasterized page down to [detectContentBounds]'s own bounding
/// box before JPEG-encoding it - "Merge/Redact/Edit/View PDF should fill
/// the page with actual content instead of leaving the source document's
/// own trailing whitespace" (a real, disclosed content characteristic of
/// certain source PDFs, not a rendering defect - see
/// `PdfMergeService`/`docs/architecture/hld.md` for the forensic
/// investigation that established this). A page with no detected content
/// at all (a genuinely blank page) is returned uncropped rather than
/// collapsed to nothing - see [detectContentBounds]'s own doc comment.
@visibleForTesting
CroppedRasterResult encodeRasterAsCroppedJpeg(RasterEncodeRequest request) {
  final composited = _decodeAndCompositeOnWhite(request);
  final bounds = detectContentBounds(composited);
  final cropped = bounds.isFullImage(composited.width, composited.height)
      ? composited
      : img.copyCrop(composited, x: bounds.left, y: bounds.top, width: bounds.width, height: bounds.height);
  return CroppedRasterResult(
    jpegBytes: img.encodeJpg(cropped, quality: request.quality),
    width: cropped.width,
    height: cropped.height,
  );
}

/// The detected bounding box of non-background content within a rasterized
/// page image, plus a small margin - `@visibleForTesting` so this is
/// directly verifiable with synthetic images.
@visibleForTesting
class ContentBounds {
  const ContentBounds({required this.left, required this.top, required this.width, required this.height});
  final int left;
  final int top;
  final int width;
  final int height;

  bool isFullImage(int imageWidth, int imageHeight) =>
      left == 0 && top == 0 && width == imageWidth && height == imageHeight;
}

/// Finds the bounding box of everything on [image] that isn't the page's
/// own background color (sampled from its top-left corner, the same
/// assumption [looksLikeBlankRenderFailure] already makes - a document
/// page's corner is background far more reliably than its center is), with
/// [paddingFraction] of the image's own size added back as a margin on
/// every side so cropped content never touches the very edge of the output
/// page.
///
/// Returns the **full, uncropped image bounds** if no content is detected
/// at all - a genuinely blank page must never be "cropped" down to a
/// degenerate zero-size region; there is nothing wrong with a real blank
/// page, and collapsing one to nothing would corrupt whatever document it
/// belongs to.
@visibleForTesting
ContentBounds detectContentBounds(
  img.Image image, {
  int backgroundTolerance = 12,
  double paddingFraction = 0.025,
}) {
  if (image.width <= 0 || image.height <= 0) {
    return ContentBounds(left: 0, top: 0, width: image.width, height: image.height);
  }

  final bg = image.getPixel(0, 0);
  final bgR = bg.r, bgG = bg.g, bgB = bg.b;

  var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      if ((pixel.r - bgR).abs() > backgroundTolerance ||
          (pixel.g - bgG).abs() > backgroundTolerance ||
          (pixel.b - bgB).abs() > backgroundTolerance) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < minX || maxY < minY) {
    // No content detected - a genuinely blank page. Never crop it away.
    return ContentBounds(left: 0, top: 0, width: image.width, height: image.height);
  }

  final padX = (image.width * paddingFraction).round();
  final padY = (image.height * paddingFraction).round();
  final left = (minX - padX).clamp(0, image.width - 1);
  final top = (minY - padY).clamp(0, image.height - 1);
  final right = (maxX + padX).clamp(0, image.width - 1);
  final bottom = (maxY + padY).clamp(0, image.height - 1);
  return ContentBounds(left: left, top: top, width: right - left + 1, height: bottom - top + 1);
}

/// True if [image] looks like a rendering failure - overwhelmingly one
/// near-uniform color, almost always near-white - rather than genuine page
/// content. Public (not test-only) - `PdfMergeService` calls this for
/// real, as a defensive backstop against a future rasterizer regression
/// (see `PdfiumPdfPageRenderingService`'s own doc comment for the real bug
/// this app already hit once); also directly unit-tested with synthetic
/// images, independent of any real rasterizer.
///
/// A real, legitimately blank PDF page is pixel-indistinguishable from a
/// rendering failure by content alone - this function can only ever say
/// "this looks blank," never "this SHOULD have content but didn't." A
/// caller that has an independent signal the source page should contain
/// real content (e.g. non-empty extracted text for that same page - see
/// `PdfMergeService`) is the one that turns "looks blank" into an actual
/// failure; this function itself never throws.
bool looksLikeBlankRenderFailure(img.Image image, {double maxNonUniformFraction = 0.01}) {
  if (image.width <= 0 || image.height <= 0) return true;

  final reference = image.getPixel(0, 0);
  final refR = reference.r, refG = reference.g, refB = reference.b;
  const tolerance = 8; // small anti-aliasing/compression-adjacent slack

  // Sampled, not exhaustive - stays cheap even for a high-DPI page; a real
  // rendering failure (an essentially solid-color page) is uniform enough
  // that a coarse grid still detects it reliably, and a page with genuine
  // content has non-uniform pixels densely enough to be caught by a grid
  // this fine regardless of exactly where they fall.
  final strideX = (image.width / 200).ceil().clamp(1, image.width);
  final strideY = (image.height / 260).ceil().clamp(1, image.height);

  var sampled = 0;
  var differing = 0;
  for (var y = 0; y < image.height; y += strideY) {
    for (var x = 0; x < image.width; x += strideX) {
      final pixel = image.getPixel(x, y);
      sampled++;
      if ((pixel.r - refR).abs() > tolerance ||
          (pixel.g - refG).abs() > tolerance ||
          (pixel.b - refB).abs() > tolerance) {
        differing++;
      }
    }
  }
  if (sampled == 0) return true;
  return (differing / sampled) <= maxNonUniformFraction;
}

/// A fake for service/controller tests - a real rasterizer is backed by
/// native code with no implementation under `flutter test`, so every PDF
/// Tool built on [PdfPageRenderingService] (Compress/Merge/Split/Organize)
/// needs this to test its *own* logic (grouping, page ordering, temp-file
/// cleanup, error propagation) without a real device. Genuinely writes
/// each synthetic page to a real toolkit temp file (via
/// [newToolkitTempFilePath]) - callers under test still exercise their
/// real file-read/cleanup code, only the native rasterization step itself
/// is faked.
class FakePdfPageRenderingService implements PdfPageRenderingService {
  FakePdfPageRenderingService({
    this.pageCount = 3,
    this.pageWidth = 200,
    this.pageHeight = 260,
    this.throwOnRasterize,
  });

  int pageCount;
  int pageWidth;
  int pageHeight;
  PdfRenderingException? throwOnRasterize;

  @override
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 85,
    // Accepted for interface compatibility, not simulated - this fake
    // exists for *other* services' own logic (ordering, cleanup, error
    // propagation), not for testing crop behavior itself, which is tested
    // directly against [detectContentBounds]/[encodeRasterAsCroppedJpeg].
    bool cropToContent = false,
  }) async* {
    if (throwOnRasterize != null) throw throwOnRasterize!;
    final indices = pageIndices == null
        ? List<int>.generate(pageCount, (i) => i)
        : (pageIndices.toSet().toList()..sort());
    for (final index in indices) {
      if (index < 0 || index >= pageCount) continue;
      final image = img.Image(width: pageWidth, height: pageHeight);
      // A distinct color per page index, so tests can verify page identity
      // and ordering survived a group/reorder operation, not just count.
      final color = img.ColorRgb8((index * 37) % 256, (index * 73) % 256, (index * 113) % 256);
      img.fill(image, color: color);
      // A deliberately non-uniform corner - a genuinely blank/failed
      // render is a single flat color across the whole page (see
      // [looksLikeBlankRenderFailure]), which a fake page consisting only
      // of `img.fill` would otherwise be indistinguishable from, wrongly
      // tripping that check in any test exercising both this fake and
      // real extracted text together (PdfMergeService's own regression
      // test for that check uses a *different*, genuinely-blank image
      // instead - see pdf_merge_service_test.dart).
      final markWidth = (pageWidth / 4).clamp(1, pageWidth).toInt();
      final markHeight = (pageHeight / 4).clamp(1, pageHeight).toInt();
      img.fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: markWidth,
        y2: markHeight,
        color: img.ColorRgb8(255 - color.r.toInt(), 255 - color.g.toInt(), 255 - color.b.toInt()),
      );
      final jpegBytes = img.encodeJpg(image, quality: jpegQuality);
      final tempPath = await newToolkitTempFilePath('jpg');
      await File(tempPath).writeAsBytes(jpegBytes);
      yield RasterizedPdfPage(
        tempFilePath: tempPath,
        width: pageWidth,
        height: pageHeight,
        pageIndex: index,
      );
    }
  }
}
