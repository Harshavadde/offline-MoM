import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  // Phase 9.2 (Product Identity): this list previously only covered
  // meetings, including one FAQ ("New meeting" on Home) that referenced a
  // combined entry point the current Home screen doesn't have any more
  // (Record and Import have been separate Quick Actions since Phase
  // 8B.2). Updated to match the current UI and to cover documents, chat,
  // and the Productivity Toolkit - a first-time user searching Help
  // shouldn't find zero mentions of three of the app's major features.
  static const _faqs = [
    (
      'How do I record or import a meeting?',
      'On Home, tap "Record meeting" to capture live audio, or "Import '
          'files" to bring in an existing audio/video file.',
    ),
    (
      'How do I add a document?',
      'Tap "Import files" on Home, then choose a PDF, Word, text, or '
          'Markdown file. It\'s extracted and summarized on-device.',
    ),
    (
      'How do I ask questions about my meetings or documents?',
      'Tap "Chat" on Home, or "Chat about this" on any meeting or '
          'document\'s details page. Answers are grounded in your own '
          'content, with sources cited - or clearly labeled when the AI '
          'is answering from its general knowledge instead.',
    ),
    (
      'What can the Productivity Toolkit do?',
      'Tap "Productivity tools" on Home for everyday file utilities that '
          'need no AI model at all: scan documents, and compress, '
          'resize, merge, split, or reorganize images and PDFs.',
    ),
    (
      'Does this need an internet connection?',
      'Only once, to download the AI models the first time you set up '
          'the app (or add a new one in Settings > AI Models). Recording, '
          'importing, transcription, chat, summarization, and the '
          'Productivity Toolkit all run entirely on this device after '
          'that.',
    ),
    (
      'Where is my data stored?',
      'In a local SQLite database inside the app\'s private storage — '
          'see the Privacy screen for details.',
    ),
    (
      'How do I get the Minutes of Meeting as a document?',
      'Open a meeting, then use "Export as PDF" to generate a shareable '
          'PDF report.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _faqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final (question, answer) = _faqs[index];
          return Card(
            child: ExpansionTile(
              title: Text(question),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(answer)],
            ),
          );
        },
      ),
    );
  }
}
