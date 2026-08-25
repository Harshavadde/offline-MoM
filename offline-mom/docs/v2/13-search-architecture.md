# V2 Search Architecture

## Current state (V1, as-built — not aspirational)

`SearchMeetingsUseCase` fans a query out to four repository methods (meeting title, transcript text, action-item description, decision description), each a `WHERE column LIKE '%query%'`, and unions the matched meeting ids. Two concrete problems, confirmed by direct code inspection, not assumed:

1. **A leading `%` wildcard can never use an index**, so every text search is a full table scan across `meetings`, `transcripts`, and `action_items` — the existing indexes (`idx_transcripts_meeting_id`, etc.) are all on foreign keys, none on the searched text columns.
2. **Summaries and notes are not searched at all**, despite both being real, populated tables today. This is a gap in the *current, shipped, meetings-only* product, not something the workspace pivot introduces.

Neither of these is acceptable to carry forward once Documents (potentially large extracted-text bodies) join the searchable corpus.

## V2 target: SQLite FTS5

Replace substring scanning with SQLite's built-in FTS5 full-text search extension — no new database engine, no new dependency beyond what `sqflite`'s underlying SQLite build already ships with (FTS5 is compiled into SQLite by default on Android). This is the smallest change that fixes both problems above.

**Design:**

- One `content_fts` virtual table (`CREATE VIRTUAL TABLE content_fts USING fts5(content_type, content_id, title, body)`), populated via triggers on insert/update/delete of `meetings`, `transcripts`, `summaries`, `action_items`, `notes`, and `documents` — a single unified index rather than one FTS table per source table, so a single query already returns results across every content type without the application needing to fan out and union manually the way `SearchMeetingsUseCase` does today.
- `content_type` distinguishes what kind of row `content_id` points back to (`meeting`, `transcript`, `summary`, `action_item`, `note`, `document`), letting the result list group/tag results by type ([FR-38](08-functional-requirements.md)) and resolve back to the right repository for the detail screen.
- Ranking via FTS5's built-in `bm25()` function rather than a hand-rolled scoring formula — consistent with the project's stated preference (already applied to hand-written SQL over an ORM) for using the database's own transparent, well-understood capability rather than reinventing it in application code.
- A single `WorkspaceSearchRepository.search(query)` method replaces the current four-repository fan-out in `SearchMeetingsUseCase`, resolving matched `(content_type, content_id)` pairs back into the actual entities the UI needs (mirroring today's `getByIds` pattern).

## Search vs. chat/RAG — two different retrieval mechanisms, not one

FTS5 search and the retrieval layer in [14-rag-architecture.md](14-rag-architecture.md) solve different problems and both are needed:

| | Search (FTS5) | Chat/RAG (embeddings) |
|---|---|---|
| Input | Keywords the user thinks are literally present | A natural-language question |
| Matches | Exact/stemmed word matches | Semantically related content, even without shared words |
| Output | A list of items to open | A synthesized answer, with citations |
| When the user reaches for it | "I know roughly what I'm looking for and just want to find it fast" | "I want an answer, and don't necessarily know which item has it" |

Building only FTS5 would leave "chat with your workspace" unanswerable for anything not phrased in the exact words the source content used. Building only embeddings-based retrieval would make simple, fast lookups (find the meeting titled "Q3 planning") slower and less precise than they need to be. V2 needs both, and they share almost no implementation — FTS5 is a schema/SQL concern, retrieval is an AI-pipeline concern (see [14-rag-architecture.md](14-rag-architecture.md)).

## Migration and rollout

FTS5 tables and their sync triggers land in migration v7 (see [12-database-design.md](12-database-design.md)), after `documents` (v4) and before the workspace search UI ships, so search can be built against the real unified index from the start rather than against the legacy fan-out pattern and then migrated later.
