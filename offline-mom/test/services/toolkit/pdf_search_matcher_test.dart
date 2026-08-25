// Tests searchPdfPagesText/hasNoSearchableText (Toolkit productization
// pass, P0-6, PDF Search) - the pure, offline, page-indexed matching logic
// behind PDF Search, independent of the native text-extraction step itself
// (pdf_text_search_service_test.dart covers that layer).
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/toolkit/pdf_search_matcher.dart';

void main() {
  group('searchPdfPagesText', () {
    test('a single matching term on one page (scenario 24)', () {
      final matches = searchPdfPagesText(['no match here', 'Kubernetes is great', 'still nothing'], 'Kubernetes');

      expect(matches, hasLength(1));
      expect(matches.single.pageIndex, 1);
      expect(matches.single.occurrenceCount, 1);
    });

    test('multiple matches on one page (scenario 25)', () {
      final matches = searchPdfPagesText(['Terraform, then more Terraform, and Terraform again'], 'Terraform');

      expect(matches, hasLength(1));
      expect(matches.single.occurrenceCount, 3);
    });

    test('matches across multiple pages (scenario 26)', () {
      final matches = searchPdfPagesText(
        ['Azure Kubernetes Service overview', 'nothing here', 'Kubernetes networking', 'GitHub Actions', 'Kubernetes pods'],
        'Kubernetes',
      );

      expect(matches.map((m) => m.pageIndex), [0, 2, 4]);
    });

    test('no match (scenario 27)', () {
      final matches = searchPdfPagesText(['alpha', 'beta', 'gamma'], 'zzz-not-present');

      expect(matches, isEmpty);
    });

    test('case-insensitive matching (scenario 28)', () {
      final matches = searchPdfPagesText(['KUBERNETES', 'kubernetes', 'KuBeRnEtEs'], 'kubernetes');

      expect(matches, hasLength(3));
    });

    test('an empty or whitespace-only query returns no matches, not every page', () {
      expect(searchPdfPagesText(['some text', 'more text'], ''), isEmpty);
      expect(searchPdfPagesText(['some text', 'more text'], '   '), isEmpty);
    });

    test('overlapping-looking occurrences are counted correctly (non-overlapping scan)', () {
      final matches = searchPdfPagesText(['aaaa'], 'aa');
      expect(matches.single.occurrenceCount, 2); // "aa|aa", not 3 overlapping
    });

    test('successive searches on the same page text are independent and repeatable (scenario 29)', () {
      const pages = ['Azure Kubernetes Service', 'Terraform config', 'GitHub Actions workflow'];

      expect(searchPdfPagesText(pages, 'Kubernetes').single.pageIndex, 0);
      expect(searchPdfPagesText(pages, 'Terraform').single.pageIndex, 1);
      expect(searchPdfPagesText(pages, 'GitHub Actions').single.pageIndex, 2);
      // Re-running an earlier query gives the identical result again.
      expect(searchPdfPagesText(pages, 'Kubernetes').single.pageIndex, 0);
    });
  });

  group('hasNoSearchableText', () {
    test('true when every page is empty or whitespace-only (a scanned/image-only PDF, scenario 32)', () {
      expect(hasNoSearchableText(['', '   ', '\n']), isTrue);
      expect(hasNoSearchableText([]), isTrue);
    });

    test('false when at least one page has real text', () {
      expect(hasNoSearchableText(['', 'some real text', '']), isFalse);
    });
  });
}
