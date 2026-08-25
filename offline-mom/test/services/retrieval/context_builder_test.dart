import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/services/retrieval/context_builder.dart';
import 'package:offline_mom/services/retrieval/hybrid_ranker.dart';

RankedChunk _ranked(int id, String text) {
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
    fusedScore: 1.0,
    matchedVector: true,
    matchedKeyword: false,
  );
}

void main() {
  group('ContextBuilder', () {
    const builder = ContextBuilder();

    test('formats each chunk with a "## label" header, matching the original prompt shape', () {
      final result = builder.build(
        [_ranked(1, 'The team approved the budget.')],
        {1: 'Standup — Transcript'},
      );

      expect(result.text, contains('## Standup — Transcript'));
      expect(result.text, contains('The team approved the budget.'));
      expect(result.includedChunkIds, [1]);
    });

    test('preserves given order (caller is responsible for passing already-ranked chunks)', () {
      final result = builder.build(
        [_ranked(1, 'first chunk'), _ranked(2, 'second chunk')],
        {1: 'Source A', 2: 'Source B'},
      );

      final indexA = result.text.indexOf('first chunk');
      final indexB = result.text.indexOf('second chunk');
      expect(indexA, lessThan(indexB));
    });

    test('falls back to a generic label when none is provided for a chunk id', () {
      final result = builder.build([_ranked(1, 'text')], const {});
      expect(result.text, contains('## Source'));
    });

    test('an empty chunk list produces an empty context', () {
      final result = builder.build(const [], const {});
      expect(result.text, isEmpty);
      expect(result.includedChunkIds, isEmpty);
    });
  });
}
