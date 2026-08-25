import 'package:flutter/material.dart';

import '../../core/utils/friendly_error.dart';

/// A compact, single-line error message for a section embedded inside a
/// larger scrollable screen (e.g. Home's "Recent Meetings" section) where
/// the full [EmptyState] treatment would be too heavy. Always renders
/// [error] through [friendlyErrorMessage] - never the raw exception text.
class InlineErrorText extends StatelessWidget {
  const InlineErrorText(this.error, {super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            friendlyErrorMessage(error),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
