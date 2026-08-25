import 'package:flutter/material.dart';

import '../../core/utils/friendly_error.dart';
import 'empty_state.dart';

/// The app's one full-screen/full-section "this failed to load" shape
/// (Batch 3, Design System Consolidation) - every list/detail screen's
/// `AsyncValue.error` branch used to repeat the same three lines
/// (`EmptyState(icon: Icons.error_outline_rounded, title: ..., message:
/// friendlyErrorMessage(err))`) more than a dozen times over, a pattern
/// this project's own V2.1 hardening pass introduced everywhere at once
/// when it swept out raw exception text - genuinely duplicated, not
/// merely similar. Thin wrapper around [EmptyState]; never shows [error]
/// raw, always through [friendlyErrorMessage].
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.title, required this.error});

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: title,
      message: friendlyErrorMessage(error),
    );
  }
}
