import 'package:flutter/material.dart';

/// A reusable, friendly empty-state layout: icon, headline, supporting text
/// and optional action(s). Used any time a screen has nothing to show yet
/// (no meetings, no search results, a feature not wired up yet) - and, as
/// of Batch 3 (Design System Consolidation), also for "pick a file to get
/// started" prompts that need more than one entry point (e.g. Scanner's
/// Capture/Import/Add-one-photo), which previously hand-rolled this exact
/// icon-title-message-buttons shape from scratch rather than reusing this
/// widget.
///
/// [actionLabel]/[onAction] (a single primary button) is kept for every
/// existing single-action call site; pass [actions] instead for more than
/// one button. Rendered as a plain vertical stack with no imposed spacing
/// of its own - callers include their own `SizedBox`s between entries,
/// matching what every multi-button prompt this replaces already did by
/// hand (a primary/secondary/tertiary stack, not evenly spaced). Passing
/// both is not a supported combination - [actions] takes precedence if
/// both are given.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final resolvedActions = actions ??
        (actionLabel != null && onAction != null
            ? [FilledButton(onPressed: onAction, child: Text(actionLabel!))]
            : null);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (resolvedActions != null && resolvedActions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Column(mainAxisSize: MainAxisSize.min, children: resolvedActions),
            ],
          ],
        ),
      ),
    );
  }
}
