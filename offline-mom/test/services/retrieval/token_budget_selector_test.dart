import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/services/retrieval/hybrid_ranker.dart';
import 'package:offline_mom/services/retrieval/token_budget_selector.dart';

RankedChunk _ranked(int id, String text, {double score = 1.0}) {
  return RankedChunk(
    chunk: KnowledgeChunk(
      id: id,
      contentType: ContentType.transcript,
      sourceId: 1,
      meetingId: 1,
      documentId: null,
      chunkIndex: 0,
      chunkText: text,
      embedding: const [1.0],
      createdAt: DateTime(2026, 1, 1),
    ),
    fusedScore: score,
    matchedVector: true,
    matchedKeyword: false,
  );
}

void main() {
  group('TokenBudgetSelector', () {
    test('everything fits when well under budget', () {
      const selector = TokenBudgetSelector(charBudget: 1000);
      final ranked = [_ranked(1, 'short'), _ranked(2, 'also short')];

      final selection = selector.select(ranked);

      expect(selection.selected, hasLength(2));
      expect(selection.truncated, isFalse);
    });

    test('stops before exceeding the budget, never cutting a chunk mid-way', () {
      const selector = TokenBudgetSelector(charBudget: 100, perChunkOverheadChars: 0);
      final ranked = [_ranked(1, 'a' * 60), _ranked(2, 'b' * 60), _ranked(3, 'c' * 60)];

      final selection = selector.select(ranked);

      // Only the first fits (60 <= 100); the second would push past 100.
      expect(selection.selected, hasLength(1));
      expect(selection.selected.single.chunk.id, 1);
      expect(selection.truncated, isTrue);
      // Every included chunk's text is intact (never truncated mid-string).
      expect(selection.selected.single.chunk.chunkText, 'a' * 60);
    });

    test('always includes at least one chunk even if it alone exceeds the budget', () {
      const selector = TokenBudgetSelector(charBudget: 10, perChunkOverheadChars: 0);
      final ranked = [_ranked(1, 'x' * 500)];

      final selection = selector.select(ranked);

      expect(selection.selected, hasLength(1));
      expect(selection.truncated, isFalse);
    });

    test('an empty ranked list selects nothing and is not marked truncated', () {
      const selector = TokenBudgetSelector();
      final selection = selector.select(const []);
      expect(selection.selected, isEmpty);
      expect(selection.truncated, isFalse);
    });

    test('selection preserves rank order (best-first)', () {
      const selector = TokenBudgetSelector(charBudget: 1000);
      final ranked = [_ranked(1, 'first', score: 3), _ranked(2, 'second', score: 2), _ranked(3, 'third', score: 1)];

      final selection = selector.select(ranked);

      expect(selection.selected.map((c) => c.chunk.id), [1, 2, 3]);
    });
  });
}
