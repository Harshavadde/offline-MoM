// Tests `outputBudgetTokens` (lib/services/ai/llamadart_llm_engine.dart) -
// the R-8 fix for `answerQuestionStream`/`_answerQuestion` ("Ask")
// previously using a fixed `maxTokens: 300` regardless of how much of the
// model's context window a given request's prompt already used. Pure
// function, no model/engine needed - mirrors
// pdf_page_rendering_service_test.dart's own "test the extracted pure
// function directly" pattern from R-6.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ai/llamadart_llm_engine.dart';

void main() {
  group('outputBudgetTokens', () {
    test('a small prompt gets the full ceiling - plenty of context left', () {
      final budget = outputBudgetTokens(promptChars: 200, contextSize: 2048);
      expect(budget, 800); // default ceiling
    });

    test('a prompt using roughly the full context window is clamped to the floor, '
        'never requesting a negative/zero token budget', () {
      final budget = outputBudgetTokens(promptChars: 10000, contextSize: 2048);
      expect(budget, 64); // default floor
    });

    test('a moderately-sized prompt gets exactly the remaining headroom, not the '
        'ceiling or the floor', () {
      // ceil(4452/3) + 64 = 1548 estimated prompt tokens -> 2048 - 1548 = 500
      // remaining, strictly between the default floor (64) and ceiling (800).
      final budget = outputBudgetTokens(promptChars: 4452, contextSize: 2048);
      expect(budget, 500);
    });

    test('never overflows the context window, except when even the floor can\'t '
        'avoid it (an already-oversized prompt, a pre-existing constraint this '
        'function cannot fix without touching retrieval/history budgets)', () {
      for (final promptChars in [0, 500, 2000, 4452, 6000]) {
        final budget = outputBudgetTokens(promptChars: promptChars, contextSize: 2048);
        final estimatedPromptTokens = (promptChars / 3).ceil() + 64;
        // Whenever the budget wasn't clamped up to the floor, the estimated
        // prompt + output never exceeds contextSize - that's the actual
        // guarantee this function provides for normal-sized prompts.
        if (budget > 64) {
          expect(estimatedPromptTokens + budget, lessThanOrEqualTo(2048));
        }
      }
    });

    test('a larger prompt never yields a larger budget (monotonically non-increasing)', () {
      int? previous;
      for (final promptChars in [0, 1000, 2000, 3000, 4000, 5000, 8000]) {
        final budget = outputBudgetTokens(promptChars: promptChars, contextSize: 2048);
        if (previous != null) expect(budget, lessThanOrEqualTo(previous));
        previous = budget;
      }
    });

    test('custom ceiling/floor are respected', () {
      expect(
        outputBudgetTokens(promptChars: 0, contextSize: 2048, ceiling: 500),
        500,
      );
      expect(
        outputBudgetTokens(promptChars: 10000, contextSize: 2048, floor: 120),
        120,
      );
    });

    test('a larger context window yields a larger (or equal) budget for the same prompt', () {
      final small = outputBudgetTokens(promptChars: 4452, contextSize: 2048);
      final large = outputBudgetTokens(promptChars: 4452, contextSize: 4096);
      expect(large, greaterThanOrEqualTo(small));
    });
  });
}
