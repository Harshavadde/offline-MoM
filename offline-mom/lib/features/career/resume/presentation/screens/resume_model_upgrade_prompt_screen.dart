import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../models/ai_model_spec.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/ai/model_catalog.dart';
import '../../../../../services/ai/model_lifecycle_manager.dart' show ModelKind;
import '../../../../../shared/utils/format_utils.dart';
import '../../../../ai_models/presentation/providers/installed_models_providers.dart';
import '../../../../ai_models/presentation/providers/model_download_providers.dart';

/// The one-time "get better resume results" model-upgrade prompt
/// (docs/v3/01-prd.md §13, FR3-15/FR3-16, Milestone 4), shown before first
/// entering the Resume feature - see [ResumeListScreen]'s own gate, which
/// checks [AppSettings.hasSeenResumeModelUpgradePrompt] and calls this.
///
/// A dialog, not a full route - the PRD's own "screen (or dialog widget,
/// implementer's choice)". Reuses the *existing* AI Model Manager
/// download/activate machinery unchanged ([ModelDownloadController]/
/// [InstalledModelsController], the same pair [ModelDetailsScreen] and
/// `ProfessionSetupController` already build on) rather than introducing a
/// second way to download a model. Declining (tapping "Not now" or
/// dismissing) never blocks the Resume feature - only [markResumeModelUpgradePromptSeen]
/// is called either way, so the prompt never shows again (FR3-16).
Future<void> showResumeModelUpgradePromptDialog(BuildContext context, WidgetRef ref) async {
  final upgradeTier = ModelCatalog.forKind(ModelKind.llm).where((m) => !m.isDefault).toList();
  if (upgradeTier.isEmpty) {
    // No optional tier defined in the catalog - nothing to offer. Still
    // marks the prompt seen so this check isn't repeated on every entry.
    await ref.read(settingsControllerProvider.notifier).markResumeModelUpgradePromptSeen();
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (_) => _ResumeModelUpgradeDialog(spec: upgradeTier.first),
  );
  if (context.mounted) {
    await ref.read(settingsControllerProvider.notifier).markResumeModelUpgradePromptSeen();
  }
}

class _ResumeModelUpgradeDialog extends ConsumerStatefulWidget {
  const _ResumeModelUpgradeDialog({required this.spec});

  final AiModelSpec spec;

  @override
  ConsumerState<_ResumeModelUpgradeDialog> createState() => _ResumeModelUpgradeDialogState();
}

class _ResumeModelUpgradeDialogState extends ConsumerState<_ResumeModelUpgradeDialog> {
  bool _activated = false;

  /// Set when the download succeeds but `activate()`'s own verification
  /// step (reliability-overhaul pass, Phase 14/17) fails - rendered
  /// through the same visible error/Retry path as a real
  /// [ModelDownloadFailed], never silently left as an unexplained "not
  /// activated" state.
  String? _activationError;

  /// Mirrors `ProfessionSetupController`'s own download-then-activate
  /// sequence exactly: start the existing download machinery, only
  /// activate if it didn't fail - never silently activate a model that was
  /// never actually installed.
  Future<void> _downloadAndActivate() async {
    setState(() => _activationError = null);
    final downloadController = ref.read(modelDownloadControllerProvider.notifier);
    await downloadController.start(widget.spec);
    if (!mounted) return;
    if (downloadController.stateFor(widget.spec.id) is ModelDownloadFailed) return;
    final activated = await ref
        .read(installedModelsControllerProvider.notifier)
        .activate(ModelKind.llm, widget.spec.id);
    if (!mounted) return;
    if (!activated) {
      setState(() => _activationError =
          '${widget.spec.displayName} downloaded but failed verification. Please try again.');
      return;
    }
    setState(() => _activated = true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final downloadState =
        ref.watch(modelDownloadControllerProvider)[widget.spec.id] ?? const ModelDownloadIdle();
    final tierAsync = ref.watch(resumeRecommendedDeviceTierProvider);

    late final Widget content;
    late final List<Widget> actions;

    if (_activated) {
      content = Text('${widget.spec.displayName} is downloaded and now in use for resume '
          'suggestions.');
      actions = [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ];
    } else if (downloadState is ModelDownloadInProgress) {
      final fraction = downloadState.fraction;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Downloading ${widget.spec.displayName}…'),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: fraction),
          ),
        ],
      );
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue in background'),
        ),
      ];
    } else if (downloadState is ModelDownloadFailed || _activationError != null) {
      final failedDownloadMessage = downloadState is ModelDownloadFailed ? downloadState.message : null;
      content = Text(
        _activationError ?? failedDownloadMessage ?? 'Something went wrong. Please try again.',
        style: TextStyle(color: scheme.error),
      );
      actions = [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
        FilledButton(onPressed: _downloadAndActivate, child: const Text('Retry')),
      ];
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For better resume results, you can download the recommended '
            'model. Once downloaded, it stays on your device and works '
            'offline.',
          ),
          const SizedBox(height: 12),
          Text(
            '${widget.spec.displayName} · ~${formatFileSize(widget.spec.sizeBytesApprox)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'The current model keeps working fully if you skip this - only '
            'suggestion quality is affected.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          tierAsync.when(
            data: (tier) => tier == RecommendedDeviceTier.anyModernPhone
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'This model works best on higher-RAM devices - it will still '
                      'run here, just more slowly.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      );
      actions = [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
        FilledButton.icon(
          onPressed: _downloadAndActivate,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Download'),
        ),
      ];
    }

    return AlertDialog(
      title: const Text('Get better resume results'),
      content: content,
      actions: actions,
    );
  }
}
