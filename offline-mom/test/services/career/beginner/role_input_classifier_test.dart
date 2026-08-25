// Tests looksLikeJobTitle (lib/services/career/beginner/role_input_classifier.dart)
// - R-10 §3's "a short pasted title must not be forced through the full JD
// parser" heuristic.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/career/beginner/role_input_classifier.dart';

void main() {
  group('short job titles - looksLikeJobTitle returns true', () {
    for (final title in [
      'Sales Executive',
      'Data Entry Operator',
      'Customer Support',
      'HR',
      'BDE',
    ]) {
      test('"$title"', () => expect(looksLikeJobTitle(title), isTrue));
    }
  });

  group('real JD text - looksLikeJobTitle returns false', () {
    test('multi-line text', () {
      expect(looksLikeJobTitle('Sales Executive\n\nResponsibilities:\n- Call leads'), isFalse);
    });

    test('long single-line text (over the word count bound)', () {
      expect(
        looksLikeJobTitle(
          'We are looking for a motivated Sales Executive to join our growing team immediately',
        ),
        isFalse,
      );
    });

    test('short text that still contains a JD structure marker', () {
      expect(looksLikeJobTitle('Sales Executive - apply now'), isFalse);
      expect(looksLikeJobTitle('Requirements: 2 years experience'), isFalse);
    });
  });

  test('blank input is not treated as a job title', () {
    expect(looksLikeJobTitle(''), isFalse);
    expect(looksLikeJobTitle('   '), isFalse);
  });
}
