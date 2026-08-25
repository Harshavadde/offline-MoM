import '../../models/knowledge_chunk.dart';
import '../ai/embedding_engine.dart';
import 'knowledge_chunk_filter.dart';
import 'vector_store.dart';

/// Turns a natural-language question into the top-K most relevant
/// [KnowledgeChunk]s, end to end: embed the query, then similarity-search
/// [VectorStore] - the two-step "query embedding → similarity search"
/// half of the pipeline in docs/v2/14-rag-architecture.md, kept as its
/// own component (rather than inlined into a future chat use case) so
/// [WorkspaceChatUseCase] (features/chat/workspace_chat_use_case.dart,
/// M1.3 - not implemented by this milestone) has one, already-tested
/// contract to call instead of re-deriving "embed then search" itself.
///
/// Supports every retrieval shape M1.2/M1.3 need (ADR-021,
/// docs/v2/implementation/03-decisions.md): workspace-wide/mixed
/// retrieval (the default, [KnowledgeChunkFilter.workspace]),
/// meeting-only ([KnowledgeChunkFilter.meetingsOnly]/[forMeeting]),
/// document-only ([KnowledgeChunkFilter.documentsOnly]/[forDocument]),
/// and content-type filtering ([KnowledgeChunkFilter.contentTypes]) - all
/// via the one [filter] parameter, not a family of near-duplicate
/// methods.
abstract class RetrievalEngine {
  /// Retrieves the [k] chunks (default 3, per ADR-011,
  /// docs/v2/implementation/03-decisions.md) most relevant to [query],
  /// narrowed by [filter] (default: no restriction).
  Future<List<KnowledgeChunk>> retrieve(
    String query, {
    int k = 3,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  });
}

class DefaultRetrievalEngine implements RetrievalEngine {
  DefaultRetrievalEngine({
    required EmbeddingEngine embeddingEngine,
    required VectorStore vectorStore,
  })  : _embeddingEngine = embeddingEngine,
        _vectorStore = vectorStore;

  final EmbeddingEngine _embeddingEngine;
  final VectorStore _vectorStore;

  @override
  Future<List<KnowledgeChunk>> retrieve(
    String query, {
    int k = 3,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final queryEmbedding = await _embeddingEngine.embed(trimmed);
    return _vectorStore.similaritySearch(queryEmbedding, k: k, filter: filter);
  }
}
