import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/theme/accent_colors.dart';
import 'package:offline_mom/core/theme/app_theme.dart';

/// WCAG 2.x relative-luminance contrast ratio between two opaque colors,
/// per https://www.w3.org/TR/WCAG21/#contrast-minimum. Phase 4A added
/// this specifically to catch a real, computed WCAG AA failure in
/// [AppTheme.heroGradient]'s original stops (white hero-card text/icons
/// measured 1.58:1/1.70:1 against the gradient's lighter two-thirds -
/// see ADR-031, docs/v2/implementation/03-decisions.md) - this test
/// guards against that regressing again, since nothing else in the type
/// system would catch a future gradient tweak reintroducing it.
double _linearize(int channel) {
  final c = channel / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) =>
    0.2126 * _linearize((color.r * 255).round()) +
    0.7152 * _linearize((color.g * 255).round()) +
    0.0722 * _linearize((color.b * 255).round());

double _contrastRatio(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  final lighter = math.max(l1, l2), darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Alpha-composites [fg] over an opaque [bg] (both already 0-255 int
/// channels via [Color]) - needed to evaluate `Colors.white70`'s *effective*
/// rendered color against a background, not its nominal (pre-blend) one.
Color _compositeOver(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1.0,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

void main() {
  group('AppTheme.heroGradient WCAG AA contrast (Phase 4A, ADR-031)', () {
    // Every accent color a user can actually select (Settings > Appearance)
    // - the gradient is seed-derived, so a fix verified only against the
    // default accent wouldn't guarantee every other option is safe too.
    for (final seed in AccentColors.extended) {
      final name = AccentColors.names[seed.toARGB32()] ?? seed.toString();

      test('$name: solid white passes 4.5:1 at every gradient stop', () {
        final scheme = AppTheme.dark(seed).colorScheme;
        final stops = AppTheme.heroGradient(scheme).colors;
        for (final (i, stop) in stops.indexed) {
          final ratio = _contrastRatio(Colors.white, stop);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'stop $i ($stop) only reaches ${ratio.toStringAsFixed(2)}:1 '
                'against solid white',
          );
        }
      });

      test('$name: Colors.white70 (the hero subtitle color) passes 4.5:1 '
          'at every gradient stop', () {
        final scheme = AppTheme.dark(seed).colorScheme;
        final stops = AppTheme.heroGradient(scheme).colors;
        for (final (i, stop) in stops.indexed) {
          final effective = _compositeOver(Colors.white70, stop);
          final ratio = _contrastRatio(effective, stop);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'stop $i ($stop) only reaches ${ratio.toStringAsFixed(2)}:1 '
                'against Colors.white70 (effective $effective)',
          );
        }
      });
    }
  });
}
