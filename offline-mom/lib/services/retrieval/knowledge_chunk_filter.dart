import '../../core/knowledge/content_type.dart';
import '../../models/knowledge_chunk.dart';

/// Which owner type(s) a [KnowledgeChunkFilter] restricts a search to -
/// meeting-owned chunks, document-owned chunks, or (when the filter's
/// [KnowledgeChunkFilter.ownerType] is left null) both.
enum KnowledgeChunkOwnerType { meeting, document }

/// Scopes a [VectorStore]/[RetrievalEngine] similarity search - covers
/// every retrieval shape Milestone M1.2/1C calls for: workspace-wide
/// (no filter), meeting-only or document-only ([ownerType]), content-type
/// filtering ([contentTypes] - e.g. "only summaries"), and metadata
/// filtering to one specific meeting/document ([meetingId]/[documentId]).
/// A plain value object, not a query-builder - [BruteForceVectorStore]
/// applies it as an in-memory predicate ([matches]) before scoring, per
/// ADR-004's brute-force approach; a future `sqlite-vec`-style store
/// could instead translate it into a `WHERE` clause without this type
/// needing to change.
class KnowledgeChunkFilter {
  const KnowledgeChunkFilter({
    this.contentTypes,
    this.ownerType,
    this.meetingId,
    this.documentId,
  });

  /// Matches every chunk regardless of owner or content type - workspace
  /// -wide/mixed retrieval, the default when no filter is passed.
  static const workspace = KnowledgeChunkFilter();

  /// Meeting-owned chunks only (any content type: transcript, summary, or
  /// note), across every meeting.
  static const meetingsOnly = KnowledgeChunkFilter(ownerType: KnowledgeChunkOwnerType.meeting);

  /// Document-owned chunks only, across every document.
  static const documentsOnly = KnowledgeChunkFilter(ownerType: KnowledgeChunkOwnerType.document);

  /// Restricts to one specific meeting's chunks only.
  factory KnowledgeChunkFilter.forMeeting(int meetingId) =>
      KnowledgeChunkFilter(ownerType: KnowledgeChunkOwnerType.meeting, meetingId: meetingId);

  /// Restricts to one specific document's chunks only.
  factory KnowledgeChunkFilter.forDocument(int documentId) =>
      KnowledgeChunkFilter(ownerType: KnowledgeChunkOwnerType.document, documentId: documentId);

  /// Null matches every content type; otherwise only chunks whose
  /// [KnowledgeChunk.contentType] is in this set.
  final Set<ContentType>? contentTypes;

  /// Null matches both meeting- and document-owned chunks (mixed/workspace
  /// retrieval); otherwise restricts to just one owner kind.
  final KnowledgeChunkOwnerType? ownerType;

  /// When set, matches only this meeting's chunks (implies meeting-owned).
  final int? meetingId;

  /// When set, matches only this document's chunks (implies document-owned).
  final int? documentId;

  bool matches(KnowledgeChunk chunk) {
    if (contentTypes != null && !contentTypes!.contains(chunk.contentType)) {
      return false;
    }
    if (ownerType == KnowledgeChunkOwnerType.meeting && chunk.meetingId == null) {
      return false;
    }
    if (ownerType == KnowledgeChunkOwnerType.document && chunk.documentId == null) {
      return false;
    }
    if (meetingId != null && chunk.meetingId != meetingId) return false;
    if (documentId != null && chunk.documentId != documentId) return false;
    return true;
  }
}
