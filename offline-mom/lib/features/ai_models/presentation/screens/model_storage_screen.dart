import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/error_state.dart';
import '../providers/model_storage_providers.dart';

/// Storage Usage (Phase 6A objective 10): Storage Used, Model Cache,
/// Temporary Downloads, and Delete Cache - see [ModelStorageInfo]'s doc
/// comment for why this is a separate breakdown from Settings > Storage's
/// existing `storageInfoProvider`.
class ModelStorageScreen extends ConsumerWidget {
  const ModelStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageAsync = ref.watch(modelStorageInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Model storage')),
      body: storageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(title: 'Couldn\'t read storage usage', error: e),
        data: (info) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Row(label: 'Speech-to-text models', value: formatFileSize(info.whisperModelsBytes)),
            _Row(label: 'Chat + embedding model cache', value: formatFileSize(info.llmEmbeddingCacheBytes)),
            _Row(label: 'Temporary downloads', value: formatFileSize(info.partialDownloadBytes)),
            const Divider(height: 32),
            _Row(
              label: 'Total',
              value: formatFileSize(info.totalBytes),
              emphasize: true,
            ),
            const SizedBox(height: 24),
            Text(
              'Clearing the cache removes any in-progress downloads and the shared '
              'chat/embedding model cache (both re-download automatically next time '
              'they\'re needed). Installed speech-to-text models are not affected - '
              'delete those individually from their Model Details screen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDestructiveConfirmDialog(
                  context,
                  title: 'Clear model cache?',
                  message: 'The chat and embedding models will need to re-download the '
                      'next time you use them.',
                  confirmLabel: 'Clear cache',
                );
                if (!confirmed) return;
                await clearModelCache();
                ref.invalidate(modelStorageInfoProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Model cache cleared.')),
                  );
                }
              },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Delete cache'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
