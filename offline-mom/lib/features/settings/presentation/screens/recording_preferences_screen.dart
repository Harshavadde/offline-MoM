import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/app_providers.dart';

class RecordingPreferencesScreen extends ConsumerWidget {
  const RecordingPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final notifier = ref.read(settingsControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Recording')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Recording quality', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Transcription always converts audio down to 16kHz mono first, '
            'so quality here only affects file size and how good the '
            'recording sounds if you play it back yourself.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: RadioGroup<bool>(
              groupValue: settings.recordingQualityHigh,
              onChanged: (value) {
                if (value != null) notifier.setRecordingQualityHigh(value);
              },
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: Text('Standard'),
                    subtitle: Text('16kHz mono - smaller files (default)'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: Text('High'),
                    subtitle: Text('44.1kHz stereo - larger files, better playback'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
