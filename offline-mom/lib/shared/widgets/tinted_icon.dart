import 'package:flutter/material.dart';

/// An icon inside a small rounded, tinted square - the app's standard way
/// of presenting a leading icon in a list row (Settings rows, quick
/// actions, etc.), matching the reference design's look instead of a bare
/// [Icon]. Color defaults to the theme's primary container so it adapts to
/// the user's chosen accent color (Settings > Appearance) automatically.
class TintedIcon extends StatelessWidget {
  const TintedIcon(
    this.icon, {
    super.key,
    this.size = 40,
    this.iconSize = 20,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: foreground ?? scheme.onPrimaryContainer,
      ),
    );
  }
}
