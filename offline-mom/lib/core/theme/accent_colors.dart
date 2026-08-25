import 'package:flutter/material.dart';

/// Preset accent colors offered on the Appearance screen, plus a slightly
/// larger set shown behind "Custom" - kept as fixed swatches rather than a
/// full color-wheel picker to avoid pulling in an extra dependency for a
/// cosmetic feature.
class AccentColors {
  AccentColors._();

  static const Color defaultAccent = Color(0xFF6D5FFD);
  static const int defaultAccentValue = 0xFF6D5FFD;

  static const List<Color> presets = [
    defaultAccent, // purple (default, matches the app's primary branding)
    Color(0xFF2196F3), // blue
    Color(0xFF2ECC71), // green
    Color(0xFFF5A623), // orange
    Color(0xFFE74C3C), // red
    Color(0xFFEC4899), // pink
  ];

  static const List<Color> extended = [
    ...presets,
    Color(0xFF00BCD4), // cyan
    Color(0xFF8BC34A), // light green
    Color(0xFFFFC107), // amber
    Color(0xFF795548), // brown
    Color(0xFF607D8B), // blue grey
    Color(0xFF9C27B0), // deep purple
  ];

  /// Human-readable name per swatch above, for TalkBack (Phase 4A) - a
  /// screen reader can't infer "purple" from an RGB value, so the color
  /// picker's `Semantics` labels read from this rather than duplicating the
  /// same name list a second time next to the widget that uses it. Keyed by
  /// ARGB int (`toARGB32()`), not `Color` itself - `Color` overrides `==`,
  /// which the const-map-key checker rejects (same reason
  /// `settings.accentColorValue` is already compared as an int elsewhere in
  /// this codebase, not as a `Color`).
  static const Map<int, String> names = {
    defaultAccentValue: 'Purple',
    0xFF2196F3: 'Blue',
    0xFF2ECC71: 'Green',
    0xFFF5A623: 'Orange',
    0xFFE74C3C: 'Red',
    0xFFEC4899: 'Pink',
    0xFF00BCD4: 'Cyan',
    0xFF8BC34A: 'Light green',
    0xFFFFC107: 'Amber',
    0xFF795548: 'Brown',
    0xFF607D8B: 'Blue grey',
    0xFF9C27B0: 'Deep purple',
  };
}
