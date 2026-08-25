-- OfflineMoMAI SQLite schema (v15 - final state after all migrations)
--
-- This is the raw-SQL equivalent of the cumulative effect of
-- lib/database/migrations/v1.dart through v15.dart, kept here for
-- reference/review; the Dart migration files are the actual source of
-- truth executed by the app (AppDatabase.open runs them in sequence on a
-- fresh install, or incrementally on an upgrade). Settings are
-- intentionally NOT a table here - they live in Hive instead (see
-- docs/architecture/database-design.md). There is no in-memory-only,
-- never-persisted content type in this app - an earlier iteration's
-- Conversation Translator was the one exception to that and has been
-- removed entirely.
--
-- See docs/architecture/database-design.md for the migration-by-migration
-- history (what each of v1-v15 added and why) and the full ER diagram.
--
-- v15 (Phase 9.3, folders) shipped 2026-08-06, tag phase-9-3 - see
-- docs/v2/implementation/10-v2-progress.md.

PRAGMA foreign_keys = ON;

-- ============================================================================
-- Meetings and their owned children (v1, extended v2/v3)
-- ============================================================================

CREATE TABLE meetings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  source TEXT NOT NULL,               -- 'recorded' | 'imported'
  status TEXT NOT NULL,               -- 'created' | 'downloadingModel' | 'transcribing'
                                       -- | 'downloadingSummaryModel' | 'summarizing'
                                       -- | 'indexing' | 'ready' | 'error'
  created_at TEXT NOT NULL,           -- ISO-8601
  updated_at TEXT NOT NULL,           -- ISO-8601
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  audio_file_path TEXT,
  error_message TEXT,                 -- set when status = 'error' (v2)
  is_favorite INTEGER NOT NULL DEFAULT 0   -- History's Favorites filter (v3)
);

CREATE TABLE transcripts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id INTEGER NOT NULL,
  language TEXT NOT NULL,
  full_text TEXT NOT NULL,
  segments_json TEXT NOT NULL,        -- JSON array of {start_ms, end_ms, text}
  created_at TEXT NOT NULL,
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE
);

-- Rebuilt in v6 to become polymorphic (meeting- or document-owned).
CREATE TABLE summaries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id INTEGER,                 -- nullable since v6
  document_id INTEGER,                -- added in v6
  summary_text TEXT NOT NULL,
  minutes_of_meeting TEXT NOT NULL,
  key_topics_json TEXT NOT NULL,      -- JSON array of strings
  model_used TEXT NOT NULL,
  generated_at TEXT NOT NULL,
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE,
  FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
  CHECK ((meeting_id IS NOT NULL) <> (document_id IS NOT NULL))
);

CREATE TABLE action_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id INTEGER NOT NULL,
  description TEXT NOT NULL,          -- user-entered; no longer AI-extracted
  owner TEXT,
  due_date TEXT,
  is_completed INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE
);

-- Never written to: the AI no longer extracts decisions, and there is no
-- manual "add decision" UI either. Kept for schema stability and because
-- the Export screen's per-section toggle and the search use case still
-- reference it (both are effectively no-ops now). See ai-architecture.md.
CREATE TABLE decisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id INTEGER NOT NULL,
  description TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE
);

-- A timestamp the user flagged mid-recording ("Mark"), used to jump to
-- that point during playback. Not a transcript segment.
CREATE TABLE recording_marks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id INTEGER NOT NULL,
  offset_ms INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE
);

-- Freeform per-meeting notes, independent of the AI summary.
CREATE TABLE notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE
);

CREATE INDEX idx_transcripts_meeting_id ON transcripts (meeting_id);
CREATE INDEX idx_summaries_meeting_id ON summaries (meeting_id);
CREATE INDEX idx_summaries_document_id ON summaries (document_id);
CREATE INDEX idx_action_items_meeting_id ON action_items (meeting_id);
CREATE INDEX idx_decisions_meeting_id ON decisions (meeting_id);
CREATE INDEX idx_recording_marks_meeting_id ON recording_marks (meeting_id);
CREATE INDEX idx_notes_meeting_id ON notes (meeting_id);

-- ============================================================================
-- Documents (v5, extended by v6's summaries/content_fts rework above)
-- ============================================================================

CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  original_filename TEXT NOT NULL,
  source_type TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL,
  file_path TEXT NOT NULL,
  status TEXT NOT NULL,                -- 'created' | 'extracting' | 'indexing'
                                        -- | 'summarizing' | 'ready' | 'error'
  extracted_text TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  folder_id INTEGER                    -- v15; nullable, NOT a foreign key (see
                                        -- folders table below), validated at the
                                        -- repository layer instead
);

-- ============================================================================
-- Document folders (v15) - a lightweight, purely organizational label.
-- folders has no foreign keys pointing into it from documents.folder_id
-- above (deliberately unenforced, matching toolkit_files.tool_type /
-- installed_models.model_id's existing convention); deleting a folder sets
-- every member document's folder_id back to NULL first
-- (FolderRepository.delete()), it never deletes the documents themselves.
-- ============================================================================

CREATE TABLE folders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX idx_documents_folder_id ON documents (folder_id);

-- ============================================================================
-- Retrieval: chunked, embedded content (v7, extended v8)
-- ============================================================================

CREATE TABLE knowledge_chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id INTEGER,                  -- nullable; exactly one of meeting/document set
  document_id INTEGER,
  content_type TEXT NOT NULL,          -- 'document' | 'transcript' | 'summary' | 'note' (v8)
  source_id INTEGER NOT NULL,          -- the source row's own PK, not the owning meeting/document id (v8)
  chunk_index INTEGER NOT NULL,
  chunk_text TEXT NOT NULL,
  embedding BLOB NOT NULL,             -- little-endian float64 vector
  embedding_dim INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE,
  FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
  CHECK ((meeting_id IS NOT NULL) <> (document_id IS NOT NULL))
);

CREATE INDEX idx_knowledge_chunks_meeting_id ON knowledge_chunks (meeting_id);
CREATE INDEX idx_knowledge_chunks_document_id ON knowledge_chunks (document_id);
CREATE INDEX idx_knowledge_chunks_content_type_source_id
  ON knowledge_chunks (content_type, source_id);

-- FTS5 "external content" index over knowledge_chunks.chunk_text (v14) -
-- powers the keyword half of Hybrid Retrieval for Chat. content=/content_rowid=
-- means chunk_text is never duplicated on disk, only the FTS5 index
-- structures are stored. Deliberately a *second*, separate FTS5 table from
-- content_fts below - different granularity (chunk vs. source-item),
-- different consumer (Chat vs. Search screen), no shared code path (ADR-037).
CREATE VIRTUAL TABLE knowledge_chunks_fts USING fts5(
  chunk_text,
  content='knowledge_chunks',
  content_rowid='id'
);

CREATE TRIGGER knowledge_chunks_fts_ai AFTER INSERT ON knowledge_chunks BEGIN
  INSERT INTO knowledge_chunks_fts(rowid, chunk_text)
  VALUES (new.id, new.chunk_text);
END;

CREATE TRIGGER knowledge_chunks_fts_ad AFTER DELETE ON knowledge_chunks BEGIN
  INSERT INTO knowledge_chunks_fts(knowledge_chunks_fts, rowid, chunk_text)
  VALUES('delete', old.id, old.chunk_text);
END;

CREATE TRIGGER knowledge_chunks_fts_au AFTER UPDATE ON knowledge_chunks BEGIN
  INSERT INTO knowledge_chunks_fts(knowledge_chunks_fts, rowid, chunk_text)
  VALUES('delete', old.id, old.chunk_text);
  INSERT INTO knowledge_chunks_fts(rowid, chunk_text)
  VALUES (new.id, new.chunk_text);
END;

-- ============================================================================
-- Chat (v9, extended v10 and v14)
-- ============================================================================

CREATE TABLE chat_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  scope TEXT NOT NULL,                 -- 'general' | 'workspace' | 'document' | 'meeting'
  meeting_id INTEGER,                  -- set only when scope = 'meeting'
  document_id INTEGER,                 -- set only when scope = 'document'
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  is_pinned INTEGER NOT NULL DEFAULT 0, -- v10; pinned sessions sort first
  FOREIGN KEY (meeting_id) REFERENCES meetings (id) ON DELETE CASCADE,
  FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
  CHECK ((scope = 'meeting') = (meeting_id IS NOT NULL)),
  CHECK ((scope = 'document') = (document_id IS NOT NULL))
);

CREATE INDEX idx_chat_sessions_meeting_id ON chat_sessions (meeting_id);
CREATE INDEX idx_chat_sessions_document_id ON chat_sessions (document_id);

CREATE TABLE chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL,
  role TEXT NOT NULL,                  -- 'user' | 'assistant'
  content TEXT NOT NULL,
  sources_json TEXT,                   -- citations, derived only from retrieved
                                        -- chunks, never parsed from model text;
                                        -- always null for 'user' rows
  created_at TEXT NOT NULL,
  answer_provenance TEXT,              -- v14: 'local' | 'general_knowledge';
                                        -- always null for 'user' rows
  FOREIGN KEY (session_id) REFERENCES chat_sessions (id) ON DELETE CASCADE
);

CREATE INDEX idx_chat_messages_session_id ON chat_messages (session_id);

-- ============================================================================
-- Student Toolkit outputs (v11, extended v12) - no foreign keys: a toolkit
-- output isn't owned by any meeting/document, and has no FTS5 entry either
-- (toolkit outputs aren't part of the workspace's searchable knowledge).
-- ============================================================================

CREATE TABLE toolkit_files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tool_type TEXT NOT NULL,             -- 'imageCompress' | 'imageResize' | 'scan'
                                        -- | 'pdfCompress' | 'pdfMerge' | 'pdfSplit'
                                        -- | 'pdfOrganize'
  title TEXT NOT NULL,
  output_path TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL,
  original_file_size_bytes INTEGER,    -- nullable
  is_favorite INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  page_count INTEGER                   -- v12; null for image compress/resize rows
);

-- ============================================================================
-- Installed AI models (v13) - device configuration, not user content; no
-- foreign keys, no FTS5 entry. model_id references ModelCatalog, a static
-- Dart data structure, not a database table.
-- ============================================================================

CREATE TABLE installed_models (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  model_id TEXT NOT NULL,
  kind TEXT NOT NULL,                  -- 'llm' | 'embedding' | 'speechToText'
                                        -- | 'ocr' | 'vision' | 'translation'
                                        -- (last three: reserved, zero catalog entries)
  local_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  downloaded_at TEXT NOT NULL,
  local_sha256 TEXT,                   -- nullable
  is_active INTEGER NOT NULL DEFAULT 0 -- at most one per kind, enforced at the
                                        -- repository layer, not a CHECK constraint
);

CREATE INDEX idx_installed_models_kind ON installed_models (kind);

-- ============================================================================
-- content_fts (v4, extended v6) - source-item granularity full-text search,
-- powers the Search screen only, via ContentSearchRepository. Trigger-synced
-- from meetings/transcripts/summaries/action_items/notes/documents. Not the
-- same table as knowledge_chunks_fts above - see that table's comment.
-- ============================================================================

CREATE VIRTUAL TABLE content_fts USING fts5(
  content_type UNINDEXED,     -- 'meeting' | 'transcript' | 'summary' | 'action_item'
                              -- | 'note' | 'document' | 'document_text'
  meeting_id UNINDEXED,
  document_id UNINDEXED,      -- added in v6
  source_id UNINDEXED,        -- the source row's own PK
  title,
  body
);

-- meetings: title changes via rename; searchable text is the title only.
CREATE TRIGGER meetings_fts_ai AFTER INSERT ON meetings BEGIN
  INSERT INTO content_fts (content_type, meeting_id, source_id, title, body)
  VALUES ('meeting', NEW.id, NEW.id, NEW.title, '');
END;
CREATE TRIGGER meetings_fts_au AFTER UPDATE OF title ON meetings BEGIN
  DELETE FROM content_fts WHERE content_type = 'meeting' AND source_id = OLD.id;
  INSERT INTO content_fts (content_type, meeting_id, source_id, title, body)
  VALUES ('meeting', NEW.id, NEW.id, NEW.title, '');
END;
CREATE TRIGGER meetings_fts_ad AFTER DELETE ON meetings BEGIN
  DELETE FROM content_fts WHERE content_type = 'meeting' AND source_id = OLD.id;
END;

-- transcripts: insert-only (TranscriptRepository has no update method).
CREATE TRIGGER transcripts_fts_ai AFTER INSERT ON transcripts BEGIN
  INSERT INTO content_fts (content_type, meeting_id, source_id, title, body)
  VALUES ('transcript', NEW.meeting_id, NEW.id, NULL, NEW.full_text);
END;
CREATE TRIGGER transcripts_fts_ad AFTER DELETE ON transcripts BEGIN
  DELETE FROM content_fts WHERE content_type = 'transcript' AND source_id = OLD.id;
END;

-- summaries: insert-only; writes whichever of meeting_id/document_id is set.
CREATE TRIGGER summaries_fts_ai AFTER INSERT ON summaries BEGIN
  INSERT INTO content_fts (content_type, meeting_id, document_id, source_id, title, body)
  VALUES ('summary', NEW.meeting_id, NEW.document_id, NEW.id, NULL,
    NEW.summary_text || ' ' || NEW.minutes_of_meeting || ' ' || NEW.key_topics_json);
END;
CREATE TRIGGER summaries_fts_ad AFTER DELETE ON summaries BEGIN
  DELETE FROM content_fts WHERE content_type = 'summary' AND source_id = OLD.id;
END;

-- action_items: insert-only (setCompleted never touches description).
CREATE TRIGGER action_items_fts_ai AFTER INSERT ON action_items BEGIN
  INSERT INTO content_fts (content_type, meeting_id, source_id, title, body)
  VALUES ('action_item', NEW.meeting_id, NEW.id, NULL, NEW.description);
END;
CREATE TRIGGER action_items_fts_ad AFTER DELETE ON action_items BEGIN
  DELETE FROM content_fts WHERE content_type = 'action_item' AND source_id = OLD.id;
END;

-- notes: the one source whose searchable text is genuinely editable after
-- creation, so it's the only one with an UPDATE trigger.
CREATE TRIGGER notes_fts_ai AFTER INSERT ON notes BEGIN
  INSERT INTO content_fts (content_type, meeting_id, source_id, title, body)
  VALUES ('note', NEW.meeting_id, NEW.id, NULL, NEW.content);
END;
CREATE TRIGGER notes_fts_au AFTER UPDATE OF content ON notes BEGIN
  DELETE FROM content_fts WHERE content_type = 'note' AND source_id = OLD.id;
  INSERT INTO content_fts (content_type, meeting_id, source_id, title, body)
  VALUES ('note', NEW.meeting_id, NEW.id, NULL, NEW.content);
END;
CREATE TRIGGER notes_fts_ad AFTER DELETE ON notes BEGIN
  DELETE FROM content_fts WHERE content_type = 'note' AND source_id = OLD.id;
END;

-- documents: title via rename (like meetings); extracted_text is set once by
-- the extraction pipeline and rarely edited directly, so it gets its own
-- 'document_text' content_type/trigger rather than sharing 'document'.
CREATE TRIGGER documents_fts_ai AFTER INSERT ON documents BEGIN
  INSERT INTO content_fts (content_type, document_id, source_id, title, body)
  VALUES ('document', NEW.id, NEW.id, NEW.title, '');
END;
CREATE TRIGGER documents_fts_au AFTER UPDATE OF title ON documents BEGIN
  DELETE FROM content_fts WHERE content_type = 'document' AND source_id = OLD.id;
  INSERT INTO content_fts (content_type, document_id, source_id, title, body)
  VALUES ('document', NEW.id, NEW.id, NEW.title, '');
END;
CREATE TRIGGER documents_fts_ad AFTER DELETE ON documents BEGIN
  DELETE FROM content_fts
    WHERE content_type IN ('document', 'document_text') AND source_id = OLD.id;
END;
CREATE TRIGGER document_text_fts_au AFTER UPDATE OF extracted_text ON documents
  WHEN NEW.extracted_text IS NOT NULL BEGIN
  DELETE FROM content_fts WHERE content_type = 'document_text' AND source_id = NEW.id;
  INSERT INTO content_fts (content_type, document_id, source_id, title, body)
  VALUES ('document_text', NEW.id, NEW.id, NULL, NEW.extracted_text);
END;

-- ============================================================================
-- Example queries (see lib/repositories/*.dart,
-- lib/features/search/search_workspace_use_case.dart, and
-- lib/services/retrieval/ for the real query paths):
-- ============================================================================

-- Search screen (content_fts, unranked, source-item granularity):
-- SELECT * FROM content_fts WHERE content_fts MATCH 'budget';

-- Hybrid Retrieval keyword half (knowledge_chunks_fts, BM25, chunk granularity):
-- SELECT rowid, bm25(knowledge_chunks_fts) AS rank FROM knowledge_chunks_fts
--   WHERE knowledge_chunks_fts MATCH 'budget' ORDER BY rank;

-- Search by date range:
-- SELECT id FROM meetings WHERE created_at >= '2026-03-10T00:00:00.000'
--   AND created_at < '2026-03-11T00:00:00.000';
