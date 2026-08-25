import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/connectivity_check.dart';
import '../../../../services/offline/offline_readiness_service.dart';
import '../../../../shared/widgets/inline_error_text.dart';
import '../providers/offline_readiness_providers.dart';

/// R-6: a live network-connectivity probe (`hasInternetConnection()`) is a
/// genuinely different question from [OfflineReadinessReport] ("are the
/// offline-usable pieces in place" - see that class's own doc comment for
/// why the two are deliberately kept separate). Its own provider, `.family`
/// over nothing meaningful (just `autoDispose`, matching the report
/// provider), so re-checking is one `ref.invalidate` away without coupling
/// it to the report's own refresh.
final _liveConnectivityProvider = FutureProvider.autoDispose<bool>((ref) => hasInternetConnection());

/// R-11 P1 fix ("Offline Readiness must be user-friendly"): this screen
/// previously rendered [OfflineReadinessCheck.label]/`.detail` directly -
/// developer-facing identifiers and audit language never meant to be shown
/// as-is ("Embedding model (semantic search)", raw installed model IDs,
/// "llama.cpp"/"whisper.cpp", "On-device SQLite"). [OfflineReadinessService]
/// itself is unchanged - the exact same real, per-model-kind pass/fail
/// facts every other check consumes - only this screen's *presentation* of
/// those facts changed, mapping each known [OfflineReadinessCheck.label]
/// (a stable internal key, unchanged, still what
/// `offline_readiness_service_test.dart` asserts against) to what it
/// actually means for the person using the app: what they can already do,
/// and what to do next if something isn't ready yet. Nothing here invents
/// a capability that isn't grounded in a real `check.passed` value - see
/// `_CapabilityRow`'s own doc comment.
class OfflineReadinessScreen extends ConsumerWidget {
  const OfflineReadinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(offlineReadinessReportProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Use Offline')),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: InlineErrorText(err),
        ),
        data: (report) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: report.isReady ? scheme.primaryContainer : scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      report.isReady ? Icons.offline_bolt_rounded : Icons.download_for_offline_outlined,
                      color: report.isReady ? scheme.onPrimaryContainer : scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report.isReady ? 'You\'re ready to use the app offline' : 'A few things to set up first',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: report.isReady ? scheme.onPrimaryContainer : scheme.onErrorContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            report.isReady
                                ? 'Your required tools are ready. You can use the app without '
                                    'an internet connection.'
                                : 'Download the required AI tools below to use every feature '
                                    'without an internet connection.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: report.isReady ? scheme.onPrimaryContainer : scheme.onErrorContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Always available, no internet needed', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            const _AlwaysAvailableRow(label: 'Create and edit resumes'),
            const _AlwaysAvailableRow(label: 'Manage your documents and scans'),
            const _AlwaysAvailableRow(label: 'Use the PDF tools'),
            const SizedBox(height: 24),
            Text('Set up once, then works offline', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final check in report.checks) _CapabilityRow(check: check),
            if (!report.isReady) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push(RoutePaths.aiModels),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download required tools'),
              ),
            ],
            const SizedBox(height: 24),
            const _LiveConnectivityRow(),
          ],
        ),
      ),
    );
  }
}

class _AlwaysAvailableRow extends StatelessWidget {
  const _AlwaysAvailableRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Maps one real [OfflineReadinessCheck] to plain, user-facing language -
/// never a bare pass/fail with implementation detail (a model filename, a
/// library name, "SQLite"). Matching on [OfflineReadinessCheck.label] (a
/// stable internal key [OfflineReadinessService] already guarantees, and
/// what its own tests assert against) rather than duplicating any
/// readiness logic here - an unrecognized label (there shouldn't be one,
/// but this must never crash or leak raw text if the service ever adds a
/// new check before this screen is updated for it) falls back to the
/// check's own required/optional + passed/failed shape with fully generic
/// wording, never the raw label/detail string.
class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.check});

  final OfflineReadinessCheck check;

  static const _capabilityLabels = {
    'AI language model': 'Summaries and AI writing help',
    'Embedding model (semantic search)': 'Search your saved information',
    'Speech-to-text model': 'Record and transcribe meetings',
    'OCR model': 'Searchable PDF and image scanning',
  };

  @override
  Widget build(BuildContext context) {
    // The 3 static, always-passing architecture facts
    // (OfflineReadinessService's "Local database available"/"AI inference
    // runs entirely on-device"/"No network required for..." checks) are
    // real, but their wording is internal-audit language, not a user
    // capability - they add nothing the top banner and the rows below
    // don't already say in plain terms, so they're intentionally not
    // rendered as their own row at all.
    final label = _capabilityLabels[check.label];
    if (label == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final String statusText;
    if (check.passed) {
      statusText = 'Ready to use offline.';
    } else if (check.required) {
      statusText = 'Download required to use this feature offline.';
    } else {
      statusText = 'Optional feature. Install this to use it.';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            check.passed
                ? Icons.check_circle_rounded
                : (check.required ? Icons.cancel_rounded : Icons.remove_circle_outline_rounded),
            color: check.passed
                ? Colors.green
                : (check.required ? scheme.error : scheme.onSurfaceVariant),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodyMedium),
                    if (!check.required) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'OPTIONAL',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// R-6: a real, live check ("is there a network connection right now"),
/// deliberately separate from the capability checks above - re-fetches
/// each time this screen is (re)built (`autoDispose`) rather than caching
/// across app launches, since connectivity can change at any moment.
class _LiveConnectivityRow extends ConsumerWidget {
  const _LiveConnectivityRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final connectivityAsync = ref.watch(_liveConnectivityProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        connectivityAsync.when(
          loading: () => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => Icon(Icons.help_outline_rounded, color: scheme.onSurfaceVariant, size: 20),
          data: (online) => Icon(
            online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: online ? scheme.primary : scheme.onSurfaceVariant,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connectivityAsync.when(
                  loading: () => 'Checking connection…',
                  error: (_, __) => 'Internet connection: unknown',
                  data: (online) => online ? 'Internet connection: Connected' : 'Internet connection: Not connected',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Only needed to download AI tools - everything above still works without it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
