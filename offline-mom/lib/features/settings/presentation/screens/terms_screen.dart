import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _assetPath = 'docs/legal/terms-of-service.md';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(_assetPath),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: _renderMarkdown(context, snapshot.data!),
          );
        },
      ),
    );
  }

  /// A deliberately minimal markdown-to-widgets pass (headings + paragraphs
  /// only) - the terms document only uses those two constructs, so a full
  /// markdown package would be more dependency than the content needs.
  List<Widget> _renderMarkdown(BuildContext context, String source) {
    final textTheme = Theme.of(context).textTheme;
    final widgets = <Widget>[];
    final paragraphBuffer = <String>[];

    void flushParagraph() {
      if (paragraphBuffer.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(paragraphBuffer.join(' '), style: textTheme.bodyMedium),
        ),
      );
      paragraphBuffer.clear();
    }

    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }
      if (line.startsWith('# ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(line.substring(2), style: textTheme.headlineSmall),
        ));
      } else if (line.startsWith('## ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(line.substring(3), style: textTheme.titleMedium),
        ));
      } else if (line.startsWith('*') && line.endsWith('*') && line.length > 1) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            line.substring(1, line.length - 1),
            style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ));
      } else {
        paragraphBuffer.add(line);
      }
    }
    flushParagraph();
    return widgets;
  }
}
