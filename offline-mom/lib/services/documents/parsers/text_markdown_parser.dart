import 'dart:convert';
import 'dart:io';

import '../../../models/document.dart';
import '../document_text_extraction_service.dart';

/// Handles both TXT and Markdown - both are plain text and don't warrant
/// separate classes (Markdown's own formatting syntax is left as-is in the
/// extracted text; no Markdown-to-plain-text conversion is performed,
/// consistent with every other format here extracting the document's
/// actual textual content rather than reinterpreting it).
class TextMarkdownParser implements DocumentTextExtractionService {
  TextMarkdownParser(this.supportedSourceType)
      : assert(
          supportedSourceType == DocumentSourceType.txt ||
              supportedSourceType == DocumentSourceType.markdown,
        );

  @override
  final DocumentSourceType supportedSourceType;

  @override
  Future<String?> extractText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();

    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Not valid UTF-8 - fall back to Latin-1 (ISO-8859-1), which never
      // throws (every byte value 0-255 maps to a valid code point), rather
      // than failing outright on a plain-text file that simply wasn't
      // saved as UTF-8. This can't misrender genuine UTF-8 content (that
      // path is already handled above) - only a non-UTF-8 file reaches
      // here, and Latin-1 is a reasonable, dependency-free best effort for
      // it rather than guessing at a full charset-detection library.
      text = latin1.decode(bytes);
    }

    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
