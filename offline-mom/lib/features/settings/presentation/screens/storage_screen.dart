import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/tinted_icon.dart';
import '../../../ai_models/presentation/providers/model_storage_providers.dart';
import '../providers/storage_providers.dart';

/// Above this combined footprint (this app's own data plus downloaded AI
/// models), the Storage screen surfaces a warning with a direct link to
/// freeing space (Phase 7A, item 12) rather than staying silent until the
/// device itself is actually full - a generous, device-independent
/// threshold, not an attempt to estimate the device's actual remaining
/// space (this app has no reliable, dependency-free way to read that).
const _highUsageWarningBytes = 3 * 1024 * 1024 * 1024;

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  bool _isClearing = false;

  Future<void> _clearTempCache() async {
    setState(() => _isClearing = true);
    try {
      final deleted = await clearTempTranscodeCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted == 0
                ? 'No leftover temp files found.'
                : 'Cleared $deleted leftover temp file${deleted == 1 ? '' : 's'}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(storageInfoProvider);
    final modelInfoAsync = ref.watch(modelStorageInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(title: 'Couldn\'t read storage usage', error: err),
        data: (info) {
          final modelBytes = modelInfoAsync.valueOrNull?.totalBytes;
          final combinedBytes = info.totalBytes + (modelBytes ?? 0);
          final isHighUsage = combinedBytes >= _highUsageWarningBytes;

          final rows = [
            (
              icon: Icons.mic_none_rounded,
              label: 'Recordings',
              value: '${formatFileSize(info.recordingsBytes)} '
                  '(${info.recordingsCount} file${info.recordingsCount == 1 ? '' : 's'})',
            ),
            (
              icon: Icons.auto_fix_high_rounded,
              label: 'Productivity Toolkit outputs',
              value: '${formatFileSize(info.toolkitBytes)} '
                  '(${info.toolkitCount} file${info.toolkitCount == 1 ? '' : 's'})',
            ),
            (
              icon: Icons.description_outlined,
              label: 'Documents',
              value: '${formatFileSize(info.documentsBytes)} '
                  '(${info.documentsCount} file${info.documentsCount == 1 ? '' : 's'})',
            ),
            (
              icon: Icons.storage_rounded,
              label: 'Database (meetings, transcripts, notes…)',
              value: formatFileSize(info.databaseBytes),
            ),
            (
              icon: Icons.cleaning_services_outlined,
              // Phase 8B.4, Priority 2: "Cache" alone didn't say what was
              // being cached - unlike its neighbor row, which already
              // names itself clearly.
              label: 'Temporary audio conversion files',
              value: formatFileSize(info.cacheBytes),
            ),
            (
              icon: Icons.backup_outlined,
              label: 'Temporary backup exports',
              value: formatFileSize(info.backupsBytes),
            ),
            (
              icon: Icons.psychology_outlined,
              label: 'AI models',
              value: modelInfoAsync.when(
                data: (m) => formatFileSize(m.totalBytes),
                loading: () => 'Calculating…',
                error: (_, _) => 'Unavailable',
              ),
            ),
            (
              icon: Icons.pie_chart_outline_rounded,
              label: 'Total used by OfflineMoMAI',
              value: formatFileSize(combinedBytes),
            ),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isHighUsage) ...[
                _HighUsageBanner(
                  totalBytes: combinedBytes,
                  modelBytes: modelBytes ?? 0,
                  onFreeUpSpace: () => context.push(RoutePaths.aiModelStorage),
                ),
                const SizedBox(height: 14),
              ],
              for (final row in rows) ...[
                Card(
                  child: ListTile(
                    leading: TintedIcon(row.icon),
                    title: Text(row.label),
                    trailing: Text(row.value, style: Theme.of(context).textTheme.bodyMedium),
                    onTap: row.label == 'AI models' ? () => context.push(RoutePaths.aiModelStorage) : null,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),
              Text('Maintenance', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const TintedIcon(Icons.cleaning_services_outlined),
                  title: const Text('Clear temporary cache'),
                  subtitle: const Text(
                    'Removes leftover audio-conversion and backup-export '
                    'temp files. Never touches your recordings or meeting '
                    'data.',
                  ),
                  trailing: _isClearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _isClearing ? null : _clearTempCache,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shown once this app's combined footprint (its own data plus downloaded AI
/// models) crosses [_highUsageWarningBytes] - names the largest contributor
/// (AI models, in every realistic case, since they're multi-hundred-MB to
/// multi-GB downloads) and links straight to the screen that can actually
/// free space, rather than just stating a number.
class _HighUsageBanner extends StatelessWidget {
  const _HighUsageBanner({
    required this.totalBytes,
    required this.modelBytes,
    required this.onFreeUpSpace,
  });

  final int totalBytes;
  final int modelBytes;
  final VoidCallback onFreeUpSpace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Storage is getting large (${formatFileSize(totalBytes)})',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI models are the biggest contributor (${formatFileSize(modelBytes)}). '
                    'You can clear the model cache and re-download only what you use.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: onFreeUpSpace,
                      child: const Text('Free up space'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
