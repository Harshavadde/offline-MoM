// Tests pdf_page_rendering_service.dart's RGBA-to-JPEG alpha-compositing
// fix (R-6) - the shared conversion step every PDF Tool depends on
// (`PrintingPdfPageRenderingService.rasterizePages` calls it for every
// page). `Printing.raster()` itself has no implementation under
// `flutter test` (R-32 and successors), but `encodeRasterAsJpeg` is pure
// Dart, exposed `@visibleForTesting` specifically so this conversion step
// - the one screenshots showed producing washed-out/discolored PDF Tool
// output - is directly verifiable with synthetic pixel data.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';

/// Builds a 1x1 RGBA pixel buffer with the given channel values.
Uint8List _onePixelRgba(int r, int g, int b, int a) {
  return Uint8List.fromList([r, g, b, a]);
}

void main() {
  group('encodeRasterAsJpeg - RGBA alpha compositing (R-6)', () {
    test('a fully opaque pixel keeps its real color', () {
      final bytes = encodeRasterAsJpeg(
        RasterEncodeRequest(width: 1, height: 1, pixels: _onePixelRgba(30, 60, 90, 255), quality: 100),
      );
      final decoded = img.decodeJpg(bytes)!;
      final pixel = decoded.getPixel(0, 0);
      // JPEG's own lossy chroma subsampling means a single-pixel round trip
      // isn't byte-exact - a wide tolerance still proves the real color
      // survived, not that it collapsed toward white (which is what the
      // pre-fix behavior effectively did for any non-opaque pixel, and
      // what a broken fix could still do for opaque ones).
      expect(pixel.r, closeTo(30, 12));
      expect(pixel.g, closeTo(60, 12));
      expect(pixel.b, closeTo(90, 12));
    });

    test('a fully transparent pixel composites to pure white, not its raw (irrelevant) RGB value', () {
      // Alpha 0 - these RGB values are exactly the kind of "leftover"
      // color the pre-fix code baked straight into the JPEG, producing
      // the washed-out/discolored output screenshots showed. A correct
      // fix must composite this pixel against the white page background
      // instead, regardless of what its RGB channels happen to contain.
      final bytes = encodeRasterAsJpeg(
        RasterEncodeRequest(width: 1, height: 1, pixels: _onePixelRgba(255, 0, 0, 0), quality: 100),
      );
      final decoded = img.decodeJpg(bytes)!;
      final pixel = decoded.getPixel(0, 0);
      expect(pixel.r, closeTo(255, 5));
      expect(pixel.g, closeTo(255, 5));
      expect(pixel.b, closeTo(255, 5));
    });

    test('a half-transparent pixel blends proportionally toward white, not left as raw RGB', () {
      // Black at alpha 128 (~50%) composited onto white should land near
      // mid-gray (~127) - proving real alpha blending happens, not a
      // binary "fully opaque or fully dropped" shortcut.
      final bytes = encodeRasterAsJpeg(
        RasterEncodeRequest(width: 1, height: 1, pixels: _onePixelRgba(0, 0, 0, 128), quality: 100),
      );
      final decoded = img.decodeJpg(bytes)!;
      final pixel = decoded.getPixel(0, 0);
      expect(pixel.r, closeTo(127, 20));
      expect(pixel.g, closeTo(127, 20));
      expect(pixel.b, closeTo(127, 20));
      // Explicitly not still-black (the un-composited raw value) and not
      // still-white (an over-correction) - genuinely blended.
      expect(pixel.r, greaterThan(60));
      expect(pixel.r, lessThan(200));
    });

    test('output is a real, valid JPEG with the requested dimensions', () {
      final pixels = Uint8List(4 * 3 * 2); // 3x2 image, RGBA
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = 10;
        pixels[i + 1] = 20;
        pixels[i + 2] = 30;
        pixels[i + 3] = 255;
      }
      final bytes = encodeRasterAsJpeg(RasterEncodeRequest(width: 3, height: 2, pixels: pixels, quality: 90));
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, 3);
      expect(decoded.height, 2);
    });
  });

  group('encodeRasterAsJpeg - BGRA alpha compositing (PDFium/pdfrx path)', () {
    // PDFium (`pdfrx_engine`'s `PdfImage.pixels`, the replacement for
    // `printing`'s RGBA8888 raster - see `PdfiumPdfPageRenderingService`)
    // yields BGRA8888, not RGBA8888. These mirror the RGBA group above
    // exactly, byte-swapped, proving the same already-correct compositing
    // logic (R-6) is reused correctly for the new channel order rather
    // than silently swapping red and blue across the whole page.
    Uint8List onePixelBgra(int r, int g, int b, int a) {
      return Uint8List.fromList([b, g, r, a]);
    }

    test('a fully opaque pixel keeps its real color, channels in the right place', () {
      final bytes = encodeRasterAsJpeg(
        RasterEncodeRequest(
          width: 1,
          height: 1,
          pixels: onePixelBgra(30, 60, 90, 255),
          quality: 100,
          channelOrder: RasterChannelOrder.bgra,
        ),
      );
      final decoded = img.decodeJpg(bytes)!;
      final pixel = decoded.getPixel(0, 0);
      expect(pixel.r, closeTo(30, 12));
      expect(pixel.g, closeTo(60, 12));
      expect(pixel.b, closeTo(90, 12));
    });

    test('a fully transparent BGRA pixel still composites to pure white', () {
      final bytes = encodeRasterAsJpeg(
        RasterEncodeRequest(
          width: 1,
          height: 1,
          pixels: onePixelBgra(255, 0, 0, 0),
          quality: 100,
          channelOrder: RasterChannelOrder.bgra,
        ),
      );
      final decoded = img.decodeJpg(bytes)!;
      final pixel = decoded.getPixel(0, 0);
      expect(pixel.r, closeTo(255, 5));
      expect(pixel.g, closeTo(255, 5));
      expect(pixel.b, closeTo(255, 5));
    });

    test('RasterChannelOrder defaults to rgba, so every pre-existing caller is unaffected', () {
      final rgba = Uint8List.fromList([12, 34, 56, 255]);
      final bytes = encodeRasterAsJpeg(RasterEncodeRequest(width: 1, height: 1, pixels: rgba, quality: 100));
      final decoded = img.decodeJpg(bytes)!;
      final pixel = decoded.getPixel(0, 0);
      expect(pixel.r, closeTo(12, 12));
      expect(pixel.g, closeTo(34, 12));
      expect(pixel.b, closeTo(56, 12));
    });
  });

  group('looksLikeBlankRenderFailure', () {
    img.Image solidImage(int r, int g, int b, {int width = 100, int height = 100}) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      return image;
    }

    test('a perfectly uniform white page looks like a render failure', () {
      expect(looksLikeBlankRenderFailure(solidImage(255, 255, 255)), isTrue);
    });

    test('a perfectly uniform non-white page also looks like a render failure '
        '(uniformity is the signal, not whiteness specifically)', () {
      expect(looksLikeBlankRenderFailure(solidImage(240, 240, 240)), isTrue);
    });

    test('a page with real, spread-out content does not look like a failure', () {
      final image = solidImage(255, 255, 255, width: 200, height: 260);
      // Scatter enough non-white pixels around the page to resemble real
      // text/graphics, not a single small mark easily missed by sampling.
      // Deliberately starts at (2, 2), not (0, 0): pixel (0, 0) is the
      // function's own reference pixel, so marking it would flip the
      // comparison (nearly everything would "differ" from a now-black
      // reference) instead of testing what this test claims to.
      for (var y = 2; y < image.height; y += 5) {
        for (var x = 2; x < image.width; x += 5) {
          image.setPixelRgb(x, y, 0, 0, 0);
        }
      }
      expect(looksLikeBlankRenderFailure(image), isFalse);
    });

    test('a tiny, localized mark on an otherwise blank page still counts as blank '
        '(matches this app\'s own real bug: a couple of stray glyphs on an '
        'otherwise-empty page)', () {
      final image = solidImage(255, 255, 255, width: 200, height: 260);
      // Placed well away from (0, 0), the function's own reference pixel -
      // see the note above.
      for (var y = 100; y < 104; y++) {
        for (var x = 100; x < 104; x++) {
          image.setPixelRgb(x, y, 0, 0, 0);
        }
      }
      expect(looksLikeBlankRenderFailure(image), isTrue);
    });
  });

  group('detectContentBounds', () {
    img.Image whiteImage(int width, int height) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      return image;
    }

    test('a genuinely blank page returns the full image bounds unchanged '
        '(a blank page must never be cropped away)', () {
      final image = whiteImage(200, 260);
      final bounds = detectContentBounds(image);
      expect(bounds.isFullImage(200, 260), isTrue);
    });

    test('content confined to the top half is detected with a bottom edge '
        'well short of the full page height - the exact real-world case '
        '(a resume\'s Education/Certifications page) that motivated this '
        'feature', () {
      final image = whiteImage(200, 260);
      img.fillRect(image, x1: 10, y1: 10, x2: 190, y2: 120, color: img.ColorRgb8(0, 0, 0));
      final bounds = detectContentBounds(image);

      expect(bounds.isFullImage(200, 260), isFalse);
      expect(bounds.top, lessThan(15));
      // Bottom of the detected region (top + height) should sit just past
      // the content's own bottom edge (120) plus padding, nowhere near the
      // full 260px page height.
      expect(bounds.top + bounds.height, lessThan(150));
    });

    test('content spanning nearly the whole page is detected close to the '
        'full page bounds - matches the source resume\'s own page 1 '
        '(measured at 94.7% fill), which should barely be cropped at all',
        () {
      final image = whiteImage(200, 260);
      img.fillRect(image, x1: 5, y1: 5, x2: 195, y2: 246, color: img.ColorRgb8(0, 0, 0));
      final bounds = detectContentBounds(image);

      expect(bounds.height / 260, greaterThan(0.90));
    });

    test('padding keeps cropped content away from the very edge, never '
        'flush against it', () {
      final image = whiteImage(200, 260);
      img.fillRect(image, x1: 20, y1: 20, x2: 100, y2: 100, color: img.ColorRgb8(0, 0, 0));
      final bounds = detectContentBounds(image);

      expect(bounds.left, lessThan(20));
      expect(bounds.top, lessThan(20));
    });
  });

  group('encodeRasterAsCroppedJpeg', () {
    Uint8List rgbaBytesFor(img.Image image) {
      final bytes = Uint8List(image.width * image.height * 4);
      var i = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          bytes[i++] = p.r.toInt();
          bytes[i++] = p.g.toInt();
          bytes[i++] = p.b.toInt();
          bytes[i++] = 255;
        }
      }
      return bytes;
    }

    test('a page with content only in the top half is cropped shorter than '
        'the source page', () {
      final image = img.Image(width: 200, height: 260);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(image, x1: 10, y1: 10, x2: 190, y2: 120, color: img.ColorRgb8(0, 0, 0));

      final result = encodeRasterAsCroppedJpeg(
        RasterEncodeRequest(width: 200, height: 260, pixels: rgbaBytesFor(image), quality: 90),
      );

      expect(result.height, lessThan(260));
      expect(result.width, lessThanOrEqualTo(200));
      final decoded = img.decodeJpg(result.jpegBytes)!;
      expect(decoded.width, result.width);
      expect(decoded.height, result.height);
    });

    test('a genuinely blank page is returned at its original, uncropped '
        'dimensions', () {
      final image = img.Image(width: 200, height: 260);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      final result = encodeRasterAsCroppedJpeg(
        RasterEncodeRequest(width: 200, height: 260, pixels: rgbaBytesFor(image), quality: 90),
      );

      expect(result.width, 200);
      expect(result.height, 260);
    });
  });
}
