import '../../models/chat_session.dart' show ChatScope;
import '../ai/embedding_engine.dart';
import 'hybrid_ranker.dart';
import 'keyword_search_service.dart';
import 'knowledge_chunk_filter.dart';
import 'query_classifier.dart';
import 'retrieval_confidence.dart';
import 'token_budget_selector.dart';
import 'vector_store.dart';

/// Retrieval Statistics (Phase 6B objective 13, ADR-037) - per-query
/// diagnostics, not a persisted history (no product requirement to keep
/// these over time, and no new table was added for it - kept in-memory,
/// part of the result object, consistent with "avoid unnecessary database
/// redesign").
class RetrievalStats {
  const RetrievalStats({
    required this.vectorCandidateCount,
    required this.keywordCandidateCount,
    required this.fusedCandidateCount,
    required this.selectedForContextCount,
    required this.truncatedByBudget,
    required this.elapsed,
  });

  final int vectorCandidateCount;
  final int keywordCandidateCount;

  /// Deduplicated-by-id count after [HybridRanker.fuse] - always
  /// `<= vectorCandidateCount + keywordCandidateCount` (equal only when no
  /// chunk matched both stages).
  final int fusedCandidateCount;
  final int selectedForContextCount;
  final bool truncatedByBudget;
  final Duration elapsed;
}

/// Everything one hybrid-retrieval call produced - what
/// `WorkspaceChatUseCase` needs to decide *how* to answer (confidence)
/// and *what* to answer with (selectedChunks), plus enough detail to
/// explain the decision (classification, stats).
class HybridRetrievalResult {
  const HybridRetrievalResult({
    required this.selectedChunks,
    required this.chunkConfidence,
    required this.confidence,
    required this.classification,
    required this.stats,
  });

  /// Budget-selected, ranked, best-first - exactly the chunks that should
  /// become the prompt context and the cited sources. Empty when
  /// [confidence] is [RetrievalConfidence.none] (nothing to select) or
  /// [RetrievalConfidence.low] (see `WorkspaceChatUseCase`'s policy: low
  /// confidence still triggers the general-knowledge path, so its
  /// candidate chunks are deliberately not used as unreliable citations).
  final List<RankedChunk> selectedChunks;

  /// Real, per-chunk cosine similarity for each entry in [selectedChunks]
  /// (keyed by [KnowledgeChunk.id]) - Source Attribution/Confidence
  /// Scoring (Phase 6B objectives 9/10, ADR-037), computed once here
  /// (bounded by the small `selectedChunks` count, not the whole
  /// candidate pool) since only the pipeline has the query embedding
  /// needed to compute it. `WorkspaceChatUseCase` attaches this to each
  /// [ChatSourceRef] it builds.
  final Map<int, double> chunkConfidence;

  final RetrievalConfidence confidence;
  final QueryClassification classification;
  final RetrievalStats stats;
}

/// Orchestrates the full multi-stage pipeline (Phase 6B objective 12,
/// ADR-037): classify → parallel vector + keyword retrieval → fuse/rank →
/// confidence → token-budget select. Composes existing, unmodified
/// infrastructure rather than replacing it - [VectorStore] (not
/// [RetrievalEngine], to avoid a second, redundant [EmbeddingEngine.embed]
/// call for the same query - see the constructor doc comment) and the new
/// [KeywordSearchService] run **concurrently**, since keyword search has
/// no dependency on the query embedding at all - a real parallelism win
/// this app never had before this phase (previously, only the vector path
/// existed, so there was nothing to parallelize).
class HybridRetrievalPipeline {
  HybridRetrievalPipeline({
    required EmbeddingEngine embeddingEngine,
    required VectorStore vectorStore,
    required KeywordSearchService keywordSearchService,
    QueryClassifier queryClassifier = const DefaultQueryClassifier(),
    HybridRanker ranker = const HybridRanker(),
    RetrievalConfidenceScorer confidenceScorer = const RetrievalConfidenceScorer(),
    TokenBudgetSelector tokenBudgetSelector = const TokenBudgetSelector(),
  })  : _embeddingEngine = embeddingEngine,
        _vectorStore = vectorStore,
        _keywordSearchService = keywordSearchService,
        _queryClassifier = queryClassifier,
        _ranker = ranker,
        _confidenceScorer = confidenceScorer,
        _tokenBudgetSelector = tokenBudgetSelector;

  final EmbeddingEngine _embeddingEngine;
  final VectorStore _vectorStore;
  final KeywordSearchService _keywordSearchService;
  final QueryClassifier _queryClassifier;
  final HybridRanker _ranker;
  final RetrievalConfidenceScorer _confidenceScorer;
  final TokenBudgetSelector _tokenBudgetSelector;

  /// Runs the full pipeline for one chat turn. [scope]/[meetingId]/
  /// [documentId] mirror `ChatSession`'s own fields - the filter-from-scope
  /// mapping lives here (not duplicated in `WorkspaceChatUseCase`) since
  /// it's the same mapping [QueryClassifier] already needs [scope] for.
  Future<HybridRetrievalResult> run({
    required String question,
    required ChatScope scope,
    int? meetingId,
    int? documentId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final classification = _queryClassifier.classify(question, scope);
    final filter = switch (scope) {
      ChatScope.meeting => KnowledgeChunkFilter.forMeeting(meetingId!),
      ChatScope.document => KnowledgeChunkFilter.forDocument(documentId!),
      ChatScope.workspace || ChatScope.general => KnowledgeChunkFilter.workspace,
    };

    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      stopwatch.stop();
      return HybridRetrievalResult(
        selectedChunks: const [],
        chunkConfidence: const {},
        confidence: RetrievalConfidence.none,
        classification: classification,
        stats: RetrievalStats(
          vectorCandidateCount: 0,
          keywordCandidateCount: 0,
          fusedCandidateCount: 0,
          selectedForContextCount: 0,
          truncatedByBudget: false,
          elapsed: stopwatch.elapsed,
        ),
      );
    }

    // The query embedding is computed exactly once and reused for both the
    // vector-search call below and the confidence recomputation later -
    // Phase 6B objective 16 "Retrieval Performance Optimization" ("avoid
    // unnecessary embedding calculations").
    final queryEmbedding = await _embeddingEngine.embed(trimmed);

    // Both calls start immediately (Dart futures run eagerly); awaiting
    // them sequentially below only affects when *this* method observes
    // each result, not when the underlying work runs - true concurrency
    // without `Future.wait`'s type-unification issues across two
    // unrelated result types ([KnowledgeChunk] vs [ScoredChunk]).
    final vectorFuture =
        _vectorStore.similaritySearch(queryEmbedding, k: classification.candidateK, filter: filter);
    final keywordFuture =
        _keywordSearchService.search(trimmed, k: classification.candidateK, filter: filter);
    final vectorResults = await vectorFuture;
    final keywordResults = await keywordFuture;

    final ranked = _ranker.fuse(vectorRanked: vectorResults, keywordRanked: keywordResults);

    double? topCosine;
    var keywordAgreed = false;
    if (ranked.isNotEmpty) {
      final top = ranked.first;
      topCosine = BruteForceVectorStore.cosineSimilarity(queryEmbedding, top.chunk.embedding);
      keywordAgreed = top.bothMatched;
    }
    final confidence = _confidenceScorer.classify(
      anyCandidates: ranked.isNotEmpty,
      topCosineSimilarity: topCosine,
      keywordAlsoMatched: keywordAgreed,
    );

    // Low/none confidence: `WorkspaceChatUseCase` takes the general-
    // knowledge path and must never cite these chunks as if they reliably
    // answered the question - selecting nothing here is what makes "no
    // fabricated citations" structurally true rather than a convention the
    // caller has to remember.
    final usableForContext = confidence == RetrievalConfidence.high || confidence == RetrievalConfidence.medium;
    final selection = usableForContext
        ? _tokenBudgetSelector.select(ranked)
        : const TokenBudgetSelection(selected: [], truncated: false);

    final chunkConfidence = <int, double>{
      for (final rankedChunk in selection.selected)
        if (rankedChunk.chunk.id != null)
          rankedChunk.chunk.id!:
              BruteForceVectorStore.cosineSimilarity(queryEmbedding, rankedChunk.chunk.embedding),
    };

    stopwatch.stop();
    return HybridRetrievalResult(
      selectedChunks: selection.selected,
      chunkConfidence: chunkConfidence,
      confidence: confidence,
      classification: classification,
      stats: RetrievalStats(
        vectorCandidateCount: vectorResults.length,
        keywordCandidateCount: keywordResults.length,
        fusedCandidateCount: ranked.length,
        selectedForContextCount: selection.selected.length,
        truncatedByBudget: selection.truncated,
        elapsed: stopwatch.elapsed,
      ),
    );
  }
}
