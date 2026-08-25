import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/utils/fts5_query_builder.dart';

void main() {
  group('buildFts5MatchQuery', () {
    test('tokenizes a plain Latin-script query into prefix-match terms', () {
      expect(buildFts5MatchQuery('quarterly budget'), 'quarterly* budget*');
    });

    test('lowercases so FTS5 operator keywords (AND/OR/NOT/NEAR) are neutralized', () {
      expect(buildFts5MatchQuery('cats AND dogs'), 'cats* and* dogs*');
    });

    test('strips punctuation so a lone quote/asterisk/paren can never reach the raw MATCH query', () {
      expect(buildFts5MatchQuery('"budget"* (test)'), 'budget* test*');
    });

    test('returns null for empty or pure-punctuation input', () {
      expect(buildFts5MatchQuery(''), isNull);
      expect(buildFts5MatchQuery('   '), isNull);
      expect(buildFts5MatchQuery('***???'), isNull);
    });

    test(
        'a non-Latin-script query (Devanagari) produces real tokens instead of being silently '
        'stripped to nothing - real-device QA finding: the previous ASCII-only [a-z0-9] regex '
        'treated every character of a non-Latin query as a separator, making search unusable '
        'for the Indian-language content this app explicitly supports', () {
      final query = buildFts5MatchQuery('बजट समीक्षा');
      expect(query, isNotNull);
      expect(query, contains('बजट'));
      expect(query, contains('समीक्षा'));
    });

    test('a Tamil-script query also produces real tokens', () {
      final query = buildFts5MatchQuery('கூட்டம்');
      expect(query, isNotNull);
      expect(query, contains('கூட்டம்'));
    });

    test('mixed Latin and Devanagari script query tokenizes both parts', () {
      final query = buildFts5MatchQuery('budget बजट');
      expect(query, 'budget* बजट*');
    });
  });
}
