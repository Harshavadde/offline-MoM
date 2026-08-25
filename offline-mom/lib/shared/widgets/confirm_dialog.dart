import 'package:flutter/material.dart';

/// Shows the app's one destructive-confirmation dialog shape (Phase 4A,
/// ADR-031, docs/v2/implementation/03-decisions.md) - every "delete this
/// permanently" prompt in the app (meetings, documents, chat conversations,
/// notes) used to build its own near-identical `AlertDialog` with a plain
/// `FilledButton`, which was both duplicated widget code and meant "Delete"
/// and "Save" looked visually identical (no color distinguishing a
/// destructive action from a routine one). This is the single shared
/// version: `Cancel` stays a plain [TextButton], the destructive action is a
/// [FilledButton] styled with [ColorScheme.error]/[ColorScheme.onError] -
/// guaranteed WCAG-AA-contrasting against each other, since Material 3's
/// `ColorScheme.fromSeed` derives `onError` specifically to meet that bar
/// against `error`.
///
/// Returns `true` only if the user tapped the destructive action; `false`
/// for Cancel *or* dismissal (tapping outside, back button) - callers should
/// never need to distinguish those two "didn't confirm" cases.
Future<bool> showDestructiveConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
