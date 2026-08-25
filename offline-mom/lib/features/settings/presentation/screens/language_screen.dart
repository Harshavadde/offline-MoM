import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/app_providers.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  static const _languages = [
    (code: 'auto', label: 'Auto-detect'),
    (code: 'en', label: 'English'),
    (code: 'hi', label: 'Hindi'),
    (code: 'ta', label: 'Tamil'),
    (code: 'te', label: 'Telugu'),
    (code: 'bn', label: 'Bengali'),
    (code: 'mr', label: 'Marathi'),
    (code: 'kn', label: 'Kannada'),
    (code: 'ml', label: 'Malayalam'),
    (code: 'pa', label: 'Punjabi'),
    (code: 'gu', label: 'Gujarati'),
    (code: 'es', label: 'Spanish'),
    (code: 'fr', label: 'French'),
    (code: 'de', label: 'German'),
    (code: 'ar', label: 'Arabic'),
    (code: 'zh', label: 'Chinese'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final notifier = ref.read(settingsControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Transcription language', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A hint for the speech-to-text engine about what language is '
            'being spoken - it detects the language once, from the whole recording, not '
            'sentence by sentence. Pick a language directly if auto-detect '
            'keeps guessing wrong for a meeting that\'s consistently in '
            'one language - auto-detect is especially unreliable on very '
            'short recordings (a few seconds), since there\'s barely '
            'enough audio for it to go on. Picking your language directly '
            'fixes that.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Speaking two languages in the same meeting (e.g. '
                    'half Hindi, half English)? Keep this on Auto-detect - '
                    'the multilingual model can follow a language '
                    'switch mid-recording better than being locked to one '
                    'language, though it still isn\'t perfect and may '
                    'transcribe some words phonetically in the wrong '
                    'script.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: RadioGroup<String>(
              groupValue: settings.transcriptionLanguage,
              onChanged: (value) {
                if (value != null) notifier.setTranscriptionLanguage(value);
              },
              child: Column(
                children: [
                  for (final language in _languages)
                    RadioListTile<String>(
                      value: language.code,
                      title: Text(language.label),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Output language', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              value: settings.translateToEnglish,
              onChanged: notifier.setTranslateToEnglish,
              title: const Text('Always give me English text'),
              subtitle: Text(
                settings.translateToEnglish
                    ? 'On: the transcript (and therefore the summary and '
                        'MoM, which are generated from it) will always be '
                        'in English, translated from whatever language was '
                        'spoken. You\'ll no longer get a transcript in the '
                        'original language.'
                    : 'Off (default): the transcript stays in the language '
                        'that was spoken. Turn this on if you\'d rather '
                        'always read everything in English regardless of '
                        'what language the meeting was in.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
