import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/background/background_download_service.dart';
import '../../../../shared/widgets/hero_icon.dart';
import '../providers/onboarding_providers.dart';

/// First-run, mandatory model download: the app is not usable (no route
/// other than this one is reachable) until the selected AI models are
/// downloaded and cached, so the very first recording/import/question
/// afterward runs with no surprise wait. See [OnboardingSetupState] for
/// why this has no skip option, unlike [WelcomeNameScreen].
class ModelSetupScreen extends ConsumerWidget {
  const ModelSetupScreen({super.key});

  // Ordered least -> most accurate; downloadModels() picks the last
  // selected entry here as the new active model if the previous default
  // wasn't part of the selection. `recommended` is presentation-only
  // (Phase 9.2 - drives the "Recommended" badge below); it doesn't change
  // which entries can be selected or how the download itself works.
  static const _whisperModels = [
    (
      name: 'tiny',
      label: 'Tiny',
      size: '~75 MB',
      note: 'Fastest, least accurate',
      recommended: false,
    ),
    (name: 'base', label: 'Base', size: '~140 MB', note: 'Balanced', recommended: false),
    (
      name: 'small',
      label: 'Small',
      size: '~460 MB',
      note: 'Noticeably better for Indian-language recordings than Base',
      recommended: true,
    ),
  ];

  List<String> _orderedSelection(Set<String> selected) =>
      [for (final m in _whisperModels) if (selected.contains(m.name)) m.name];

  String _labelFor(String modelName) => _whisperModels
      .firstWhere((m) => m.name == modelName, orElse: () => _whisperModels.first)
      .label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsControllerProvider);
    final settingsNotifier = ref.read(settingsControllerProvider.notifier);
    final setupState = ref.watch(onboardingSetupControllerProvider);
    final isDownloading = setupState is OnboardingSetupDownloading;
    final selected = ref.watch(selectedWhisperModelsProvider);

    ref.listen(onboardingSetupControllerProvider, (previous, next) {
      if (next is OnboardingSetupDone) {
        context.go(RoutePaths.home);
      }
    });

    void startDownload() => ref
        .read(onboardingSetupControllerProvider.notifier)
        .downloadModels(_orderedSelection(selected));

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Phase 9.2 (AI Model Setup polish): a hero icon consistent
            // with the intro screen's visual language, plus a tightened,
            // consumer-facing explanation of *why* this step exists and
            // roughly what it costs (storage + time), stated honestly
            // rather than with a fabricated precise ETA - actual speed
            // depends entirely on the user's connection.
            const Center(
              child: HeroIcon(icon: Icons.auto_awesome_rounded, iconSize: 34),
            ),
            const SizedBox(height: 20),
            Text(
              'Set up your AI',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'A one-time download so recording, chatting, and summarizing '
              'all work fully offline afterward. This downloads the '
              'speech-to-text model you pick below, plus a ~1.1 GB AI '
              'model used for summaries and chat - usually just a few '
              'minutes on Wi-Fi.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 28),
            Text('Speech-to-text model', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pick one or more sizes - each only needs to download once, '
              'so switching later in Settings is instant instead of a '
              'fresh download.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            for (final model in _whisperModels) ...[
              _ModelOptionCard(
                label: model.label,
                size: model.size,
                note: model.note,
                recommended: model.recommended,
                selected: selected.contains(model.name),
                enabled: !isDownloading,
                onChanged: (checked) {
                  final updated = Set<String>.of(selected);
                  if (checked) {
                    updated.add(model.name);
                  } else if (updated.length > 1) {
                    // At least one model must stay selected.
                    updated.remove(model.name);
                  }
                  ref.read(selectedWhisperModelsProvider.notifier).state = updated;
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SwitchListTile(
                  value: settings.allowBackgroundDownloads,
                  onChanged: isDownloading
                      ? null
                      : (value) {
                          settingsNotifier.setAllowBackgroundDownloads(value);
                          if (value) BackgroundDownloadService.requestPermission();
                        },
                  title: const Text('Keep downloading in the background'),
                  subtitle: Text(
                    settings.allowBackgroundDownloads
                        ? 'On: the download keeps running if you switch to '
                            'another app. Android requires showing a small '
                            'ongoing notification while this is active - '
                            'that\'s how background work stays alive on '
                            'Android, not something else we\'re tracking.'
                        : 'Off (default): please keep this screen open '
                            'until the download finishes. Switching apps or '
                            'turning off the screen may pause it, since '
                            'Android suspends apps that aren\'t in the '
                            'foreground. You can change this later in '
                            'Settings.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            switch (setupState) {
              OnboardingSetupIdle() => FilledButton.icon(
                  onPressed: selected.isEmpty ? null : startDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download & Continue'),
                ),
              OnboardingSetupDownloading(:final sttFractions, :final llmFraction) => Column(
                  children: [
                    for (final entry in sttFractions.entries) ...[
                      _DownloadProgressRow(
                        label: 'Speech-to-text (${_labelFor(entry.key)})',
                        fraction: entry.value,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _DownloadProgressRow(label: 'AI language model', fraction: llmFraction),
                    const SizedBox(height: 8),
                    Text(
                      'Downloading everything at the same time - this can '
                      'take a while depending on your connection.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              OnboardingSetupFailed(:final message, :final wasPaused) => Column(
                  children: [
                    // R-11 P0 fix: a stall/backgrounding-induced timeout
                    // previously looked identical to a genuine failure (red
                    // error box, generic "Retry") - on a real device, with
                    // no foreground service keeping the connection alive
                    // while backgrounded, this is the common case, not the
                    // exceptional one, and every one of these downloads
                    // genuinely resumes from where it left off rather than
                    // restarting - see `OnboardingSetupFailed.wasPaused`'s
                    // own doc comment. This mirrors the post-onboarding
                    // Model Manager's existing, correct `ModelDownloadPaused`
                    // treatment (`model_details_screen.dart`).
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: wasPaused ? scheme.secondaryContainer : scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: wasPaused
                          ? Text(
                              'Download paused - your progress was saved. Tap Resume to '
                              'continue from where you left off.',
                              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
                            )
                          : SelectableText(
                              message,
                              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                            ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: startDownload,
                      icon: Icon(wasPaused ? Icons.play_arrow_rounded : Icons.refresh_rounded),
                      label: Text(wasPaused ? 'Resume' : 'Retry'),
                    ),
                  ],
                ),
              OnboardingSetupDone() => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }
}

/// One selectable Whisper size, reskinned as a tappable option card
/// (Phase 9.2) instead of a bare [CheckboxListTile] - same selection
/// semantics (tapping anywhere toggles it, [onChanged] carries the new
/// checked state), just presented like a consumer app's plan/tier picker
/// rather than a settings-panel checklist. [recommended] shows a small
/// badge next to the title; it's purely visual and doesn't change what a
/// user can select.
class _ModelOptionCard extends StatelessWidget {
  const _ModelOptionCard({
    required this.label,
    required this.size,
    required this.note,
    required this.recommended,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String size;
  final String note;
  final bool recommended;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? () => onChanged(!selected) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: Theme.of(context).textTheme.titleSmall),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$size · $note',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: selected,
                onChanged: enabled ? (checked) => onChanged(checked ?? false) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One model's row inside the multi-download progress view - a label, a
/// live percentage (or an indeterminate state before the total size is
/// known), and a progress bar.
class _DownloadProgressRow extends StatelessWidget {
  const _DownloadProgressRow({required this.label, required this.fraction});

  final String label;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final done = fraction != null && fraction! >= 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              done
                  ? 'Done'
                  : fraction == null
                      ? '…'
                      : '${(fraction! * 100).round()}%',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: fraction),
        ),
      ],
    );
  }
}
