/// Discriminator for which library table a [ResumeBlockRef] resolves
/// against - the polymorphic counterpart to [ContentType]
/// (lib/core/knowledge/content_type.dart), the same "cannot be a real FK
/// across multiple possible parent tables" shape [KnowledgeChunk] already
/// uses for `content_type` + `source_id`.
enum ResumeBlockType {
  experience,
  education,
  project,
  certification,
  skill,

  /// A generic, user/import-labeled section (e.g. "Awards & Recognition",
  /// "Publications", "Volunteer Experience") that doesn't fit any of the
  /// other five typed slots above - beta data-fidelity requirement
  /// (docs/v3/implementation/03-decisions.md): an unrecognized resume
  /// section must be preserved, never silently discarded, even though this
  /// app has no dedicated structured field for it. Resolves against
  /// [CustomSectionBlock]/`custom_section_blocks` (migration v18).
  customSection,
}
