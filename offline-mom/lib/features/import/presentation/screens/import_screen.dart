import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/friendly_error.dart';
import '../providers/import_providers.dart';

/// Import an existing recording (MP3/WAV/M4A/AAC/MP4/MKV/MOV), extracting
/// audio automatically when a video file is picked.
class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  static const _formats = ['MP3', 'WAV', 'M4A', 'AAC', 'MP4', 'MKV', 'MOV'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(importControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<ImportUiState>(importControllerProvider, (previous, next) {
      if (next is ImportSucceeded) {
        final meetingId = next.meetingId;
        ref.read(importControllerProvider.notifier).reset();
        context.pushReplacement(RoutePaths.meetingDetailsPath(meetingId));
      } else if (next is ImportFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(next.message))),
        );
        ref.read(importControllerProvider.notifier).reset();
      }
    });

    final isProcessing = importState is ImportProcessing;

    return Scaffold(
      appBar: AppBar(title: const Text('Import Meeting')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: isProcessing
                      ? null
                      : () => ref
                          .read(importControllerProvider.notifier)
                          .importFile(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: isProcessing
                              ? Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                )
                              : Icon(
                                  Icons.file_upload_outlined,
                                  size: 34,
                                  color: scheme.onPrimaryContainer,
                                ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isProcessing
                              ? 'Preparing audio…'
                              : 'Tap to choose a file',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isProcessing
                              ? 'Extracting audio and copying it into '
                                  'OfflineMoMAI. This stays on this device.'
                              : 'Pick an audio or video recording from '
                                  'this device to transcribe and '
                                  'summarize offline.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (!isProcessing) ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => ref
                                .read(importControllerProvider.notifier)
                                .importFile(),
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Choose a file'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Supported formats',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final format in _formats)
                    Chip(
                      label: Text(format),
                      backgroundColor: scheme.surfaceContainerHighest,
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Video files have their audio extracted automatically before '
                'transcription. Nothing ever leaves this device.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
