import '../../core/knowledge/content_type.dart';
import '../../core/logging/app_logger.dart';
import '../../models/knowledge_chunk.dart';
import '../../repositories/knowledge_chunk_repository.dart';
import '../ai/embedding_engine.dart';
import 'chunking_service.dart';
import 'vector_store.dart';

const _log = AppLogger('IndexingService');

/// Orchestrates chunking + embedding + storage for one piece of content -
/// the background step that takes a `ready` meeting or document to fully
/// indexed, per FR-40 (docs/v2/08-functional-requirements.md: "every
/// piece of ready content shall be chunked and embedded automatically in
/// the background").
///
/// Composes [ChunkingService], [EmbeddingEngine]
/// (services/ai/embedding_engine.dart), [VectorStore], and
/// [KnowledgeChunkRepository] (lib/repositories/) - content-type-agnostic
/// by design (driven by [ContentType] plus exactly one of
/// [meetingId]/[documentId]) so both `DocumentIndexer`
/// (features/documents/document_indexer.dart) and a future meeting-side
/// equivalent share this one implementation rather than each
/// re-implementing chunk→embed→store.
abstract class IndexingService {
  /// Indexes one specific prose source - a meeting's transcript, a
  /// meeting's or document's summary, one meeting note, or a document's
  /// extracted text. [contentType] + [sourceId] identify *which* source
  /// (the source row's own id - see [KnowledgeChunk.sourceId]);
  /// [meetingId]/[documentId] (exactly one set) identify the owner every
  /// chunk is tagged with for owner-scoped queries/cascade delete.
  /// Idempotent and source-scoped: re-running for the same
  /// ([contentType], [sourceId]) pair replaces only that source's
  /// previous chunks, never a sibling source sharing the same owner (ADR-021,
  /// docs/v2/implementation/03-decisions.md) - safe to call again after a
  /// content edit or a failed prior attempt.
  Future<void> indexContent({
    required ContentType contentType,
    required int sourceId,
    int? meetingId,
    int? documentId,
    required String text,
  });

  /// Removes one source's chunks without replacing them - for when the
  /// source itself is deleted (e.g. a note removed by the user) rather
  /// than edited. The database's `ON DELETE CASCADE` already handles the
  /// case where the *owning* meeting/document is deleted; this handles
  /// the narrower case of one source disappearing while its owner still
  /// exists.
  Future<void> removeIndexForSource(ContentType contentType, int sourceId);
}

class DefaultIndexingService implements IndexingService {
  DefaultIndexingService({
    required ChunkingService chunkingService,
    required EmbeddingEngine embeddingEngine,
    required VectorStore vectorStore,
    required KnowledgeChunkRepository knowledgeChunkRepository,
  })  : _chunkingService = chunkingService,
        _embeddingEngine = embeddingEngine,
        _vectorStore = vectorStore,
        _knowledgeChunkRepository = knowledgeChunkRepository;

  final ChunkingService _chunkingService;
  final EmbeddingEngine _embeddingEngine;
  final VectorStore _vectorStore;
  final KnowledgeChunkRepository _knowledgeChunkRepository;

  /// One in-flight [indexContent] call per (contentType, sourceId) key at a
  /// time (Phase 3A) - see [indexContent]'s doc comment for why.
  final Map<String, Future<void>> _inFlight = {};

  static String _key(ContentType contentType, int sourceId) =>
      '${contentType.name}:$sourceId';

  @override
  Future<void> indexContent({
    required ContentType contentType,
    required int sourceId,
    int? meetingId,
    int? documentId,
    required String text,
  }) {
    // Not `assert` (Phase 4B) - `flutter build --release` strips asserts
    // entirely, and this is a real boundary this app's own call sites
    // (DocumentIndexer/MeetingIndexer/NotesController) all pass through,
    // not just an internal invariant - a violation here should fail
    // loudly in every build mode, not silently index a chunk with the
    // wrong (or no) owner in release.
    if ((meetingId != null) == (documentId != null)) {
      throw ArgumentError('exactly one of meetingId/documentId must be set');
    }

    // Duplicate-indexing guard (Phase 3A): two callers racing to index the
    // exact same source (e.g. a user double-tapping Retry, or a background
    // pipeline step and a manual retry landing at the same time) would
    // otherwise both run the delete-then-insert sequence below
    // concurrently, and since the delete happens synchronously up front
    // but the insert only after chunking/embedding (real async work), both
    // deletes could land before either insert - leaving two full,
    // duplicate chunk sets for the same source instead of one. Rather than
    // starting a second `_indexContent` run, a caller that arrives while
    // one is already in flight for the same key awaits that same
    // in-flight result - the source ends up indexed exactly once, not
    // duplicated and not skipped.
    final key = _key(contentType, sourceId);
    final existing = _inFlight[key];
    if (existing != null) {
      _log.info('Duplicate indexContent call for $key coalesced into the in-flight one.');
      return existing;
    }

    final future = _indexContent(
      contentType: contentType,
      sourceId: sourceId,
      meetingId: meetingId,
      documentId: documentId,
      text: text,
    ).whenComplete(() {
      // A block body, not `=> _inFlight.remove(key)`, deliberately: `Map
      // .remove` returns the *removed value* - which, here, is a
      // `Future<void>` (this very `future`, once assigned below).
      // `Future.whenComplete` awaits whatever its callback *returns* if
      // that's itself a Future - so an arrow-function callback that
      // returned `_inFlight.remove(key)` would hand back this exact
      // still-completing future, making `whenComplete` wait for the
      // future it belongs to before it can complete: a self-referential
      // deadlock that only manifests once the underlying work has fully
      // finished (every prior await genuinely completes; only the
      // outermost `Future` this method returns never resolves). A block
      // body's implicit `void` return avoids that entirely.
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<void> _indexContent({
    required ContentType contentType,
    required int sourceId,
    int? meetingId,
    int? documentId,
    required String text,
  }) async {
    // Clear this source's previous chunks first, so a re-index (a content
    // edit, or a retry after a partial failure) replaces rather than
    // duplicates - scoped to (contentType, sourceId), not the owning
    // meeting/document, so re-indexing one source (e.g. one edited note)
    // never touches a sibling source sharing the same owner (ADR-021).
    // Safe to do before the new chunks are ready since this whole method
    // already runs with the owning Meeting/Document parked in a
    // transient `indexing` status that no read path treats as final (see
    // DocumentIndexer/MeetingIndexer).
    await _knowledgeChunkRepository.deleteForSource(contentType, sourceId);
    // The store's own cache (if it has one, e.g. BruteForceVectorStore -
    // Phase 3A) has no other way to know about this delete, since it went
    // straight to the repository rather than through the store itself.
    _vectorStore.invalidateCache();

    final textChunks = _chunkingService.chunk(text);
    if (textChunks.isEmpty) return;

    final embeddings = await _embeddingEngine.embedBatch(
      [for (final chunk in textChunks) chunk.text],
    );

    final now = DateTime.now();
    final knowledgeChunks = [
      for (var i = 0; i < textChunks.length; i++)
        KnowledgeChunk(
          id: null,
          contentType: contentType,
          sourceId: sourceId,
          meetingId: meetingId,
          documentId: documentId,
          chunkIndex: textChunks[i].index,
          chunkText: textChunks[i].text,
          embedding: embeddings[i],
          createdAt: now,
        ),
    ];

    await _vectorStore.addAll(knowledgeChunks);
  }

  @override
  Future<void> removeIndexForSource(ContentType contentType, int sourceId) async {
    await _knowledgeChunkRepository.deleteForSource(contentType, sourceId);
    _vectorStore.invalidateCache();
  }
}
