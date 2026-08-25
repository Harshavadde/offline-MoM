/// Central place for table and column name literals so repositories never
/// hand-type a column name more than once.
class MeetingsTable {
  MeetingsTable._();
  static const name = 'meetings';
  static const id = 'id';
  static const title = 'title';
  static const source = 'source';
  static const status = 'status';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
  static const durationSeconds = 'duration_seconds';
  static const audioFilePath = 'audio_file_path';
  static const errorMessage = 'error_message';
  static const isFavorite = 'is_favorite';
}

class TranscriptsTable {
  TranscriptsTable._();
  static const name = 'transcripts';
  static const id = 'id';
  static const meetingId = 'meeting_id';
  static const language = 'language';
  static const fullText = 'full_text';
  static const segmentsJson = 'segments_json';
  static const createdAt = 'created_at';
}

class SummariesTable {
  SummariesTable._();
  static const name = 'summaries';
  static const id = 'id';
  static const meetingId = 'meeting_id';

  /// Added in migration v6 alongside making [meetingId] nullable - exactly
  /// one of the two is ever set (enforced by a CHECK constraint), per
  /// ADR-005 (docs/v2/implementation/03-decisions.md): one shared
  /// `summaries` table for both meetings and documents, rather than a
  /// parallel `document_summaries` table.
  static const documentId = 'document_id';
  static const summaryText = 'summary_text';
  static const minutesOfMeeting = 'minutes_of_meeting';
  static const keyTopicsJson = 'key_topics_json';
  static const modelUsed = 'model_used';
  static const generatedAt = 'generated_at';
}

class ActionItemsTable {
  ActionItemsTable._();
  static const name = 'action_items';
  static const id = 'id';
  static const meetingId = 'meeting_id';
  static const description = 'description';
  static const owner = 'owner';
  static const dueDate = 'due_date';
  static const isCompleted = 'is_completed';
  static const createdAt = 'created_at';
}

class DecisionsTable {
  DecisionsTable._();
  static const name = 'decisions';
  static const id = 'id';
  static const meetingId = 'meeting_id';
  static const description = 'description';
  static const createdAt = 'created_at';
}

class RecordingMarksTable {
  RecordingMarksTable._();
  static const name = 'recording_marks';
  static const id = 'id';
  static const meetingId = 'meeting_id';
  static const offsetMs = 'offset_ms';
  static const createdAt = 'created_at';
}

class NotesTable {
  NotesTable._();
  static const name = 'notes';
  static const id = 'id';
  static const meetingId = 'meeting_id';
  static const content = 'content';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// Imported documents (migration v5, V2 Phase 1A) - see
/// `docs/v2/12-database-design.md` and `migrations/v5.dart`.
class DocumentsTable {
  DocumentsTable._();
  static const name = 'documents';
  static const id = 'id';
  static const title = 'title';
  static const originalFilename = 'original_filename';
  static const sourceType = 'source_type';
  static const mimeType = 'mime_type';
  static const fileSizeBytes = 'file_size_bytes';
  static const filePath = 'file_path';
  static const status = 'status';
  static const extractedText = 'extracted_text';
  static const errorMessage = 'error_message';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';

  /// Which [FoldersTable] row this document has been organized into
  /// (migration v15, V2.2 Production Hardening, Priority 2) - null means
  /// "All Documents", the default, unfiled view every document already
  /// had before this column existed. Deliberately not a real foreign key
  /// - same convention already established for `toolkit_files.tool_type`/
  /// `installed_models.model_id`: validated at the repository layer
  /// instead. [FolderRepository.delete] explicitly sets this back to null
  /// for every document in a folder before removing it, so this can never
  /// point at a folder that no longer exists.
  static const folderId = 'folder_id';
}

/// A user-created folder for organizing documents (migration v15, V2.2
/// Production Hardening, Priority 2). No relational structure beyond its
/// own name/timestamps - membership lives entirely on
/// [DocumentsTable.folderId], the same "child points at parent, no
/// separate join table" shape every other owned-content relationship in
/// this schema already uses. Empty folders are allowed by construction:
/// nothing about this table's existence depends on any document
/// referencing it.
class FoldersTable {
  FoldersTable._();
  static const name = 'folders';
  static const id = 'id';
  static const title = 'title';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// Chunked, embedded content for retrieval (migration v7, V2 Phase 1B) -
/// see `docs/v2/14-rag-architecture.md` and
/// `docs/v2/implementation/spikes/m1-0-embedding-spike.md`. Same
/// two-nullable-FK + CHECK pattern as [SummariesTable] (ADR-005).
class KnowledgeChunksTable {
  KnowledgeChunksTable._();
  static const name = 'knowledge_chunks';
  static const id = 'id';
  static const meetingId = 'meeting_id';
  static const documentId = 'document_id';

  /// Which source table/kind of prose this chunk came from (`document`,
  /// `transcript`, `summary`, `note`) - added in migration v8, V2 Phase
  /// 1C. Mirrors `content_fts.content_type`'s purpose exactly: a meeting
  /// owns multiple independently-changing prose sources (its transcript,
  /// its summary, each of its notes), so re-indexing one of them must
  /// never touch the others' chunks - scoping delete-then-reinsert by
  /// (`content_type`, `source_id`) together, not by `meeting_id` alone,
  /// is what makes that safe. See ADR-021.
  static const contentType = 'content_type';

  /// The source row's own primary key (the transcript's id, the summary's
  /// id, the individual note's id, or - for documents, unchanged since
  /// migration v7 - the document's own id) - never the owning
  /// meeting's/document's id. Added alongside [contentType] in migration
  /// v8; see its doc comment.
  static const sourceId = 'source_id';
  static const chunkIndex = 'chunk_index';
  static const chunkText = 'chunk_text';

  /// The embedding vector, serialized as a little-endian float64 BLOB (see
  /// `KnowledgeChunk.toMap`/`fromMap`) - not human-readable, but consistent
  /// with the rest of the schema's "SQLite is the only store, no separate
  /// vector engine" commitment (ADR-004).
  static const embedding = 'embedding';

  /// Vector dimensionality, stored redundantly alongside [embedding] so it
  /// can be read (and validated) without decoding the BLOB - the embedding
  /// model's actual output size is only known at runtime (see the spike
  /// report), so this is never a hardcoded constant.
  static const embeddingDim = 'embedding_dim';
  static const createdAt = 'created_at';
}

/// FTS5 "external content" virtual table over [KnowledgeChunksTable.chunkText]
/// (migration v14, V2 Phase 6B, Hybrid Retrieval Engine, ADR-037) - **not**
/// the same table as [ContentFtsTable]: that one indexes whole meetings/
/// documents/transcripts/summaries/notes at source-item granularity (one row
/// per meeting/document/etc., powering the Search screen only); this one
/// indexes individual [KnowledgeChunk] rows at the exact same granularity
/// vector retrieval already operates on, so a keyword match and a vector
/// match can be fused chunk-for-chunk (`KeywordSearchService`,
/// `HybridRetrievalPipeline`). Deliberately a second, separate index rather
/// than extending [ContentFtsTable] to a finer granularity - that table's
/// existing consumer ([SearchWorkspaceUseCase]/`SearchScreen`) has no use
/// for chunk-level rows and doing so would be an unrelated redesign of a
/// working, unrelated feature.
///
/// An "external content" table (`content=knowledge_chunks,
/// content_rowid=id` - see `migrations/v14.dart`) so [chunkText] is never
/// duplicated on disk; kept in sync purely by SQL triggers on
/// `knowledge_chunks` insert/update/delete, the same trigger-driven
/// discipline [ContentFtsTable] already established for its own source
/// tables - no Dart-side code is responsible for keeping this index
/// current, so it can never drift out of sync with a chunk write that
/// forgets to update it.
class KnowledgeChunksFtsTable {
  KnowledgeChunksFtsTable._();
  static const name = 'knowledge_chunks_fts';
  static const chunkText = 'chunk_text';
}

/// Chat conversations (migration v9, V2 Phase 2A) - see
/// `docs/v2/12-database-design.md` and ADR-025
/// (docs/v2/implementation/03-decisions.md). One session per conversation;
/// [scope] picks which of [meetingId]/[documentId] (if either) is set,
/// enforced by a CHECK constraint - the three-way extension of the
/// two-nullable-FK pattern already used for [SummariesTable]/
/// [KnowledgeChunksTable] (ADR-005).
class ChatSessionsTable {
  ChatSessionsTable._();
  static const name = 'chat_sessions';
  static const id = 'id';
  static const title = 'title';

  /// `general` | `workspace` | `document` | `meeting` - see [ChatScope].
  /// `general` is unused until M2.1 (ADR-025); Phase 2A only ever writes
  /// `workspace`, `document`, or `meeting`.
  static const scope = 'scope';

  /// Set only when [scope] = `meeting` - the [ChatScope.meeting] case added
  /// in Phase 2A (ADR-025), absorbing what `AskAboutMeetingsUseCase`
  /// previously handled as a separate feature (ADR-010).
  static const meetingId = 'meeting_id';

  /// Set only when [scope] = `document`.
  static const documentId = 'document_id';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';

  /// Added in migration v10 (V2 Phase 2B, ADR-028,
  /// docs/v2/implementation/03-decisions.md) - "pin conversation" is the one
  /// genuinely new Workspace Chat capability that milestone asked for
  /// (everything else - rename, delete, recent, resume - already existed
  /// from Phase 2A). Pinned sessions sort first in [ChatHistoryScreen].
  static const isPinned = 'is_pinned';
}

/// One turn (user question or assistant answer) within a [ChatSessionsTable]
/// conversation (migration v9, V2 Phase 2A).
class ChatMessagesTable {
  ChatMessagesTable._();
  static const name = 'chat_messages';
  static const id = 'id';
  static const sessionId = 'session_id';

  /// `user` | `assistant` - see [ChatMessageRole].
  static const role = 'role';
  static const content = 'content';

  /// JSON-encoded list of citation labels the assistant's answer drew on -
  /// derived from the [KnowledgeChunk]s `RetrievalEngine.retrieve` actually
  /// returned for this turn, never parsed from the model's own text
  /// (ADR-026, docs/v2/implementation/03-decisions.md: "no hallucinated
  /// citations"). Always null for `user`-role rows.
  static const sourcesJson = 'sources_json';
  static const createdAt = 'created_at';

  /// `local` | `general_knowledge` - added in migration v14 (V2 Phase 6B,
  /// Hybrid Retrieval Engine, ADR-037) - which prompt mode produced an
  /// assistant answer: retrieved-context-only (`local`, [LlmEngine
  /// .answerQuestionStream]) or the model's own parametric knowledge
  /// (`general_knowledge`, [LlmEngine.answerGeneralKnowledgeStream]) after
  /// hybrid retrieval found nothing confidently relevant. Persisted, not
  /// re-derived from `sources_json` being empty, since a `local` answer can
  /// legitimately have no citations too (none of that shouldn't happen in
  /// practice, but the two concepts - "which prompt was used" and "were any
  /// sources cited" - are independent and both real). Always null for
  /// `user`-role rows, same convention as [sourcesJson].
  static const answerProvenance = 'answer_provenance';
}

/// FTS5 virtual table backing full-text search (migration v4, extended in
/// v6 for documents). Not a regular table - see `migrations/v4.dart` and
/// `migrations/v6.dart` for how it's populated (trigger-synced from
/// `meetings`/`transcripts`/`summaries`/`action_items`/`notes`/`documents`,
/// one row per matchable piece of content) and
/// `content_search_repository.dart` for how it's queried.
class ContentFtsTable {
  ContentFtsTable._();
  static const name = 'content_fts';
  static const contentType = 'content_type';
  static const meetingId = 'meeting_id';

  /// Added in migration v6, alongside [DocumentsTable] - the document-side
  /// counterpart to [meetingId], for resolving a match back to the
  /// [Document] it belongs to.
  static const documentId = 'document_id';
  static const sourceId = 'source_id';
  static const title = 'title';
  static const body = 'body';
}

/// Student Toolkit outputs (migration v11, V2 Phase 5A) - one row per saved
/// compressed/resized image (Recent Files). Unlike every table above, this
/// one has no owning meeting/document and no FTS5 entry - toolkit outputs
/// aren't part of the workspace's searchable knowledge, they're standalone
/// files the user asked the toolkit to produce.
class ToolkitFilesTable {
  ToolkitFilesTable._();
  static const name = 'toolkit_files';
  static const id = 'id';

  /// `imageCompress` | `imageResize` | `scan` | `pdfCompress` | `pdfMerge` |
  /// `pdfSplit` | `pdfOrganize` - see [ToolkitToolType].
  static const toolType = 'tool_type';

  /// User-editable display name - defaults to the source file's name minus
  /// extension, same convention as `Document.title`.
  static const title = 'title';
  static const outputPath = 'output_path';
  static const fileSizeBytes = 'file_size_bytes';

  /// Null only if the source's original size genuinely couldn't be read -
  /// present for every normal compress/resize result, driving the
  /// before/after reduction percentage `ToolkitFile` displays.
  static const originalFileSizeBytes = 'original_file_size_bytes';
  static const isFavorite = 'is_favorite';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';

  /// Added in migration v12 (V2 Phase 5B) - page count for a scan or PDF
  /// output; null for image compress/resize rows, which have no notion of
  /// pages.
  static const pageCount = 'page_count';

  /// Which [ToolkitFoldersTable] row this file has been organized into
  /// (migration v21, P0-9 File-Manager Parity) - null means "All Files",
  /// the default, unfiled view every toolkit file already had before this
  /// column existed. Deliberately not a real foreign key - same convention
  /// as [DocumentsTable.folderId]/[toolType]: validated at the repository
  /// layer instead. [ToolkitFolderRepository.delete] explicitly sets this
  /// back to null for every file in a folder before removing it.
  static const folderId = 'folder_id';
}

/// A user-created folder for organizing Student Toolkit outputs (migration
/// v21, P0-9 File-Manager Parity) - the exact same shape as [FoldersTable]
/// (Documents' own folder table, v15), deliberately kept as its own,
/// separate table rather than shared: Documents and toolkit files are
/// unrelated content types with no shared lifecycle, so a folder
/// disappearing/renaming from one screen must never affect the other. See
/// ADR-047, docs/v2/implementation/03-decisions.md.
class ToolkitFoldersTable {
  ToolkitFoldersTable._();
  static const name = 'toolkit_folders';
  static const id = 'id';
  static const title = 'title';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// Models actually downloaded onto this device (migration v13, V2 Phase
/// 6A AI Model Manager) - one row per successfully completed download,
/// see [InstalledModel]'s doc comment for why a row here (not a
/// file-existence check) is the "installed" source of truth. Unlike every
/// content table above, this has no owning meeting/document/toolkit
/// output and no FTS5 entry - installed models are device configuration,
/// not user content.
class InstalledModelsTable {
  InstalledModelsTable._();
  static const name = 'installed_models';
  static const id = 'id';

  /// The `AiModelSpec.id` this row was downloaded from - not a foreign
  /// key (the catalog is static Dart data, not a table), so this is
  /// deliberately just a validated-in-code string reference, the same way
  /// `ToolkitFilesTable.toolType` references `ToolkitToolType` without an
  /// FK.
  static const modelId = 'model_id';

  /// `llm` | `embedding` | `speechToText` | `ocr` | `vision` |
  /// `translation` - `ModelKind.name`. Denormalized alongside [modelId]
  /// (recoverable from the catalog) purely so `getByKind` queries don't
  /// need to join through Dart-side catalog data.
  static const kind = 'kind';
  static const localPath = 'local_path';
  static const sizeBytes = 'size_bytes';
  static const downloadedAt = 'downloaded_at';

  /// Nullable - see [InstalledModel.localSha256]'s doc comment for what
  /// this fingerprint can and can't prove.
  static const localSha256 = 'local_sha256';

  /// 0/1 - at most one row per [kind] should have this set; enforced at
  /// the repository layer (`InstalledModelRepository.setActive`), not by
  /// a CHECK constraint, since "at most one" per a non-unique column
  /// value isn't expressible as a simple SQLite CHECK.
  static const isActive = 'is_active';
}

/// A Resume identity (migration v16, V3 Milestone 1, Resume Foundation) -
/// the container a user names and returns to, independent of any
/// particular saved version. Profile fields ([fullName]/[email]/[phone]/
/// [location]/[linksJson]) live inline, 1:1, rather than in a separate
/// table - the same "small, fixed shape, no reason to split out" reasoning
/// [FoldersTable] already applies to its own fields.
class ResumesTable {
  ResumesTable._();
  static const name = 'resumes';
  static const id = 'id';
  static const title = 'title';

  /// Reserved for M2's Job-Description-matching context - no Editor field
  /// reads or writes it in Milestone 1.
  static const targetRole = 'target_role';
  static const fullName = 'full_name';
  static const email = 'email';
  static const phone = 'phone';
  static const location = 'location';

  /// JSON-encoded list of `ResumeLink`s (`ResumeLink.encodeList`/
  /// `decodeList`) - mirrors [ChatMessagesTable.sourcesJson]'s "a list of
  /// small structured values serialized into one TEXT column" convention.
  static const linksJson = 'links_json';

  /// JSON-encoded ordered string list (migration v17, V3 Milestone 0) -
  /// short, non-relational achievement bullets. Deliberately not a
  /// block-library table: mirrors [linksJson]'s "small structured values,
  /// one TEXT column" convention rather than [ExperienceBlocksTable]'s
  /// reusable-block shape, since achievements have no reuse-across-resumes
  /// need.
  static const achievementsJson = 'achievements_json';

  /// Which template (archetype + token preset) last rendered this resume's
  /// draft (migration v17, V3 Milestone 0) - purely descriptive metadata;
  /// no Milestone 0 code assigns it a value. `NULL` until the Milestone 1
  /// template engine sets it.
  static const templateId = 'template_id';

  /// `1` for the single resume that is the user's "My Profile" (migration
  /// v19, Product Validation phase), `0` for every job-specific resume -
  /// see `Resume.isProfile`'s own doc comment for the full invariant.
  static const isProfile = 'is_profile';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// One reusable work-experience entry in the block library (migration v16,
/// V3 Milestone 1) - app-scoped, not resume-scoped: editing it here updates
/// every Resume that references it via [ResumeBlocksTable], since a resume
/// only ever holds a reference, never a copy.
class ExperienceBlocksTable {
  ExperienceBlocksTable._();
  static const name = 'experience_blocks';
  static const id = 'id';
  static const role = 'role';
  static const company = 'company';
  static const location = 'location';

  /// "YYYY-MM" - month-and-year precision only.
  static const startDate = 'start_date';

  /// Null means "Present."
  static const endDate = 'end_date';

  /// JSON-encoded ordered string list.
  static const bulletsJson = 'bullets_json';

  /// JSON-encoded ordered list of `{name, bullets}` objects (migration
  /// v20) - distinct sub-projects nested under this Experience entry
  /// (e.g. "SciLab", "ByHeart", "Crossword" under one role), each with
  /// its own name and bullet list, separate from this entry's own
  /// [bulletsJson]. Null on any row written before this column existed -
  /// [ExperienceBlock.fromMap] treats that identically to an explicit
  /// empty list.
  static const subProjectsJson = 'sub_projects_json';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// One reusable education entry in the block library (migration v16, V3
/// Milestone 1) - app-scoped, not resume-scoped, mirroring
/// [ExperienceBlocksTable]'s exact shape and reasoning.
class EducationBlocksTable {
  EducationBlocksTable._();
  static const name = 'education_blocks';
  static const id = 'id';
  static const institution = 'institution';
  static const degree = 'degree';
  static const fieldOfStudy = 'field_of_study';

  /// "YYYY-MM" - see [ExperienceBlocksTable.startDate].
  static const startDate = 'start_date';
  static const endDate = 'end_date';

  /// Honors/GPA/coursework - an optional JSON-encoded bullet list, `NULL`
  /// (not an empty array) when there's nothing to show.
  static const detailsJson = 'details_json';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// One reusable project entry in the block library (migration v16, V3
/// Milestone 1) - app-scoped, not resume-scoped, mirroring
/// [ExperienceBlocksTable]'s exact shape and reasoning.
class ProjectBlocksTable {
  ProjectBlocksTable._();
  static const name = 'project_blocks';
  static const id = 'id';

  /// The column is `name` - identifier is [projectName] rather than `name`
  /// only because [name] above already names this class's own table name.
  static const projectName = 'name';
  static const link = 'link';

  /// JSON-encoded ordered string list.
  static const bulletsJson = 'bullets_json';

  /// Nullable (migration v22) - [ProjectBlockStatus.name] ("planned"/
  /// "completed"), or absent/null for a row with no opinion either way.
  static const status = 'status';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// One reusable certification entry in the block library (migration v16,
/// V3 Milestone 1) - app-scoped, not resume-scoped, mirroring
/// [ExperienceBlocksTable]'s exact shape and reasoning. Unlike Experience/
/// Education/Project, this table has no bullet-list column - a
/// certification has no orderable/trimmable content for
/// [ResumeBlocksTable.overrideJson] to ever act on.
class CertificationBlocksTable {
  CertificationBlocksTable._();
  static const name = 'certification_blocks';
  static const id = 'id';

  /// The column is `name` - identifier is [certificationName] rather than
  /// `name` only because [name] above already names this class's own
  /// table name.
  static const certificationName = 'name';
  static const issuer = 'issuer';
  static const issuedDate = 'issued_date';
  static const credentialUrl = 'credential_url';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// The flat, categorized skill library (migration v16, V3 Milestone 1) -
/// app-scoped, not resume-scoped, attached to resumes the same way
/// [ExperienceBlocksTable] is (via [ResumeBlocksTable] with
/// `block_type = skill`). No `updated_at`: a skill is a short name plus a
/// category, never edited in place after creation - only added, attached/
/// detached, or deleted.
class SkillEntriesTable {
  SkillEntriesTable._();
  static const name = 'skill_entries';
  static const id = 'id';

  /// The column is `name` - identifier is [skillName] rather than `name`
  /// only because [name] above already names this class's own table name.
  static const skillName = 'name';

  /// `technical` | `tool` | `soft` - see `SkillCategory`.
  static const category = 'category';
  static const createdAt = 'created_at';
}

/// The library of generic, custom-titled resume sections (migration v18,
/// beta scope) - app-scoped, not resume-scoped, mirroring
/// [ProjectBlocksTable]'s exact shape. Backs [CustomSectionBlock], attached
/// to resumes via [ResumeBlocksTable] with
/// `block_type = ${ResumeBlockType.customSection}` exactly like every
/// other block type.
class CustomSectionBlocksTable {
  CustomSectionBlocksTable._();
  static const name = 'custom_section_blocks';
  static const id = 'id';
  static const title = 'title';

  /// JSON-encoded ordered string list.
  static const entriesJson = 'entries_json';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// A Resume's *live, editable* composition (migration v16, V3 Milestone 1)
/// - which library blocks it currently includes, in what order, with what
/// per-resume overrides. The polymorphic join row the Editor reads/writes
/// on every interaction; [blockType] + [blockId] resolve to whichever
/// library table [blockType] names - the same "cannot be a real FK across
/// multiple possible parent tables" shape [KnowledgeChunksTable] already
/// has for [KnowledgeChunksTable.contentType] + [KnowledgeChunksTable.sourceId].
/// [resumeId] is deliberately not a real foreign key either, same
/// convention as [DocumentsTable.folderId] - validated at the application
/// layer (`DeleteLibraryBlockUseCase`) instead.
class ResumeBlocksTable {
  ResumeBlocksTable._();
  static const name = 'resume_blocks';
  static const id = 'id';
  static const resumeId = 'resume_id';

  /// `experience` | `education` | `project` | `certification` | `skill` |
  /// `customSection` - see `ResumeBlockType`.
  static const blockType = 'block_type';

  /// The id within [blockType]'s own library table - never the owning
  /// [resumeId].
  static const blockId = 'block_id';
  static const sortOrder = 'sort_order';

  /// A per-resume trim (e.g. a subset of bullets), never touching the
  /// shared library block - only ever set for `experience`/`project`/
  /// `education` block types.
  static const overrideJson = 'override_json';
  static const createdAt = 'created_at';
}

/// One immutable, frozen snapshot of a Resume (migration v16, V3 Milestone
/// 1) - never edited once created, only created, listed, renamed (metadata
/// only), or deleted. [compiledSnapshot] is what guarantees this: once
/// written, it is never re-derived from the live block library, so a later
/// edit or deletion of a source block can never retroactively change what
/// a version means - mirrors [ChatMessagesTable]'s append-only spirit,
/// extended to versions.
class ResumeVersionsTable {
  ResumeVersionsTable._();
  static const name = 'resume_versions';
  static const id = 'id';
  static const resumeId = 'resume_id';

  /// The one permitted metadata edit target - never `compiled_snapshot`.
  static const versionLabel = 'version_label';

  /// JSON-encoded `ResumeSnapshot` - frozen at save time by
  /// `ResumeCompilerService.compile()`, never mutated after.
  static const compiledSnapshot = 'compiled_snapshot';

  /// Null until the optional PDF export step completes; a failed export
  /// never blocks the version itself from persisting.
  static const exportedPdfPath = 'exported_pdf_path';

  /// Which template rendered this frozen snapshot (migration v17, V3
  /// Milestone 0) - descriptive metadata, `NULL` for any version saved
  /// before the Milestone 1 template engine exists.
  static const templateId = 'template_id';

  /// Label-only JD-tailoring metadata (migration v17, V3 Milestone 0) -
  /// never the full JD text (docs/v3/01-prd.md §14/§16: JD content stays
  /// session-only). Both null for a version not tied to any JD.
  static const tailoredForJdTitle = 'tailored_for_jd_title';
  static const tailoredForJdCompany = 'tailored_for_jd_company';
  static const createdAt = 'created_at';
}

/// One proposed AI edit to a Resume's content (migration v17, V3 Milestone
/// 0) - see `SuggestedEdit`'s own doc comment for the full "AI proposes,
/// user decides" contract this table exists to enforce. [targetBlockType]/
/// [targetBlockId] are nullable together (a profile-level suggestion has
/// neither), the same optional polymorphic-reference shape
/// [ResumeBlocksTable] uses unconditionally.
class SuggestedEditsTable {
  SuggestedEditsTable._();
  static const name = 'suggested_edits';
  static const id = 'id';
  static const resumeId = 'resume_id';

  /// `experience` | `education` | `project` | `certification` | `skill` -
  /// see `ResumeBlockType`. `NULL` for a profile-level suggestion.
  static const targetBlockType = 'target_block_type';

  /// The id within [targetBlockType]'s own library table - `NULL` for a
  /// profile-level suggestion, never the owning [resumeId].
  static const targetBlockId = 'target_block_id';
  static const fieldName = 'field_name';
  static const originalValue = 'original_value';
  static const suggestedValue = 'suggested_value';
  static const sourceRequirement = 'source_requirement';

  /// `pending` | `accepted` | `rejected` | `edited` - see
  /// `SuggestedEditStatus`.
  static const status = 'status';
  static const createdAt = 'created_at';

  /// `NULL` while [status] is still `pending`.
  static const resolvedAt = 'resolved_at';
}
