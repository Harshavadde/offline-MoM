/// V2 scaffolding. Shared discriminator for "what kind of content is this,"
/// used wherever a piece of content needs to be referred to generically
/// across meetings/documents/etc. - the unified FTS5 search index
/// (docs/v2/13-search-architecture.md's `content_fts.content_type` column)
/// and [KnowledgeChunk]'s meeting-or-document association (ADR-005,
/// docs/v2/implementation/03-decisions.md) both use this same discriminator
/// rather than each inventing their own.
///
/// Not a new architectural decision - this mirrors exactly what
/// docs/v2/13-search-architecture.md already specified for the FTS5
/// `content_type` column; this enum is the Dart-side placeholder for it.
enum ContentType {
  meeting,
  transcript,
  summary,
  actionItem,
  note,
  document,
}
