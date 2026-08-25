import 'dart:math';

import '../../models/knowledge_chunk.dart';
import '../../repositories/knowledge_chunk_repository.dart';
import 'knowledge_chunk_filter.dart';

/// Similarity search over embedded chunks - distinct from
/// [KnowledgeChunkRepository] (lib/repositories/knowledge_chunk_repository.dart),
/// which handles ordinary row access. Resolved by the M1.0 spike (ADR-004,
/// docs/v2/implementation/03-decisions.md): `sqlite-vec` (option 1) is not
/// usable from this app's `sqflite`-based database layer (it requires
/// `package:sqlite3`'s native FFI bindings, a different Flutter database
/// package this app does not use anywhere), so [BruteForceVectorStore]
/// (option 2) is the implementation - see the spike report for the full
/// reasoning.
abstract class VectorStore {
  /// Persists [chunk]'s embedding for later similarity search. Assumes
  /// [chunk].embedding is already populated by [EmbeddingEngine]
  /// (services/ai/embedding_engine.dart).
  Future<void> add(KnowledgeChunk chunk);

  /// Bulk form of [add] - [DefaultIndexingService] always has a whole
  /// content item's chunks ready at once; see
  /// [KnowledgeChunkRepository.insertAll]'s identical reasoning.
  Future<void> addAll(List<KnowledgeChunk> chunks);

  /// Returns the top [k] chunks most similar to [queryEmbedding], ordered
  /// most-similar first. See ADR-011 for the starting K value (3).
  /// [filter] (default [KnowledgeChunkFilter.workspace], i.e. no
  /// restriction) narrows the candidate set before scoring - workspace
  /// -wide/mixed, meeting-only, document-only, content-type, or one
  /// specific meeting/document, per ADR-021.
  Future<List<KnowledgeChunk>> similaritySearch(
    List<double> queryEmbedding, {
    required int k,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  });

  /// Tells an implementation that caches its view of `knowledge_chunks`
  /// (Phase 3A - see [BruteForceVectorStore]) that a mutation it wasn't
  /// itself the author of has happened - specifically, [IndexingService]
  /// deleting a source's previous chunks directly via
  /// [KnowledgeChunkRepository.deleteForSource] before re-indexing it,
  /// which this store has no other way to observe (unlike [add]/[addAll],
  /// which it can invalidate its own cache from directly since it performs
  /// them itself). A no-op for an implementation that doesn't cache.
  void invalidateCache();
}

/// Brute-force cosine similarity over every row in `knowledge_chunks`,
/// computed in Dart - the validated approach per ADR-004 at this app's
/// scoped corpus scale (NFR-16: hundreds to low thousands of chunks, not
/// millions). "Brute-force" describes the *scan* (every row is compared,
/// no index/pruning), not the similarity math itself, which is the
/// standard, correct cosine-similarity formula.
class BruteForceVectorStore implements VectorStore {
  BruteForceVectorStore({required KnowledgeChunkRepository knowledgeChunkRepository})
      : _knowledgeChunkRepository = knowledgeChunkRepository;

  final KnowledgeChunkRepository _knowledgeChunkRepository;

  /// In-memory cache of every chunk (embeddings already BLOB-decoded), so
  /// repeated retrieval calls in the same app session - every chat message,
  /// every search - don't re-fetch and re-decode the whole corpus from
  /// SQLite each time (Phase 3A). `null` means "no cached view, next read
  /// must hit the repository" - both the initial state and the state right
  /// after any invalidation, so a stale read is structurally impossible:
  /// every mutation this class performs itself ([add]/[addAll]) clears it,
  /// and [invalidateCache] covers the one mutation path it doesn't perform
  /// itself ([IndexingService]'s direct `deleteForSource` call).
  List<KnowledgeChunk>? _cache;

  Future<List<KnowledgeChunk>> _allChunks() async {
    final cached = _cache;
    if (cached != null) return cached;
    final all = await _knowledgeChunkRepository.getAll();
    _cache = all;
    return all;
  }

  @override
  Future<void> add(KnowledgeChunk chunk) async {
    await _knowledgeChunkRepository.insert(chunk);
    _cache = null;
  }

  @override
  Future<void> addAll(List<KnowledgeChunk> chunks) async {
    await _knowledgeChunkRepository.insertAll(chunks);
    _cache = null;
  }

  @override
  void invalidateCache() => _cache = null;

  @override
  Future<List<KnowledgeChunk>> similaritySearch(
    List<double> queryEmbedding, {
    required int k,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  }) async {
    if (k <= 0) return const [];
    final all = await _allChunks();
    if (all.isEmpty) return const [];

    // Filtered out before scoring, not after - no point computing a
    // cosine similarity for a chunk the caller has already excluded by
    // scope (e.g. a document-only search over a workspace that also has
    // meetings).
    final candidates = filter == KnowledgeChunkFilter.workspace
        ? all
        : all.where(filter.matches).toList();
    if (candidates.isEmpty) return const [];

    return _topK(candidates, queryEmbedding, k);
  }

  /// Selects the [k] highest-scoring chunks without allocating or sorting a
  /// scored entry for every candidate (Phase 3A) - the previous
  /// implementation allocated one `MapEntry` per candidate and fully
  /// sorted all of them even though only the top handful (`k`, per
  /// ADR-011 typically 3) were ever read. This instead keeps a bounded
  /// buffer of at most [k] entries, ascending by score, and only touches it
  /// when a new candidate's score beats the current worst kept one -
  /// O(candidates × k) with a tiny, fixed allocation instead of
  /// O(candidates) allocation + O(candidates log candidates) sort. Produces
  /// the exact same result as "score everything, sort descending, take k" -
  /// see `vector_store_test.dart`'s property-style test comparing the two
  /// directly across randomized corpora.
  static List<KnowledgeChunk> _topK(
    List<KnowledgeChunk> candidates,
    List<double> queryEmbedding,
    int k,
  ) {
    final top = <MapEntry<KnowledgeChunk, double>>[];
    for (final chunk in candidates) {
      final score = cosineSimilarity(queryEmbedding, chunk.embedding);
      if (top.length < k) {
        _insertSorted(top, MapEntry(chunk, score));
      } else if (score > top.first.value) {
        top.removeAt(0);
        _insertSorted(top, MapEntry(chunk, score));
      }
    }
    return [for (final entry in top.reversed) entry.key];
  }

  /// Inserts [entry] into [sorted] (ascending by score) at its correct
  /// position - [sorted] never exceeds [k] elements in [_topK]'s usage, so
  /// a linear scan for the insertion point is simpler than a binary search
  /// for no real cost at that size.
  static void _insertSorted(
    List<MapEntry<KnowledgeChunk, double>> sorted,
    MapEntry<KnowledgeChunk, double> entry,
  ) {
    var i = 0;
    while (i < sorted.length && sorted[i].value < entry.value) {
      i++;
    }
    sorted.insert(i, entry);
  }

  /// Standard cosine similarity: `dot(a, b) / (norm(a) * norm(b))`, range
  /// `[-1, 1]` (higher = more similar). Computed properly (not assumed to
  /// reduce to a bare dot product) even though [EmbeddingEngine] always
  /// L2-normalizes its output by convention - this function is correct
  /// independent of that upstream guarantee, and stays correct if it's
  /// ever violated (a mismatched vector length throws rather than
  /// silently producing a meaningless score).
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError(
        'Cannot compare embeddings of different lengths (${a.length} vs '
        '${b.length}) - they were not produced by the same embedding '
        'model.',
      );
    }
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
