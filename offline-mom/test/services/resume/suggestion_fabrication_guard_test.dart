// Tests SuggestionFabricationGuard
// (lib/services/resume/suggestion_fabrication_guard.dart) - a pure,
// deterministic, offline lexical check. No LLM, no database.
//
// Per docs/v3/01-prd.md AC3-03/D-08 (confirmed against the frozen PRD, not
// reinterpreted here): this guard *flags*, it never auto-rejects. Every
// test below asserts on `isSafe`/`newNumbers`/`newProperNouns`, never on a
// suggestion being discarded - that's a caller-level (UI/review-time)
// decision, not this guard's.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/suggestion_fabrication_guard.dart';

void main() {
  const guard = SuggestionFabricationGuard();

  group('valid rewrite', () {
    test('a pure reordering/rewording of existing content is safe', () {
      final result = guard.check(
        originalText: 'Built REST APIs using Node.js.\nWrote unit tests with Jest.',
        suggestedText: 'Developed and tested REST APIs using Node.js and Jest.',
      );

      expect(result.isSafe, isTrue);
      expect(result.newNumbers, isEmpty);
      expect(result.newProperNouns, isEmpty);
    });

    test('reusing a number already present in the original text is safe', () {
      final result = guard.check(
        originalText: 'Managed a team of 5 engineers.',
        suggestedText: 'Led a 5-person engineering team.',
      );

      expect(result.isSafe, isTrue);
    });

    test("a bullet's own leading capitalized verb is never flagged", () {
      final result = guard.check(
        originalText: 'Built services.',
        suggestedText: 'Delivered services efficiently.',
      );

      expect(result.newProperNouns, isEmpty);
    });
  });

  group('unsupported employer', () {
    test('a new employer name not in the original is flagged as a new proper noun', () {
      final result = guard.check(
        originalText: 'Built services using Node.js.',
        suggestedText: 'Built services using Node.js while at Globex Corporation.',
      );

      expect(result.isSafe, isFalse);
      expect(result.newProperNouns, contains('Globex'));
    });
  });

  group('unsupported technology', () {
    test('a new technology name not in the original is flagged', () {
      final result = guard.check(
        originalText: 'Built services using Node.js.',
        suggestedText: 'Built services using Node.js and Kubernetes.',
      );

      expect(result.isSafe, isFalse);
      expect(result.newProperNouns, contains('Kubernetes'));
    });

    test('a technology already present in the original is never flagged', () {
      final result = guard.check(
        originalText: 'Deployed services with Kubernetes and Docker.',
        suggestedText: 'Orchestrated container deployments using Kubernetes and Docker.',
      );

      expect(result.newProperNouns, isEmpty);
    });
  });

  group('invented metric', () {
    test('a new number not present anywhere in the grounding text is flagged', () {
      final result = guard.check(
        originalText: 'Improved page load time.',
        suggestedText: 'Improved page load time by 40%.',
      );

      expect(result.isSafe, isFalse);
      expect(result.newNumbers, contains('40%'));
    });

    test('a number already present in the original is never flagged', () {
      final result = guard.check(
        originalText: 'Reduced latency by 40% across 3 services.',
        suggestedText: 'Cut latency 40% across all 3 services.',
      );

      expect(result.newNumbers, isEmpty);
    });
  });

  group('invented certification', () {
    test('a certification name not in the original is flagged as a new proper noun', () {
      final result = guard.check(
        originalText: 'Built cloud infrastructure on AWS.',
        suggestedText: 'Built cloud infrastructure on AWS as an AWS Certified Solutions Architect.',
      );

      expect(result.isSafe, isFalse);
      expect(result.newProperNouns, contains('Certified'));
      expect(result.newProperNouns, contains('Solutions'));
      expect(result.newProperNouns, contains('Architect'));
    });
  });

  group('invented experience/date', () {
    test('a year not present anywhere in the grounding text is flagged as a new number', () {
      final result = guard.check(
        originalText: 'Led the backend migration.',
        suggestedText: 'Led the backend migration starting in 2019.',
      );

      expect(result.isSafe, isFalse);
      expect(result.newNumbers, contains('2019'));
    });

    test('a month name not present in the original is flagged as a new proper noun', () {
      final result = guard.check(
        originalText: 'Completed the migration.',
        suggestedText: 'Completed the migration in January.',
      );

      expect(result.isSafe, isFalse);
      expect(result.newProperNouns, contains('January'));
    });

    test('a date/year already stated in the original is never flagged', () {
      final result = guard.check(
        originalText: 'Migrated the platform in 2019.',
        suggestedText: 'Led the 2019 platform migration.',
      );

      expect(result.newNumbers, isEmpty);
    });
  });

  group('additionalGroundingText (legitimate context)', () {
    test('a role/company already known from entry metadata is not flagged even though it is '
        'absent from the specific field being rewritten', () {
      final result = guard.check(
        originalText: 'Built services.',
        suggestedText: 'As a Backend Engineer at Acme, built services.',
        additionalGroundingText: const ['Backend Engineer', 'Acme'],
      );

      expect(result.isSafe, isTrue);
    });

    test('a genuinely new proper noun is still flagged even with additionalGroundingText supplied', () {
      final result = guard.check(
        originalText: 'Built services.',
        suggestedText: 'As a Backend Engineer at Acme, built services using Kubernetes.',
        additionalGroundingText: const ['Backend Engineer', 'Acme'],
      );

      expect(result.isSafe, isFalse);
      expect(result.newProperNouns, contains('Kubernetes'));
    });
  });

  group('missing evidence handled safely', () {
    test('an empty original and empty suggested text does not crash and is safe', () {
      expect(
        () => guard.check(originalText: '', suggestedText: ''),
        returnsNormally,
      );
      final result = guard.check(originalText: '', suggestedText: '');
      expect(result.isSafe, isTrue);
    });

    test('an empty original text with non-empty suggested text flags every capitalized word/number '
        'in the suggestion, never throws', () {
      expect(
        () => guard.check(originalText: '', suggestedText: 'Built services using Kubernetes.'),
        returnsNormally,
      );
      final result = guard.check(originalText: '', suggestedText: 'Built services using Kubernetes.');
      expect(result.isSafe, isFalse);
      expect(result.newProperNouns, contains('Kubernetes'));
    });

    test('a suggestion with no additionalGroundingText supplied behaves identically to an '
        'empty list (the default)', () {
      final withDefault = guard.check(originalText: 'Built services.', suggestedText: 'Built services.');
      final withExplicitEmpty = guard.check(
        originalText: 'Built services.',
        suggestedText: 'Built services.',
        additionalGroundingText: const [],
      );

      expect(withDefault.isSafe, withExplicitEmpty.isSafe);
    });
  });
}
