import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _points = [
    'Audio, transcripts, summaries, action items and decisions are stored '
        'only in this app\'s local database on this device.',
    'Speech-to-text and AI summarization run entirely on-device — no '
        'recording or transcript is ever uploaded anywhere.',
    'The app has no login, no account, and no analytics/telemetry.',
    'Deleting a meeting permanently deletes its transcript, summary, '
        'action items and decisions from the device.',
    'Exported PDF reports are saved to files you control and are only '
        'shared if you explicitly choose to share them.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'OfflineMoMAI is designed to work completely offline.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          for (final point in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 10),
                    child: Icon(Icons.circle, size: 6),
                  ),
                  Expanded(child: Text(point)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
