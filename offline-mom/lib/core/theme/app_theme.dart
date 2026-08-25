import 'package:flutter/material.dart';

import 'accent_colors.dart';

/// Material 3 theme definitions for OfflineMoMAI.
///
/// A single seed color drives both the light and dark [ColorScheme]s so the
/// two themes stay visually consistent (same brand hue, different tone).
/// The seed is user-configurable (Settings -> Appearance), defaulting to
/// [AccentColors.defaultAccent].
class AppTheme {
  AppTheme._();

  static ThemeData light([Color seedColor = AccentColors.defaultAccent]) =>
      _buildTheme(
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      );

  static ThemeData dark([Color seedColor = AccentColors.defaultAccent]) =>
      _buildTheme(
        // Material 3's own dark tonal palette keeps `surface` a fairly
        // light charcoal for contrast-safety reasons - deliberately
        // overridden here to a true near-black (with a faint accent tint)
        // to match the app's actual visual identity, which leans on rich
        // dark backgrounds behind glowing accent-color elements rather
        // than a neutral charcoal.
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF0E0B16),
          surfaceContainerLowest: const Color(0xFF0A0812),
          surfaceContainerLow: const Color(0xFF14101F),
          surfaceContainer: const Color(0xFF191428),
          surfaceContainerHigh: const Color(0xFF201A31),
          surfaceContainerHighest: const Color(0xFF261F3A),
        ),
      );

  /// The rich, diagonal accent-to-near-black gradient used behind the
  /// app's few "hero" elements (Home's Record card, its glowing mic
  /// button, the onboarding mic icon) - derived from the active accent
  /// color rather than a fixed purple, so it still respects the user's
  /// Appearance > accent choice.
  ///
  /// All three stops are deliberately darkened relative to [scheme.primary]
  /// itself (Phase 4A) - every hero element places solid-white text/icons
  /// (and one `Colors.white70` subtitle) directly over this gradient, and
  /// `scheme.primary` in Material 3's dark tonal palette is, by design, a
  /// *light* pastel tone (meant to read as an accent against a dark
  /// surface, not as a background for white text). Computed against this
  /// app's default accent (`AccentColors.defaultAccent`): the original
  /// stops (`primary` lightened 12% -> `primary` -> `primary` darkened
  /// 55%) measured 1.58:1/1.70:1 (light/mid stops) against solid white -
  /// far under WCAG AA's 4.5:1 for normal text - only the darkest stop
  /// (6.99:1) passed. These stops (darkened 60%/68%/78%) measure
  /// 8.1:1/9.7:1/12.7:1 against solid white and 5.0:1/5.9:1/7.5:1 against
  /// `Colors.white70`, comfortably passing AA at every point along the
  /// gradient, not just its darkest end - still a visible diagonal
  /// gradient, just shifted into a tonal range this app's actual text
  /// content can sit on safely. Verified by computed WCAG relative-
  /// luminance contrast ratios against this specific gradient's colors,
  /// not by real-device/TalkBack testing (unavailable in this
  /// implementation environment - see ADR-031,
  /// docs/v2/implementation/03-decisions.md); re-verified at every stop,
  /// against both solid white and `Colors.white70`, for all 12 selectable
  /// accent colors in [AccentColors.extended] (not just this app's
  /// default), by `test/core/theme/app_theme_test.dart`.
  static LinearGradient heroGradient(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(scheme.primary, Colors.black, 0.60)!,
          Color.lerp(scheme.primary, Colors.black, 0.68)!,
          Color.lerp(scheme.primary, Colors.black, 0.78)!,
        ],
      );

  static ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    return const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(height: 1.4),
      bodyMedium: TextStyle(height: 1.4),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
  }
}
