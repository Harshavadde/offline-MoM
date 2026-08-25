// One-off generator for OfflineMoMAI's launcher icon: run with
// `dart run tool/generate_app_icon.dart`, then
// `dart run flutter_launcher_icons` to install it into every Android
// density bucket. Not part of the shipped app - dev-time tooling only,
// which is why `image`/`flutter_launcher_icons` live in dev_dependencies.
//
// Mark: a bold rounded mic capsule (the app's existing brand symbol - the
// same one used on the Splash and About screens) on a purple-to-near-black
// gradient background, with a small "wifi off" badge standing in for
// "offline" - the most distinctive, reproducible element of the reference
// logo the app's owner shared (a fuller illustrated mark with a silhouette,
// soundwave and notebook, which isn't reproducible with hand-coded shape
// fills at any real fidelity; this keeps the same purple-gradient-on-dark
// feel and the explicit "offline" badge without attempting a crude copy of
// detail that needs real image-generation tooling to do justice to).
// Kept deliberately simple otherwise: Android's own launcher-icon guidance
// is that detailed marks turn to mush once scaled down to a 48dp
// home-screen icon, so this leans on a couple of bold, unmistakable shapes
// rather than a busy scene.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _gradientTop = 0xFF6C4FE0; // lighter purple, top-left
const _gradientBottom = 0xFF15111F; // near-black, bottom-right
const _white = 0xFFFFFFFF;
const _badgeColor = 0xFF15111F; // wifi-off badge circle, matches gradient floor

void main() {
  final full = _renderIcon(size: 1024, withBackground: true);
  final foreground = _renderIcon(size: 1024, withBackground: false);

  File('assets/icon/app_icon.png').writeAsBytesSync(img.encodePng(full));
  File('assets/icon/app_icon_foreground.png')
      .writeAsBytesSync(img.encodePng(foreground));

  // ignore: avoid_print
  print('Wrote assets/icon/app_icon.png and app_icon_foreground.png');
}

img.Image _renderIcon({required int size, required bool withBackground}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  if (withBackground) {
    _paintGradientBackground(image, size);
  }

  // Adaptive icons keep real content inside the center ~66% safe zone;
  // for the flat icon (withBackground: true) we can use more of the canvas.
  final contentScale = withBackground ? 1.0 : 0.66;
  final cx = size / 2;
  final cy = size / 2;

  // Mic capsule (rounded pill), vertically oriented.
  final capsuleWidth = size * 0.30 * contentScale;
  final capsuleHeight = size * 0.42 * contentScale;
  final capsuleTop = cy - size * 0.16 * contentScale;
  _fillRoundedRect(
    image,
    left: cx - capsuleWidth / 2,
    top: capsuleTop,
    width: capsuleWidth,
    height: capsuleHeight,
    radius: capsuleWidth / 2,
    color: _white,
  );

  // Base line under the mic.
  final baseWidth = size * 0.20 * contentScale;
  final baseHeight = size * 0.028 * contentScale;
  final baseTop = capsuleTop + capsuleHeight + size * 0.09 * contentScale;
  _fillRoundedRect(
    image,
    left: cx - baseWidth / 2,
    top: baseTop,
    width: baseWidth,
    height: baseHeight,
    radius: baseHeight / 2,
    color: _white,
  );

  // Small stem connecting the capsule to the base.
  _fillRoundedRect(
    image,
    left: cx - baseHeight / 2,
    top: capsuleTop + capsuleHeight,
    width: baseHeight,
    height: baseTop - (capsuleTop + capsuleHeight),
    radius: baseHeight / 2,
    color: _white,
  );

  // "Wifi off" badge, upper-right of the mic - the app's clearest, most
  // recognizable "offline" cue, echoing the reference logo's own badge.
  final badgeCenterX = cx + size * 0.24 * contentScale;
  final badgeCenterY = cy - size * 0.26 * contentScale;
  _fillWifiOffBadge(
    image,
    centerX: badgeCenterX,
    centerY: badgeCenterY,
    outerRadius: size * 0.15 * contentScale,
    ringColor: _white,
    fillColor: withBackground ? _badgeColor : null,
  );

  return image;
}

void _paintGradientBackground(img.Image image, int size) {
  final radius = size * 0.22;
  final topColor = _colorOf(_gradientTop);
  final bottomColor = _colorOf(_gradientBottom);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (!_insideRoundedSquare(x.toDouble(), y.toDouble(), size, radius)) {
        continue;
      }
      // Diagonal top-left -> bottom-right gradient, matching the reference
      // logo's own lighter-purple-to-near-black direction.
      final t = ((x + y) / (2 * size)).clamp(0.0, 1.0);
      image.setPixel(x, y, _lerpColor(topColor, bottomColor, t));
    }
  }
}

img.ColorRgba8 _colorOf(int argb) => img.ColorRgba8(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      255,
    );

img.ColorRgba8 _lerpColor(img.ColorRgba8 a, img.ColorRgba8 b, double t) {
  int lerp(num x, num y) => (x + (y - x) * t).round().clamp(0, 255);
  return img.ColorRgba8(
    lerp(a.r, b.r),
    lerp(a.g, b.g),
    lerp(a.b, b.b),
    255,
  );
}

// A plain `.clamp(lo, hi)` throws if `lo` ends up (even by a floating-point
// epsilon) greater than `hi`, which happens constantly here since several
// shapes use a corner radius equal to exactly half their width/height.
double _clampSafe(double v, double lo, double hi) {
  if (lo > hi) return (lo + hi) / 2;
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

bool _insideRoundedSquare(double x, double y, int size, double radius) {
  final left = 0.0, top = 0.0, right = size.toDouble(), bottom = size.toDouble();
  final nearestX = _clampSafe(x, left + radius, right - radius);
  final nearestY = _clampSafe(y, top + radius, bottom - radius);
  if (x >= left + radius && x <= right - radius) return y >= top && y <= bottom;
  if (y >= top + radius && y <= bottom - radius) return x >= left && x <= right;
  final dx = x - nearestX;
  final dy = y - nearestY;
  return dx * dx + dy * dy <= radius * radius;
}

void _fillRoundedRect(
  img.Image image, {
  required double left,
  required double top,
  required double width,
  required double height,
  required double radius,
  required int color,
}) {
  final r = math.min(radius, math.min(width, height) / 2);
  final right = left + width;
  final bottom = top + height;
  final c = img.ColorRgba8((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, 255);

  for (var y = top.floor(); y < bottom.ceil(); y++) {
    for (var x = left.floor(); x < right.ceil(); x++) {
      final px = x + 0.5, py = y + 0.5;
      if (px < left || px > right || py < top || py > bottom) continue;

      final nearestX = _clampSafe(px, left + r, right - r);
      final nearestY = _clampSafe(py, top + r, bottom - r);
      final inCorner = (px < left + r || px > right - r) && (py < top + r || py > bottom - r);
      if (inCorner) {
        final dx = px - nearestX;
        final dy = py - nearestY;
        if (dx * dx + dy * dy > r * r) continue;
      }
      if (x >= 0 && y >= 0 && x < image.width && y < image.height) {
        image.setPixel(x, y, c);
      }
    }
  }
}

/// A simplified "wifi, crossed out" badge: a circle, three stacked signal
/// arcs fanning above a dot (the universal wifi glyph, simplified to plain
/// arcs rather than true rounded strokes - crisp enough at icon sizes), and
/// a diagonal slash through the whole thing. [fillColor] is the badge's own
/// background fill (omitted on the transparent adaptive-icon foreground
/// layer, where only the ring/glyph/slash should paint).
void _fillWifiOffBadge(
  img.Image image, {
  required double centerX,
  required double centerY,
  required double outerRadius,
  required int ringColor,
  int? fillColor,
}) {
  final ring = _colorOf(ringColor);
  if (fillColor != null) {
    _fillCircle(image, centerX, centerY, outerRadius, _colorOf(fillColor));
  }
  final strokeThickness = outerRadius * 0.11;
  _strokeCircle(image, centerX, centerY, outerRadius, strokeThickness, ring);

  final fanCenterY = centerY + outerRadius * 0.18;
  for (final r in [outerRadius * 0.66, outerRadius * 0.44, outerRadius * 0.22]) {
    _strokeArc(
      image,
      centerX: centerX,
      centerY: fanCenterY,
      radius: r,
      thickness: strokeThickness,
      startDeg: 200,
      endDeg: 340,
      color: ring,
    );
  }
  _fillCircle(image, centerX, fanCenterY, outerRadius * 0.09, ring);

  _strokeDiagonal(
    image,
    centerX: centerX,
    centerY: centerY,
    radius: outerRadius * 1.15,
    thickness: strokeThickness * 1.3,
    color: ring,
  );
}

void _setPixelSafe(img.Image image, int x, int y, img.ColorRgba8 color) {
  if (x >= 0 && y >= 0 && x < image.width && y < image.height) {
    image.setPixel(x, y, color);
  }
}

void _fillCircle(img.Image image, double cx, double cy, double r, img.ColorRgba8 color) {
  final minX = (cx - r).floor(), maxX = (cx + r).ceil();
  final minY = (cy - r).floor(), maxY = (cy + r).ceil();
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      if (dx * dx + dy * dy <= r * r) _setPixelSafe(image, x, y, color);
    }
  }
}

void _strokeCircle(
  img.Image image,
  double cx,
  double cy,
  double radius,
  double thickness,
  img.ColorRgba8 color,
) {
  final outer = radius, inner = radius - thickness;
  final minX = (cx - outer).floor(), maxX = (cx + outer).ceil();
  final minY = (cy - outer).floor(), maxY = (cy + outer).ceil();
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      final d2 = dx * dx + dy * dy;
      if (d2 <= outer * outer && d2 >= inner * inner) _setPixelSafe(image, x, y, color);
    }
  }
}

void _strokeArc(
  img.Image image, {
  required double centerX,
  required double centerY,
  required double radius,
  required double thickness,
  required double startDeg,
  required double endDeg,
  required img.ColorRgba8 color,
}) {
  final outer = radius, inner = math.max(0.0, radius - thickness);
  final minX = (centerX - outer).floor(), maxX = (centerX + outer).ceil();
  final minY = (centerY - outer).floor(), maxY = (centerY + outer).ceil();
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x + 0.5 - centerX, dy = y + 0.5 - centerY;
      final d2 = dx * dx + dy * dy;
      if (d2 > outer * outer || d2 < inner * inner) continue;
      // atan2(dy, dx) with y-down image coords: 0=east, 90=south, 270=north.
      var angle = math.atan2(dy, dx) * 180 / math.pi;
      if (angle < 0) angle += 360;
      if (angle >= startDeg && angle <= endDeg) _setPixelSafe(image, x, y, color);
    }
  }
}

void _strokeDiagonal(
  img.Image image, {
  required double centerX,
  required double centerY,
  required double radius,
  required double thickness,
  required img.ColorRgba8 color,
}) {
  final dx = radius * math.cos(math.pi / 4);
  final dy = radius * math.sin(math.pi / 4);
  final x1 = centerX - dx, y1 = centerY - dy;
  final x2 = centerX + dx, y2 = centerY + dy;
  final minX = (math.min(x1, x2) - thickness).floor();
  final maxX = (math.max(x1, x2) + thickness).ceil();
  final minY = (math.min(y1, y2) - thickness).floor();
  final maxY = (math.max(y1, y2) + thickness).ceil();
  final len2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1);
  final halfThickness2 = (thickness / 2) * (thickness / 2);
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final px = x + 0.5, py = y + 0.5;
      var t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / len2;
      t = t.clamp(0.0, 1.0);
      final projX = x1 + t * (x2 - x1), projY = y1 + t * (y2 - y1);
      final ddx = px - projX, ddy = py - projY;
      if (ddx * ddx + ddy * ddy <= halfThickness2) {
        _setPixelSafe(image, x, y, color);
      }
    }
  }
}
