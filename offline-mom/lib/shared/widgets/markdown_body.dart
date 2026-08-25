import 'package:flutter/material.dart';

import '../../core/markdown/markdown_parser.dart';

/// Renders a chat message's Markdown (Phase 8B.1, Priority 4) using the
/// dependency-free parser in `core/markdown/markdown_parser.dart` - see
/// that file's doc comment for exactly what subset is supported. Wrapped
/// in a single [SelectionArea] so the rendered richer content (headings,
/// code blocks, tables, lists) stays selectable as one region, the same
/// as the plain [SelectableText] this replaces.
///
/// Links are styled (colored, underlined) but not tappable - making them
/// open externally would need the `url_launcher` package, a new dependency
/// this phase's "do not introduce new frameworks" constraint rules out for
/// what's a minor nice-to-have next to the rest of this renderer.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({super.key, required this.data, this.baseStyle});

  final String data;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final base = baseStyle ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final blocks = parseMarkdownBlocks(data);

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [for (final block in blocks) _buildBlock(context, block, base)],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, MarkdownBlock block, TextStyle base) {
    final scheme = Theme.of(context).colorScheme;
    return switch (block) {
      HeadingBlock(:final level, :final text) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: _richText(
            context,
            text,
            base.copyWith(
              fontSize: switch (level) { 1 => 22.0, 2 => 20.0, 3 => 18.0, 4 => 16.0, _ => 15.0 },
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ParagraphBlock(:final text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _richText(context, text, base),
        ),
      CodeBlock(:final code, :final language) => Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (language != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    language,
                    style: base.copyWith(
                      fontSize: (base.fontSize ?? 14) - 2,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              SelectableText(
                code,
                style: base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) - 1),
              ),
            ],
          ),
        ),
      BulletListBlock(:final items) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: base),
                      Expanded(child: _richText(context, item, base)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      NumberedListBlock(:final items) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}.  ', style: base),
                      Expanded(child: _richText(context, items[i], base)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      BlockQuoteBlock(:final text) => Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: scheme.outline, width: 3)),
          ),
          child: _richText(
            context,
            text,
            base.copyWith(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant),
          ),
        ),
      TableBlock(:final headers, :final rows) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Table(
            border: TableBorder.all(color: scheme.outlineVariant, width: 0.6),
            children: [
              TableRow(
                decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
                children: [
                  for (final header in headers)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: _richText(context, header, base.copyWith(fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              for (final row in rows)
                TableRow(
                  children: [
                    for (final cell in row)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: _richText(context, cell, base),
                      ),
                  ],
                ),
            ],
          ),
        ),
    };
  }

  Widget _richText(BuildContext context, String text, TextStyle base) {
    final scheme = Theme.of(context).colorScheme;
    // `SelectableText.rich` rather than plain `Text.rich` - each block stays
    // individually selectable exactly like the single `SelectableText` this
    // widget replaces, and it composes correctly with the outer
    // `SelectionArea` (which unifies selection *across* blocks) rather than
    // conflicting with it.
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final span in parseInline(text))
            TextSpan(
              text: span.text,
              style: switch (span.style) {
                InlineStyle.bold => base.copyWith(fontWeight: FontWeight.bold),
                InlineStyle.italic => base.copyWith(fontStyle: FontStyle.italic),
                InlineStyle.code => base.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: scheme.surfaceContainerHighest,
                    fontSize: (base.fontSize ?? 14) - 1,
                  ),
                InlineStyle.link => base.copyWith(
                    color: scheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                InlineStyle.plain => base,
              },
            ),
        ],
      ),
    );
  }
}
