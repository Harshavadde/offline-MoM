import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/services/retrieval/hybrid_ranker.dart';
import 'package:offline_mom/services/retrieval/scored_chunk.dart';

KnowledgeChunk _chunk(int id, {DateTime? createdAt}) {
  return KnowledgeChunk(
    id: id,
    contentType: ContentType.transcript,
    sourceId: 1,
    meetingId: 1,
    documentId: null,
    chunkIndex: 0,
    chunkText: 'chunk $id',
    embedding: const [1.0, 0.0],
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('HybridRanker.fuse', () {
    test('a chunk appearing in both vector and keyword results is deduplicated, not doubled', () {
      const ranker = HybridRanker();
      final chunk = _chunk(1);

      final result = ranker.fuse(
        vectorRanked: [chunk],
        keywordRanked: [ScoredChunk(chunk: chunk, score: 5.0)],
      );

      expect(result, hasLength(1));
      expect(result.single.matchedVector, isTrue);
      expect(result.single.matchedKeyword, isTrue);
      expect(result.single.bothMatched, isTrue);
    });

    test('a chunk matched by both signals outranks one matched by only one, all else equal', () {
      const ranker = HybridRanker();
      final both = _chunk(1);
      final vectorOnly = _chunk(2);

      final result = ranker.fuse(
        vectorRanked: [both, vectorOnly],
        keywordRanked: [ScoredChunk(chunk: both, score: 1.0)],
      );

      expect(result.first.chunk.id, 1);
      expect(result.first.bothMatched, isTrue);
      expect(result.last.chunk.id, 2);
      expect(result.last.bothMatched, isFalse);
    });

    test('rank position matters more than which list a chunk came from', () {
      const ranker = HybridRanker();
      final rankedFirstInVector = _chunk(1);
      final rankedFirstInKeyword = _chunk(2);

      final result = ranker.fuse(
        vectorRanked: [rankedFirstInVector],
        keywordRanked: [ScoredChunk(chunk: rankedFirstInKeyword, score: 99.0)],
      );

      // Both were rank 0 in their respective single-item lists - RRF gives
      // them equal contribution regardless of the keyword score being much
      // larger in raw terms (that's the whole point of rank-based fusion,
      // not raw-score fusion).
      expect(result[0].fusedScore, closeTo(result[1].fusedScore, 1e-9));
    });

    test('more recent chunks get a small boost over older, otherwise-equal chunks', () {
      const ranker = HybridRanker();
      final now = DateTime(2026, 6, 1);
      final recent = _chunk(1, createdAt: now.subtract(const Duration(days: 1)));
      final old = _chunk(2, createdAt: now.subtract(const Duration(days: 365)));

      final result = ranker.fuse(
        vectorRanked: [recent, old],
        keywordRanked: const [],
        now: now,
      );

      // Both start with the same RRF contribution (rank 0 vs rank 1 would
      // normally differ, so give them the same list position by running
      // two separate single-item fusions instead).
      final recentAlone = ranker.fuse(vectorRanked: [recent], keywordRanked: const [], now: now);
      final oldAlone = ranker.fuse(vectorRanked: [old], keywordRanked: const [], now: now);
      expect(recentAlone.single.fusedScore, greaterThan(oldAlone.single.fusedScore));
      expect(result, hasLength(2));
    });

    test('recency boost never lets an old chunk outrank a more relevant recent one', () {
      // maxRecencyBoost defaults to 10% - a chunk ranked much lower can't
      // be boosted past one ranked much higher no matter how old/new either is.
      const ranker = HybridRanker();
      final now = DateTime(2026, 6, 1);
      final highlyRelevantOld = _chunk(1, createdAt: DateTime(2020, 1, 1));
      final barelyRelevantNew = _chunk(2, createdAt: now);

      final result = ranker.fuse(
        vectorRanked: [highlyRelevantOld, _chunk(99), _chunk(98), barelyRelevantNew],
        keywordRanked: const [],
        now: now,
      );

      expect(result.first.chunk.id, 1);
    });

    test('empty inputs produce an empty result', () {
      const ranker = HybridRanker();
      expect(ranker.fuse(vectorRanked: const [], keywordRanked: const []), isEmpty);
    });

    test('a chunk with no id (never persisted) is safely skipped, not crashed on', () {
      const ranker = HybridRanker();
      final unpersisted = KnowledgeChunk(
        id: null,
        contentType: ContentType.transcript,
        sourceId: 1,
        meetingId: 1,
        documentId: null,
        chunkIndex: 0,
        chunkText: 'x',
        embedding: const [1.0],
        createdAt: DateTime(2026, 1, 1),
      );

      final result = ranker.fuse(vectorRanked: [unpersisted], keywordRanked: const []);
      expect(result, isEmpty);
    });
  });
}
