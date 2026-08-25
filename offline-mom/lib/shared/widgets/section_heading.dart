import 'package:flutter/material.dart';

/// A section title, optionally paired with a trailing text-button action
/// (e.g. "See all" / "Clear") in a space-between row. Three screens (Home,
/// Student Toolkit, Search) each hand-rolled this exact Row shape
/// independently before Batch 3, Design System Consolidation.
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    this.onAction,
    this.actionLabel = 'See all',
    this.dense = false,
  });

  final String title;
  final VoidCallback? onAction;
  final String actionLabel;

  /// Use the smaller (titleSmall) heading style, for lighter-weight
  /// sections such as "Recent searches".
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final heading = Text(title, style: dense ? textTheme.titleSmall : textTheme.titleMedium);
    if (onAction == null) return heading;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        heading,
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
