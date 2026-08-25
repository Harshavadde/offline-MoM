import 'dart:convert';

import '../core/knowledge/content_type.dart';

/// One citation shown as a source chip under an assistant [ChatMessage] -
/// a human-readable label plus enough identity to distinguish citations
/// from different owners. Built once, at answer time, from the
/// [KnowledgeChunk]s `RetrievalEngine.retrieve` actually returned and that
/// were actually included in that turn's prompt context - never parsed
/// from the model's own text (ADR-026,
/// docs/v2/implementation/03-decisions.md: "no hallucinated citations").
///
/// A plain class (not `@freezed`), mirroring [KnowledgeChunk]'s own
/// reasoning: an internal, never-user-edited value type serialized as one
/// JSON array into [ChatMessage.sourcesJson], with no `copyWith` need.
class ChatSourceRef {
  const ChatSourceRef({
    required this.label,
    required this.contentType,
    this.meetingId,
    this.documentId,
    this.confidence,
  });

  /// Precomputed display text (e.g. "Weekly Standup — Transcript",
  /// "Q3 Report.pdf") - frozen at answer time rather than re-resolved from
  /// [meetingId]/[documentId] on every render, so a later meeting/document
  /// rename or deletion doesn't retroactively change (or break) history
  /// already shown to the user.
  final String label;

  final ContentType contentType;
  final int? meetingId;
  final int? documentId;

  /// The chunk's fused-ranking cosine similarity to the question (Phase
  /// 6B, Hybrid Retrieval Engine, ADR-037), roughly `[0, 1]` - null for
  /// citations from before this field existed (decoded from old
  /// `sources_json` rows with no `confidence` key) or, in principle, any
  /// future citation source that genuinely has no comparable score.
  /// Display-only (e.g. a subtle per-source indicator) - never used to
  /// re-derive [RetrievalConfidence], which is computed once, at answer
  /// time, and is a property of the whole answer, not of one citation.
  final double? confidence;

  Map<String, Object?> toMap() {
    return {
      'label': label,
      'content_type': contentType.name,
      'meeting_id': meetingId,
      'document_id': documentId,
      'confidence': confidence,
    };
  }

  factory ChatSourceRef.fromMap(Map<String, Object?> map) {
    return ChatSourceRef(
      label: map['label'] as String,
      contentType: ContentType.values.byName(map['content_type'] as String),
      meetingId: map['meeting_id'] as int?,
      documentId: map['document_id'] as int?,
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }

  /// Serializes a list of citations into the string stored in
  /// [ChatMessage.sourcesJson]. Returns null for an empty list rather than
  /// `'[]'`, matching [ChatMessage.sourcesJson]'s "null for no citations"
  /// convention (e.g. the honest-fallback case, which cites nothing).
  static String? encodeList(List<ChatSourceRef> sources) {
    if (sources.isEmpty) return null;
    return jsonEncode(sources.map((s) => s.toMap()).toList());
  }

  /// Inverse of [encodeList]. Null/empty input decodes to an empty list.
  static List<ChatSourceRef> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    final decoded = jsonDecode(json) as List;
    return decoded
        .cast<Map<String, Object?>>()
        .map(ChatSourceRef.fromMap)
        .toList();
  }
}
