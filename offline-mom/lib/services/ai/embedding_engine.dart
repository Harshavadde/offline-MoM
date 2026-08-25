/// Contract for turning text into a fixed-dimension vector, entirely
/// on-device - see docs/v2/17-privacy.md: no cloud embedding API is
/// permitted regardless of which concrete implementation satisfies this.
///
/// Resolved by the M1.0 feasibility spike (ADR-003,
/// docs/v2/implementation/03-decisions.md;
/// docs/v2/implementation/spikes/m1-0-embedding-spike.md): option 1 (a
/// dedicated small embedding model through the same `llamadart`/
/// `llama.cpp` path the chat LLM already uses) is confirmed feasible -
/// [LlamaDartEmbeddingEngine] is the concrete implementation.
abstract class EmbeddingEngine {
  /// Turns [text] into a fixed-dimension vector. [normalize] (default
  /// true) L2-normalizes the result, matching every stored embedding in
  /// `knowledge_chunks` so cosine similarity search
  /// (services/retrieval/vector_store.dart) is comparing like with like.
  Future<List<double>> embed(String text, {bool normalize = true});

  /// Embeds every string in [texts] in one call where the underlying
  /// engine supports batching (llamadart's `embedBatch`, per the spike) -
  /// [DefaultIndexingService] always has every chunk for one content item
  /// ready at once, so batching real work rather than looping [embed]
  /// call-by-call is a real efficiency gain, not a premature one.
  Future<List<List<double>>> embedBatch(List<String> texts, {bool normalize = true});

  /// One-time model download/load, mirrors [LlmEngine.ensureModelReady]'s
  /// existing pattern exactly (including [onPreparingModel], fired only
  /// on an actual first-run download, never on a cache hit).
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  });
}
