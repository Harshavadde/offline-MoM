# V2 Database Design

Extends V1's `docs/architecture/database-design.md`. All seven existing tables (`meetings`, `transcripts`, `summaries`, `action_items`, `decisions`, `recording_marks`, `notes`) carry forward with **no changes to their existing columns** (NFR-22). New tables are additive, following the existing conventions exactly: hand-written SQL (no ORM), `id` integer primary keys, `ON DELETE CASCADE` foreign keys, ISO-8601 text timestamps (for the same debuggability reason V1 chose them — directly `DateTime.parse`-able and human-readable via `adb shell` + `sqlite3`), and a migration file per version continuing the existing numbering (`v4.dart`, `v5.dart`, ...).

## New tables

### `documents`

Mirrors `meetings` structurally.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `title` | TEXT | Defaults to filename, user-renamable like a meeting |
| `source_type` | TEXT | `pdf` \| `docx` \| `txt` \| `markdown` |
| `file_path` | TEXT | Original file, kept (not extract-then-discard) — see [15-storage-architecture.md](15-storage-architecture.md) |
| `status` | TEXT | `created` → `extracting` → `indexing` → `ready`, or `error` — extends the `MeetingStatus` pattern with one new sub-stage (`indexing`) for chunking/embedding, which meetings don't currently have |
| `extracted_text` | TEXT | Full extracted plain text, same "store the whole thing, it's only read/written as a unit" rationale V1 already applies to `transcripts.full_text` |
| `error_message` | TEXT, nullable | Same purpose as `meetings.error_message` (added in V1's migration v2 specifically so a failure isn't a dead end) |
| `created_at`, `updated_at` | TEXT | ISO-8601 |

### `summaries` — reused, not duplicated

Rather than a parallel `document_summaries` table, `summaries.meeting_id` becomes nullable and a new nullable `summaries.document_id` is added, with a `CHECK` constraint enforcing exactly one of the two is set. This keeps summarization a single concept in the schema (one summary belongs to exactly one piece of content, meeting or document) rather than forking it, and means [FR-27](08-functional-requirements.md) (document summaries) reuses the existing `SummaryRepository` almost unchanged rather than needing a sibling repository.

```sql
ALTER TABLE summaries ADD COLUMN document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE;
-- meeting_id becomes nullable in the same migration
-- CHECK ((meeting_id IS NOT NULL) <> (document_id IS NOT NULL))
```

### `knowledge_chunks`

The retrieval layer's core table — see [14-rag-architecture.md](14-rag-architecture.md) for how it's populated and queried.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `meeting_id` | INTEGER, nullable, FK → `meetings(id)` CASCADE | Exactly one of `meeting_id`/`document_id` set |
| `document_id` | INTEGER, nullable, FK → `documents(id)` CASCADE | |
| `chunk_index` | INTEGER | Position within the source content, for ordering/debugging |
| `chunk_text` | TEXT | The chunk's raw text (kept alongside the embedding so retrieved chunks can be shown/cited without a second lookup) |
| `embedding` | BLOB | Serialized vector — see [14-rag-architecture.md](14-rag-architecture.md) for dimensionality and format, pending the embedding-model feasibility spike in [11-ai-architecture.md](11-ai-architecture.md) |
| `created_at` | TEXT | |

A `CHECK ((meeting_id IS NOT NULL) <> (document_id IS NOT NULL))` constraint, the same two-nullable-FK pattern used for `summaries` above, is preferred over a true polymorphic association — it stays queryable with real foreign keys and real cascade deletes rather than an unenforced `(content_type, content_id)` pair, consistent with the project's stated preference for transparent, debuggable SQL over cleverness.

### `chat_sessions` / `chat_messages`

| `chat_sessions` | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `title` | TEXT | Auto-derived from the first message, user-renamable |
| `scope` | TEXT | `general` \| `workspace` \| `document` |
| `document_id` | INTEGER, nullable, FK → `documents(id)` CASCADE | Set only when `scope = 'document'` |
| `created_at`, `updated_at` | TEXT | |

| `chat_messages` | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `session_id` | INTEGER, FK → `chat_sessions(id)` CASCADE | |
| `role` | TEXT | `user` \| `assistant` |
| `content` | TEXT | |
| `sources_json` | TEXT, nullable | Which meeting/document ids an assistant answer cited ([FR-30](08-functional-requirements.md)), JSON-encoded list, same "JSON-in-column for data that's only ever read/written as a whole" rationale already applied to `summaries.key_topics_json` |
| `created_at` | TEXT | |

Unlike the old Conversation Translator's deliberate in-memory-only design, chat history is persisted by default — see [17-privacy.md](17-privacy.md) for why that distinction is the right one (a translated stranger's spoken words vs. the user's own knowledge-base conversation are different privacy situations, not the same rule applied inconsistently).

## FTS5 virtual tables

Covered in detail in [13-search-architecture.md](13-search-architecture.md); noted here for schema completeness. New `CREATE VIRTUAL TABLE ... USING fts5(...)` tables shadow the searchable columns of `meetings`, `transcripts`, `summaries`, `action_items`, `notes`, and `documents`, kept in sync via SQLite triggers on insert/update/delete of the underlying tables — the standard FTS5-external-content pattern, chosen so the FTS index never has to be manually rebuilt by application code.

## Migration plan

- **v4**: `documents` table, `summaries.document_id` + nullable `meeting_id` + CHECK constraint, indexes on both new FK columns.
- **v5**: `knowledge_chunks` table + indexes on `meeting_id`/`document_id`.
- **v6**: `chat_sessions` + `chat_messages` tables + indexes.
- **v7**: FTS5 virtual tables + sync triggers for all searchable content.

Each migration is additive and independently applicable in sequence, matching the existing `onCreate` (apply all migrations fresh) / `onUpgrade` (apply only missing steps) pattern in `AppDatabase` — no existing migration (v1–v3) is touched.

## Also addressed while touching this area

Per Phase 0 in [07-feature-roadmap.md](07-feature-roadmap.md): add indexes on `meetings.status` and `meetings.is_favorite` (currently missing despite both being filtered on by History/Search), and resolve the vestigial `decisions` table's fate as an explicit decision rather than carrying it forward silently a second major version.
