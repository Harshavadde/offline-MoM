import 'package:flutter/material.dart';

import '../../core/utils/friendly_error.dart';
import 'empty_state.dart';

/// Shared empty/loading/error presentation for screens waiting on an
/// offline AI pipeline stage (Meeting Summary/MoM, Document Summary),
/// which all wait on the same "download model, then generate" shape and
/// can all fail the same way. Deliberately takes plain booleans rather
/// than a `MeetingStatus`/`DocumentStatus` enum so it isn't coupled to
/// either entity - each call site maps its own status enum to these three
/// flags locally (a trivial `switch`/`==`), which is simpler than a shared
/// translation layer for the two call sites that currently exist.
class AiPipelineFallback extends StatelessWidget {
  const AiPipelineFallback({
    super.key,
    required this.isDownloadingModel,
    required this.isGenerating,
    required this.hasError,
    required this.notReadyIcon,
    required this.notReadyTitle,
    required this.notReadyMessage,
    this.errorTitle = 'AI processing failed',
    this.errorDescription = 'Something went wrong while generating this content.',
    this.errorMessage,
    this.onRetry,
  });

  final bool isDownloadingModel;
  final bool isGenerating;
  final bool hasError;
  final IconData notReadyIcon;
  final String notReadyTitle;
  final String notReadyMessage;

  /// Headline shown when [hasError] is true. Defaults to a generic
  /// message; callers with a more specific failure (e.g. a meeting's
  /// missing audio file) pass their own.
  final String errorTitle;

  /// Friendly one-line description shown under [errorTitle].
  final String errorDescription;

  /// The actual exception message captured by the use case, when
  /// [hasError] is true. Shown so a failure is diagnosable instead of a
  /// dead end.
  final String? errorMessage;

  /// When provided, shows a "Retry" button that re-runs the pipeline from
  /// wherever it left off.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (isDownloadingModel) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Downloading the AI model…',
                style: TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'One-time download (~1.1 GB). Needs a working internet '
                'connection just this once - every summary after this '
                'runs fully offline. Wi-Fi is much faster than mobile '
                'data for this.',
                textAlign: TextAlign.center,
              ),
              ..._stuckRetryAffordance(context),
            ],
          ),
        ),
      );
    }
    if (isGenerating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Generating with on-device AI…'),
              ..._stuckRetryAffordance(context),
            ],
          ),
        ),
      );
    }
    if (hasError) {
      return _buildErrorState(
        context,
        title: errorTitle,
        message: errorDescription,
      );
    }
    return EmptyState(
      icon: notReadyIcon,
      title: notReadyTitle,
      message: notReadyMessage,
    );
  }

  /// Shared layout for [MeetingStatus.error] and [MeetingStatus.audioMissing] -
  /// both are terminal failures that show [errorMessage] (when available)
  /// and an optional [onRetry] button, differing only in their headline.
  Widget _buildErrorState(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    final onRetry = this.onRetry;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              icon: Icons.error_outline_rounded,
              title: title,
              message: message,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                // V2.2 Production Hardening, Priority 6 (real-device QA
                // finding): this previously showed the stored raw
                // exception text verbatim, in a monospace debug-console
                // style - `friendlyErrorMessage` translates it to plain
                // language; the raw text is unaffected in the database
                // (Meeting.errorMessage/Document.errorMessage) and in
                // whatever the originating use case already logs via
                // AppLogger, only what's shown here changes. No longer
                // monospace, since it's a plain sentence now, not a
                // technical dump.
                child: SelectableText(
                  friendlyErrorMessage(errorMessage!),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A small "stuck? retry" affordance shown under the in-progress spinner
  /// for [MeetingStatus.downloadingSummaryModel]/[MeetingStatus.summarizing]
  /// - not just [MeetingStatus.error]. This exists because the pipeline runs
  /// unawaited in the background: if Android kills the app process while
  /// it's backgrounded (very ordinary during a long download/generation),
  /// whatever was running simply stops existing - the meeting is left
  /// showing this exact "in progress" status forever, with nothing actually
  /// running behind it anymore. Without this, that was a genuine dead end:
  /// [onRetry] only ever appeared for [MeetingStatus.error]. Retrying from
  /// here is safe even if something IS still genuinely running, since
  /// neither stage has written its result yet at this point.
  List<Widget> _stuckRetryAffordance(BuildContext context) {
    final onRetry = this.onRetry;
    if (onRetry == null) return const [];
    return [
      const SizedBox(height: 20),
      Text(
        'Taking much longer than expected? This can happen if the app '
        'was closed or lost its connection mid-way.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
      ),
    ];
  }
}
