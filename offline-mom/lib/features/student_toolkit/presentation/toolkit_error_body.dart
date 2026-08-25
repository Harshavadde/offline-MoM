import 'package:flutter/material.dart';

/// The "processing failed" shape shared by Image Compress, Image Resize,
/// and PDF Compress (Batch 3, Design System Consolidation) - a bare error
/// icon, the (already hand-authored, tool-specific) failure message, a
/// "Try again" retry, and a "Pick a different <thing>" escape hatch.
/// Deliberately distinct from the shared EmptyState/ErrorState widgets (no
/// title, no tinted-circle icon treatment) rather than forced into that
/// shape - this one never had a title, and inventing one to fit a
/// different widget's contract isn't a genuine consolidation.
class ToolkitErrorBody extends StatelessWidget {
  const ToolkitErrorBody({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onPickAgain,
    required this.pickAgainLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onPickAgain;
  final String pickAgainLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            const SizedBox(height: 8),
            TextButton(onPressed: onPickAgain, child: Text(pickAgainLabel)),
          ],
        ),
      ),
    );
  }
}
