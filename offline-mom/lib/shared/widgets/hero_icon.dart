import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The app's one "hero moment" icon treatment (Batch 3, Design System
/// Consolidation) - a circular [AppTheme.heroGradient] with a single icon,
/// used across every onboarding screen (Splash, Why Offline, Welcome/Name,
/// Model Setup). Each of those four screens used to build this
/// `Container`+`BoxDecoration` by hand, with Splash and Why Offline's
/// `boxShadow` glow drifting slightly out of sync (0.35 vs. 0.4 alpha) -
/// a small, real inconsistency exactly of the kind this consolidation
/// pass exists to remove, not a redesign of the look itself.
class HeroIcon extends StatelessWidget {
  const HeroIcon({
    super.key,
    required this.icon,
    this.size = 72,
    this.iconSize,
    this.glow = false,
  });

  final IconData icon;
  final double size;

  /// Defaults to half of [size] (the ratio Splash/Why Offline's 88px
  /// icons already used) - pass explicitly for a different ratio, as
  /// Model Setup/Welcome Name's 72px circles do (34px icon, not 36).
  final double? iconSize;

  /// The soft glow behind Splash/Why Offline's larger circles - omitted
  /// on Model Setup/Welcome Name's smaller ones, matching how each
  /// screen already looked before this widget existed.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.heroGradient(scheme),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Icon(icon, size: iconSize ?? size * 0.5, color: Colors.white),
    );
  }
}
