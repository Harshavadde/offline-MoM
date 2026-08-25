import 'package:path/path.dart' as p;

/// Machine-generated tokens stripped from the front of a filename before
/// its remaining tokens become the display title - generic enough that
/// they never carry real information about *which* document this is
/// (unlike, say, "Resume" or "Invoice").
const _genericLeadingPrefixes = {
  'download',
  'downloaded',
  'file',
  'files',
  'doc',
  'document',
  'attachment',
  'img',
  'image',
  'scan',
  'export',
  'copy',
  'untitled',
  'new',
  'tmp',
  'temp',
};

final _uuidPattern = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);

/// A parenthesized copy-counter some file managers/download tools append,
/// e.g. "Resume (1).pdf".
final _copyCounterPattern = RegExp(r'\(\d+\)');

final _pureDigits = RegExp(r'^\d+$');
final _pureHex = RegExp(r'^[0-9a-fA-F]+$');

bool _isLongNumericId(String token) => _pureDigits.hasMatch(token) && token.length >= 6;

/// Hex-only tokens read as a hash/id rather than real content - deliberately
/// a higher bar (8+) than [_isLongNumericId]'s 6, since a short hex-looking
/// token (e.g. "2024", "v2") is far more likely to be genuine content than
/// a short numeric one is.
bool _isHashLikeToken(String token) => _pureHex.hasMatch(token) && token.length >= 8;

/// Derives a clean, human-friendly document title from a raw imported
/// filename (Phase 7B, item 3) - strips machine-generated cruft (UUIDs,
/// long numeric timestamps/ids, hex-looking hashes, parenthesized copy
/// counters, percent-encoded URL leftovers, and a handful of generic
/// download-tool prefixes) while preserving whatever actually looks like
/// the document's real name, e.g. `IMG_20240615_143022_a1b2c3d4.jpg` ->
/// `IMG` alone would be left after stripping the date/time/hash tokens, so
/// this falls back to [fallback] rather than show a single generic word -
/// see the "nothing meaningful survives" branch below.
///
/// Deliberately conservative: a *short* numeric token (e.g. "v2", "2024",
/// a 3-4 digit id) is kept rather than guessed at, since destroying real
/// content is worse than leaving occasional cruft behind. This never
/// touches [Document.originalFilename] - that's preserved separately,
/// unconditionally, for export/import; this only derives the *display*
/// title.
///
/// No PDF/DOCX metadata Title is read here: this app's PDF/DOCX text
/// extraction (`read_pdf_text`, a native wrapper - see `pdf_parser.dart`)
/// exposes no metadata API, and hand-rolling a PDF object-dictionary parser
/// just for an optional metadata fallback isn't worth the correctness risk
/// for this pass (see Phase 7B's report).
String deriveDocumentTitle(String originalFilename, {String fallback = 'Untitled Document'}) {
  var name = p.basenameWithoutExtension(originalFilename);

  name = name.replaceAll(_uuidPattern, ' ');
  name = name.replaceAll(_copyCounterPattern, ' ');

  if (name.contains('%')) {
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {
      // Not valid percent-encoding after all (e.g. a literal '%' in the
      // name) - fall through and let the generic cleanup below handle it.
    }
  }

  final tokens = name.split(RegExp(r'[_\-\s]+')).where((t) => t.isNotEmpty).toList();
  final kept = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (i == 0 && _genericLeadingPrefixes.contains(token.toLowerCase())) continue;
    if (_isLongNumericId(token)) continue;
    if (_isHashLikeToken(token)) continue;
    kept.add(token);
  }

  final result = kept.join(' ').trim();
  return result.isEmpty ? fallback : result;
}
