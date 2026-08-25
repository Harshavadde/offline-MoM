// Tests ResumeWritingHeuristics
// (lib/services/resume/resume_writing_heuristics.dart) - a pure,
// deterministic, offline check. No LLM, no database.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/resume_writing_heuristics.dart';

void main() {
  const heuristics = ResumeWritingHeuristics();

  group('weak verb detection', () {
    test('flags a bullet starting with "Helped"', () {
      final hints = heuristics.analyze('Helped the team ship features.');

      expect(hints.map((h) => h.kind), contains(WritingHintKind.weakVerb));
    });

    test('flags a bullet starting with "Responsible for"', () {
      final hints = heuristics.analyze('Responsible for maintaining the CI pipeline.');

      expect(hints.map((h) => h.kind), contains(WritingHintKind.weakVerb));
    });

    test('is case-insensitive', () {
      final hints = heuristics.analyze('HELPED build the new dashboard.');

      expect(hints.map((h) => h.kind), contains(WritingHintKind.weakVerb));
    });

    test('does not flag a bullet starting with a strong action verb', () {
      final hints = heuristics.analyze('Built the new dashboard with 42 widgets.');

      expect(hints.map((h) => h.kind), isNot(contains(WritingHintKind.weakVerb)));
    });

    test('does not flag a weak phrase appearing mid-sentence, only at the start', () {
      final hints = heuristics.analyze('Led a project that helped reduce costs by 20%.');

      expect(hints.map((h) => h.kind), isNot(contains(WritingHintKind.weakVerb)));
    });
  });

  group('measurable detail detection', () {
    test('flags a bullet with no numbers at all', () {
      final hints = heuristics.analyze('Improved the checkout flow for customers.');

      expect(hints.map((h) => h.kind), contains(WritingHintKind.noMeasurableDetail));
    });

    test('does not flag a bullet containing a number', () {
      final hints = heuristics.analyze('Improved checkout conversion by 15%.');

      expect(hints.map((h) => h.kind), isNot(contains(WritingHintKind.noMeasurableDetail)));
    });

    test('does not flag a bullet containing a plain count', () {
      final hints = heuristics.analyze('Managed a team of 5 engineers.');

      expect(hints.map((h) => h.kind), isNot(contains(WritingHintKind.noMeasurableDetail)));
    });
  });

  group('never auto-inserted / purely advisory', () {
    test('analyze never returns a suggested replacement for the text - only advisory messages', () {
      final hints = heuristics.analyze('Helped the team.');

      for (final hint in hints) {
        expect(hint.message, isNot(equals('Helped the team.')));
      }
    });

    test('a bullet with both weaknesses returns both hints', () {
      final hints = heuristics.analyze('Helped improve things.');

      expect(hints.map((h) => h.kind), containsAll([
        WritingHintKind.weakVerb,
        WritingHintKind.noMeasurableDetail,
      ]));
      expect(hints, hasLength(2));
    });

    test('a strong, quantified bullet returns no hints at all', () {
      final hints = heuristics.analyze('Reduced page load time by 40% across 3 services.');

      expect(hints, isEmpty);
    });
  });

  group('missing/empty input handled safely', () {
    test('an empty string returns no hints, never throws', () {
      expect(() => heuristics.analyze(''), returnsNormally);
      expect(heuristics.analyze(''), isEmpty);
    });

    test('a whitespace-only string returns no hints', () {
      expect(heuristics.analyze('   '), isEmpty);
    });
  });
}
