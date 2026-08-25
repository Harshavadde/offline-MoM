import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/ai_model_spec.dart';
import '../../../../models/installed_model.dart';
import '../../../../services/ai/model_catalog.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../providers/installed_models_providers.dart';
import '../providers/model_download_providers.dart';

/// Model Details (Phase 6A objective 5) - everything [AiModelSpec] and
/// [InstalledModel] know about one model, plus every lifecycle action
/// (Download/Pause/Resume/Delete/Verify/Activate) for it in one place.
class ModelDetailsScreen extends ConsumerStatefulWidget {
  const ModelDetailsScreen({super.key, required this.modelId});

  final String modelId;

  @override
  ConsumerState<ModelDetailsScreen> createState() => _ModelDetailsScreenState();
}

class _ModelDetailsScreenState extends ConsumerState<ModelDetailsScreen> {
  @override
  void initState() {
    super.initState();
    // Beta blocker fix (docs/v3/implementation/03-decisions.md): opening
    // this screen after a cold app restart (the OS killed the process
    // while a download was backgrounded) previously showed "Not
    // downloaded" / a plain "Download" button even when a resumable
    // `.part` file with real progress already existed on disk - this
    // screen had no way to know about it, since
    // `ModelDownloadController`'s state map only exists for the lifetime
    // of that Notifier. Checking once here seeds an accurate `Paused`
    // state (and its real byte count) from disk, so the existing
    // Resume affordance is correct immediately instead of the user
    // tapping "Download" and perceiving it as starting over.
    final spec = ModelCatalog.byId(widget.modelId);
    if (spec != null) {
      Future.microtask(
        () => ref.read(modelDownloadControllerProvider.notifier).checkForResumableDownload(spec),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = ModelCatalog.byId(widget.modelId);
    if (spec == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Model')),
        body: const Center(child: Text('This model is no longer available.')),
      );
    }

    final installedAsync = ref.watch(installedModelsControllerProvider);
    final installed = installedAsync.valueOrNull?.where((m) => m.modelId == widget.modelId).firstOrNull;
    final downloadState =
        ref.watch(modelDownloadControllerProvider)[widget.modelId] ?? const ModelDownloadIdle();

    return Scaffold(
      appBar: AppBar(title: Text(spec.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(spec.description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          _SpecTable(spec: spec, installed: installed),
          const SizedBox(height: 16),
          _StatusSection(spec: spec, installed: installed, downloadState: downloadState),
          const SizedBox(height: 24),
          _ActionButtons(spec: spec, installed: installed, downloadState: downloadState),
        ],
      ),
    );
  }
}

class _SpecTable extends StatelessWidget {
  const _SpecTable({required this.spec, required this.installed});

  final AiModelSpec spec;
  final InstalledModel? installed;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Size', formatFileSize(spec.sizeBytesApprox)),
      if (spec.quantization != null) ('Quantization', spec.quantization!),
      ('RAM required', '~${spec.ramRequirementMb} MB'),
      ('Estimated speed', spec.speedTier.name),
      (
        'Recommended device',
        spec.recommendedDeviceTier == RecommendedDeviceTier.highRamDevice
            ? 'Higher-RAM phone/tablet'
            : 'Any modern phone',
      ),
      ('Capabilities', spec.capabilities.join(', ')),
      ('License', spec.license),
      ('Version', spec.version),
      if (installed != null) ('Installed size', formatFileSize(installed!.sizeBytes)),
      if (installed != null) ('Installed on', installed!.downloadedAt.toLocal().toString().split('.').first),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 140, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
                    Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.spec, required this.installed, required this.downloadState});

  final AiModelSpec spec;
  final InstalledModel? installed;
  final ModelDownloadState downloadState;

  @override
  Widget build(BuildContext context) {
    if (downloadState is ModelDownloadInProgress) {
      final s = downloadState as ModelDownloadInProgress;
      final fraction = s.fraction;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Downloading…'),
              Text(fraction == null ? '…' : '${(fraction * 100).round()}%'),
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
    if (downloadState is ModelDownloadVerifying) {
      return const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Verifying…')]);
    }
    if (downloadState is ModelDownloadPaused) {
      return const Text('Paused - resume to continue from where it left off.');
    }
    if (downloadState is ModelDownloadFailed) {
      return Text(
        (downloadState as ModelDownloadFailed).message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    if (installed != null) {
      return Text(installed!.isActive ? 'Installed and active.' : 'Installed.');
    }
    return const Text('Not downloaded.');
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.spec, required this.installed, required this.downloadState});

  final AiModelSpec spec;
  final InstalledModel? installed;
  final ModelDownloadState downloadState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadController = ref.read(modelDownloadControllerProvider.notifier);
    final installedController = ref.read(installedModelsControllerProvider.notifier);

    final buttons = <Widget>[];

    if (downloadState is ModelDownloadInProgress) {
      buttons.add(
        FilledButton.tonalIcon(
          onPressed: () => downloadController.pause(spec.id),
          icon: const Icon(Icons.pause),
          label: const Text('Pause'),
        ),
      );
    } else if (downloadState is ModelDownloadPaused) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => downloadController.start(spec),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
        ),
      );
      buttons.add(
        OutlinedButton(
          onPressed: () => downloadController.cancelAndDiscard(spec),
          child: const Text('Cancel download'),
        ),
      );
    } else if (installed == null) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => downloadController.start(spec),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Download'),
        ),
      );
    } else {
      if (!installed!.isActive) {
        buttons.add(
          FilledButton.icon(
            onPressed: () async {
              final activated = await installedController.activate(spec.kind, spec.id);
              if (!activated && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${spec.displayName} failed verification and could not be activated. '
                      'Try Verify, or delete and re-download it.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Activate'),
          ),
        );
      }
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => downloadController.verify(spec, installed!),
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Verify'),
        ),
      );
      buttons.add(
        OutlinedButton.icon(
          onPressed: () async {
            final confirmed = await showDestructiveConfirmDialog(
              context,
              title: 'Delete ${spec.displayName}?',
              message: 'This removes the model from your device. You can download it '
                  'again later.',
            );
            if (confirmed) await installedController.delete(installed!);
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete'),
        ),
      );
    }

    return Wrap(spacing: 12, runSpacing: 12, children: buttons);
  }
}
