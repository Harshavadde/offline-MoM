import 'package:flutter/material.dart';

/// A small, muted "this is AI-generated, verify it" caption (R-6) - mirrors
/// Workspace Chat's existing, already-shipped disclaimer text/style exactly
/// (`chat_screen.dart`: "small and muted by design... a caption, not
/// another badge"), extended here to a shared widget so every other
/// AI-generated-content surface (meeting summaries, resume suggestions)
/// can carry the same disclaimer without re-styling it from scratch. Kept
/// deliberately unobtrusive and singular per screen - "do not make this
/// annoying or repeat huge warnings everywhere."
class AiDisclaimer extends StatelessWidget {
  const AiDisclaimer({
    super.key,
    this.text = 'AI-generated content can contain mistakes or omissions. '
        'Always verify important information before relying on it.',
  });

  /// A resume-specific variant matching the wording this feature calls
  /// for explicitly - AI review guidance, not a generic disclaimer, since
  /// a resume's accuracy has real consequences (a job application) beyond
  /// "double check this."
  const AiDisclaimer.resume({super.key})
      : text = 'AI may make mistakes or infer information incorrectly. '
            'Review all generated content and verify it against your '
            'actual experience before applying.';

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
