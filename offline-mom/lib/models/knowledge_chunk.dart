import 'dart:typed_data';

import '../core/knowledge/content_type.dart';

/// One chunked, embedded piece of a meeting's transcript or a document's
/// extracted text - [ChunkingService] (services/retrieval/chunking_service.dart)
/// produces the text, [EmbeddingEngine] (services/ai/embedding_engine.dart)
/// produces the vector, [DefaultIndexingService]
/// (services/retrieval/indexing_service.dart) persists the result here via
/// [KnowledgeChunkRepository]. A plain class (not `@freezed`) - mirrors
/// [Note]'s simplicity, since this is an internal, never-user-edited value
/// type with no `copyWith` need.
class KnowledgeChunk {
  /// Not `const` (Phase 4B) - the meetingId/documentId-exactly-one-set
  /// invariant used to be an `assert`, which `flutter build --release`
  /// strips entirely (asserts only run in debug/profile builds); a bug
  /// that violated it would have built silently in release instead of
  /// failing loudly, corrupting a chunk's owner reference instead of
  /// surfacing the mistake. A real, always-enforced check needs a
  /// constructor body, which a `const` constructor's initializer list
  /// can't have - nothing in this codebase ever constructed one with
  /// `const` regardless (checked: this file's own declaration was the
  /// only `const KnowledgeChunk(...)` anywhere), so dropping it costs
  /// nothing.
  KnowledgeChunk({
    required this.id,
    required this.contentType,
    required this.sourceId,
    required this.meetingId,
    required this.documentId,
    required this.chunkIndex,
    required this.chunkText,
    required this.embedding,
    required this.createdAt,
  }) {
    if ((meetingId != null) == (documentId != null)) {
      throw ArgumentError('exactly one of meetingId/documentId must be set');
    }
  }

  final int? id;

  /// Which prose source this chunk came from (`document`, `transcript`,
  /// `summary`, `note`) - added in migration v8 (ADR-021,
  /// docs/v2/implementation/03-decisions.md). A meeting owns several
  /// independently-changing prose sources sharing one [meetingId]; this
  /// plus [sourceId] is what lets re-indexing one of them (e.g. a single
  /// edited note) leave the others' chunks untouched.
  final ContentType contentType;

  /// The source row's own primary key - the transcript's id, the
  /// summary's id, the individual note's id, or (for documents) the
  /// document's own id. Never the owning [meetingId]/[documentId].
  final int sourceId;
  final int? meetingId;
  final int? documentId;

  final int chunkIndex;
  final String chunkText;

  /// L2-normalized (by [EmbeddingEngine] convention), fixed-dimension for
  /// a given embedding model - dimensionality is read from the model at
  /// runtime (see [KnowledgeChunksTable.embeddingDim]), never assumed.
  final List<double> embedding;

  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'document_id': documentId,
      'content_type': contentType.name,
      'source_id': sourceId,
      'chunk_index': chunkIndex,
      'chunk_text': chunkText,
      'embedding': encodeEmbedding(embedding),
      'embedding_dim': embedding.length,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory KnowledgeChunk.fromMap(Map<String, Object?> map) {
    return KnowledgeChunk(
      id: map['id'] as int?,
      contentType: ContentType.values.byName(map['content_type'] as String),
      sourceId: map['source_id'] as int,
      meetingId: map['meeting_id'] as int?,
      documentId: map['document_id'] as int?,
      chunkIndex: map['chunk_index'] as int,
      chunkText: map['chunk_text'] as String,
      embedding: decodeEmbedding(
        map['embedding'] as Uint8List,
        map['embedding_dim'] as int,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Serializes an embedding vector as a little-endian float64 BLOB - the
  /// same "SQLite is the only store" commitment the rest of the schema
  /// already makes (ADR-004: brute-force Dart similarity search over rows
  /// in this table, no separate vector engine). float64 rather than
  /// float32 to avoid any precision loss relative to what the embedding
  /// model actually returns (`List<double>`) - at this app's corpus scale
  /// (NFR-16: hundreds to low thousands of chunks), the doubled storage
  /// cost per vector is immaterial.
  static Uint8List encodeEmbedding(List<double> embedding) {
    final bytes = Float64List.fromList(embedding);
    return bytes.buffer.asUint8List();
  }

  /// Inverse of [encodeEmbedding]. [dim] is read from
  /// [KnowledgeChunksTable.embeddingDim] rather than inferred from the
  /// BLOB's byte length alone, so a corrupted/truncated BLOB fails loudly
  /// (a length mismatch) instead of silently returning a short vector.
  static List<double> decodeEmbedding(Uint8List bytes, int dim) {
    final floats = bytes.buffer.asFloat64List(bytes.offsetInBytes, dim);
    if (floats.length != dim) {
      throw FormatException(
        'Embedding BLOB length (${floats.length}) does not match stored '
        'embedding_dim ($dim) - data may be corrupted.',
      );
    }
    return List<double>.unmodifiable(floats);
  }
}
