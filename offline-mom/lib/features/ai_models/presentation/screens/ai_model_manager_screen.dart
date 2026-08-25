import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../models/ai_model_spec.dart';
import '../../../../models/installed_model.dart';
import '../../../../models/profession_profile.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/model_catalog.dart';
import '../../../../services/ai/model_lifecycle_manager.dart';
import '../../../../services/background/background_download_service.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/tinted_icon.dart';
import '../providers/installed_models_providers.dart';
import '../providers/model_download_providers.dart';
import '../providers/model_storage_providers.dart';
import '../providers/profession_setup_providers.dart';

/// The AI Model Manager's home screen (Phase 6A, ADR-036) - Model Download
/// Center, Installed Models, Available Models, Recommended Models, and
/// Storage Usage all in one place, App-Store-shaped per the product brief:
/// each model row moves Available → Downloading → Installed → (optionally)
/// Active, never more than one step from wherever it currently is.
///
/// Replaces `features/settings/presentation/screens/ai_models_screen.dart`
/// at the same `/settings/ai-models` route - that screen's two real
/// capabilities (Whisper size choice, the background-downloads toggle) are
/// both still here, folded into this richer screen rather than duplicated
/// alongside it.
class AiModelManagerScreen extends ConsumerWidget {
  const AiModelManagerScreen({super.key});

  static const _catalogKinds = [ModelKind.llm, ModelKind.embedding, ModelKind.speechToText, ModelKind.ocr];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedAsync = ref.watch(installedModelsControllerProvider);
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Model Manager')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(installedModelsControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _PrivacyBanner(),
            const SizedBox(height: 16),
            const _RecommendedCard(),
            const SizedBox(height: 16),
            const _StorageSummaryCard(),
            const SizedBox(height: 24),
            Text('Advanced settings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final kind in _catalogKinds) ...[
              _KindSection(kind: kind, installedAsync: installedAsync),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            Text('Downloads', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                value: settings.allowBackgroundDownloads,
                onChanged: (value) {
                  ref.read(settingsControllerProvider.notifier).setAllowBackgroundDownloads(value);
                  if (value) BackgroundDownloadService.requestPermission();
                },
                title: const Text('Keep downloading in the background'),
                subtitle: Text(
                  settings.allowBackgroundDownloads
                      ? 'On: a model download keeps running if you switch to another '
                          'app, shown via a small ongoing notification while active.'
                      : 'Off (default): keep the app open while a model downloads, or '
                          'it may pause.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Every model here runs entirely on your device. Downloading is the '
                'only network activity - there is no cloud inference, no telemetry, '
                'and no account required.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedCard extends ConsumerWidget {
  const _RecommendedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profession = ref.watch(selectedProfessionProvider);
    return Card(
      child: ListTile(
        leading: const TintedIcon(Icons.auto_awesome_outlined),
        title: Text(profession == null ? 'Get recommended models' : 'Recommended for ${profession.label}'),
        subtitle: Text(
          profession == null
              ? 'Answer one question and we\'ll pick sensible defaults for your use case.'
              : 'Tap to review or change your profession-based recommendation.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(RoutePaths.aiModelSetup),
      ),
    );
  }
}

class _StorageSummaryCard extends ConsumerWidget {
  const _StorageSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageAsync = ref.watch(modelStorageInfoProvider);
    return Card(
      child: ListTile(
        leading: const TintedIcon(Icons.sd_storage_outlined),
        title: const Text('Storage used by AI models'),
        subtitle: storageAsync.when(
          data: (info) => Text(formatFileSize(info.totalBytes)),
          loading: () => const Text('Calculating…'),
          error: (_, _) => const Text('Unavailable'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(RoutePaths.aiModelStorage),
      ),
    );
  }
}

/// One model kind's row list, collapsed behind an [ExpansionTile] rather
/// than always shown as permanent cards (Phase 7A, item 8) - the collapsed
/// header already tells you what's active/installed, so there's no need to
/// open it at all unless you actually want to change something. This is
/// what lets the Speech-to-text section (6 models today, and the one
/// section most likely to keep growing) stay a single compact row instead
/// of a wall of cards, and it scales the same way whether a kind has 2
/// models or 30.
class _KindSection extends ConsumerWidget {
  const _KindSection({required this.kind, required this.installedAsync});

  final ModelKind kind;
  final AsyncValue<List<InstalledModel>> installedAsync;

  String get _title => switch (kind) {
        ModelKind.llm => 'Chat Model',
        ModelKind.embedding => 'Embedding Model',
        ModelKind.speechToText => 'Speech-to-text Model',
        ModelKind.ocr => 'OCR Language',
        ModelKind.vision || ModelKind.translation => '',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = ModelCatalog.forKind(kind);
    final installed = installedAsync.valueOrNull ?? const [];
    final downloadStates = ref.watch(modelDownloadControllerProvider);

    final activeInstalled = installed.where((m) => m.isActive).firstOrNull;
    final activeSpec =
        activeInstalled == null ? null : specs.where((s) => s.id == activeInstalled.modelId).firstOrNull;

    // Item 11: the Embedding Model is invisible infrastructure to a
    // non-technical user - it's never a meaningful choice the way a Chat
    // Model or Whisper size is - so its collapsed subtitle says that
    // plainly instead of implying there's a decision to make here.
    final subtitle = activeSpec != null
        ? '${activeSpec.displayName} · Active'
        : kind == ModelKind.embedding
            ? 'Used automatically for search - most people never need to open this.'
            : '${specs.length} option${specs.length == 1 ? '' : 's'} available';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(_title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(subtitle),
        childrenPadding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < specs.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _ModelRow(
              spec: specs[i],
              installed: installed.where((m) => m.modelId == specs[i].id).firstOrNull,
              downloadState: downloadStates[specs[i].id] ?? const ModelDownloadIdle(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.spec, required this.installed, required this.downloadState});

  final AiModelSpec spec;
  final InstalledModel? installed;
  final ModelDownloadState downloadState;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget trailing;
    double? fraction;
    if (downloadState is ModelDownloadInProgress) {
      fraction = (downloadState as ModelDownloadInProgress).fraction;
      trailing = SizedBox(
        width: 48,
        child: fraction == null
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Text('${(fraction * 100).round()}%'),
      );
    } else if (installed != null) {
      trailing = installed!.isActive
          ? Chip(label: const Text('Active'), backgroundColor: scheme.primaryContainer)
          : const Chip(label: Text('Installed'));
    } else {
      trailing = const Icon(Icons.download_outlined);
    }

    return ListTile(
      title: Text(spec.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${formatFileSize(spec.sizeBytesApprox)} · ${spec.speedTier.name}'),
          // A visible progress bar alongside the percentage (V2.3) - mirrors
          // the same coarse-progress convention every meeting/document card
          // already uses (KnowledgeSourceCard), so "something is actively
          // happening" reads the same way everywhere in the app, not just
          // as a number ticking up next to a spinner.
          if (fraction != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
      trailing: trailing,
      onTap: () => context.push(RoutePaths.aiModelDetailsPath(spec.id)),
    );
  }
}
