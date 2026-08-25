/// One page that contains at least one match, plus how many occurrences
/// are on that page - the granularity `read_pdf_text` actually supports
/// (per-page text, no in-page character/coordinate positions), so
/// "next/previous result" navigates page to page, not occurrence to
/// occurrence within a page - an honest reflection of what this dependency
/// can actually tell this app, not an invented finer granularity.
class PdfSearchMatch {
  const PdfSearchMatch({required this.pageIndex, required this.occurrenceCount});
  final int pageIndex;
  final int occurrenceCount;
}

/// Case-insensitive substring search across a PDF's already-extracted
/// per-page text (`PdfTextSearchService.extractPagesText`'s own output) -
/// pure, synchronous, and independent of the extraction step itself, so it
/// can be tested directly against hand-built page text without a native
/// plugin or a real PDF. Returns one [PdfSearchMatch] per page that
/// contains the query, in page order; pages with no match are omitted
/// entirely (never a zero-count entry).
List<PdfSearchMatch> searchPdfPagesText(List<String> pagesText, String query) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) return const [];
  final lowerQuery = trimmedQuery.toLowerCase();

  final matches = <PdfSearchMatch>[];
  for (var pageIndex = 0; pageIndex < pagesText.length; pageIndex++) {
    final lowerPage = pagesText[pageIndex].toLowerCase();
    var count = 0;
    var searchStart = 0;
    while (true) {
      final found = lowerPage.indexOf(lowerQuery, searchStart);
      if (found == -1) break;
      count++;
      searchStart = found + lowerQuery.length;
    }
    if (count > 0) {
      matches.add(PdfSearchMatch(pageIndex: pageIndex, occurrenceCount: count));
    }
  }
  return matches;
}

/// True if [pagesText] contains no extractable text at all (every page is
/// empty/whitespace-only) - the P0-6 spec's own explicit "No searchable
/// text found in this PDF" state, for a scanned/image-only PDF. Distinct
/// from "extraction hasn't run yet" (the caller's own `null`-vs-`[]`
/// state), which this function does not decide - a genuinely empty *result*
/// after a successful extraction is what this checks.
bool hasNoSearchableText(List<String> pagesText) {
  return pagesText.every((page) => page.trim().isEmpty);
}
