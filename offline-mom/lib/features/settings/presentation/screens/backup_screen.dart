import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../providers/app_providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _isExporting = false;

  Future<void> _exportBackup() async {
    setState(() => _isExporting = true);
    String? backupPath;
    try {
      // Share a *copy*, never the live db file - sharing the original could
      // race with sqflite's own writes and, on some share targets, the file
      // handle can outlive this call.
      final dbPath = ref.read(appDatabaseProvider).db.path;
      final tempDir = await getTemporaryDirectory();
      final backupName =
          'offline_mom_backup_${DateTime.now().millisecondsSinceEpoch}.db';
      backupPath = p.join(tempDir.path, backupName);
      await File(dbPath).copy(backupPath);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backupPath)],
          subject: 'OfflineMoMAI backup',
          text: 'OfflineMoMAI database backup - keep this file somewhere safe.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create the backup. Make sure you have enough free '
            'storage and try again.',
          ),
        ),
      );
    } finally {
      // The temp copy has no reason to outlive this export - `share()` has
      // already completed (its Future only resolves once the share sheet
      // interaction is done, by which point Android has finished reading
      // the file), so nothing still needs it (Phase 4B: this used to leak
      // one full database copy into temp storage per export indefinitely -
      // `StorageScreen`'s "Clear temporary cache" only ever targeted
      // leftover `.wav` transcode files, never these).
      if (backupPath != null) {
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      }
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Export data')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.backup_outlined, size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Export a copy of your meetings database - every meeting, '
                'transcript, summary, action item, decision and note - as '
                'a single file you can save wherever you like.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This export contains text data only. It does not include '
                        'recorded audio, and OfflineMoMAI cannot restore an export. '
                        'Keep it only as a personal archive or share it deliberately.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isExporting ? null : _exportBackup,
                icon: _isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: const Text('Export data'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
