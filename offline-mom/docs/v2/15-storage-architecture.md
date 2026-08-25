# V2 Storage Architecture

## What already exists

V1 stores recorded/imported audio in the app's private storage directory (`getApplicationDocumentsDirectory()`/`getApplicationSupportDirectory()`, OS-sandboxed from other apps), the SQLite database in the same private area, and settings in a Hive box. The Storage settings screen already shows real usage (summed actual bytes, not an estimate) and lets a user clear cached model-conversion temp files. V2 extends this, it doesn't replace it.

## Where new content lives

- **Imported documents**: stored in app-private storage alongside audio recordings, in their own subdirectory (e.g. `documents/`) mirroring the existing `recordings/` directory convention. The **original file is kept**, not discarded after text extraction — the same choice V1 already made for audio (keep the source, not just its derived transcript), so a document can always be reopened in its original form, re-processed if extraction logic improves later, and included in backups as the actual file a user imported.
- **Extracted text**: stored in the `documents.extracted_text` column (see [12-database-design.md](12-database-design.md)), same rationale as `transcripts.full_text` being a column rather than a separate file — it's read/written as a unit with its parent row.
- **Chunk embeddings**: stored in `knowledge_chunks.embedding` as a BLOB, colocated with the chunk text in the same row rather than a separate embeddings-only file — keeps retrieval a single-table query rather than a join across a database and a filesystem cache.
- **Chat history**: `chat_sessions`/`chat_messages` tables, no separate file storage — it's small, structured, text data with no reason to leave SQLite.

## Storage growth model

Documents (especially PDFs) can be considerably larger than a typical meeting's audio-plus-transcript footprint, and a workspace accumulating months of both content types needs the existing storage-usage UX to stay honest, not just extend to a new number:

- The Storage screen's usage calculation extends to include the new `documents/` directory alongside the existing recordings directory and the SQLite file.
- Embeddings add a comparatively small but non-trivial amount of storage per chunk (exact size depends on the embedding dimensionality chosen during the Phase 1 feasibility spike — see [14-rag-architecture.md](14-rag-architecture.md) — a rough industry-typical range for small on-device embedding models is on the order of a few hundred to ~1500 floating-point dimensions, i.e. roughly 1–6KB per chunk before compression; this is an estimate to validate, not a committed figure).
- No new "clear cache" ambiguity is introduced: documents and their derived chunks are either kept (with the source document) or deleted entirely (with the source document) — there's no intermediate "regenerate-able cache" state for document content the way there already is for whisper's temporary WAV conversion files.

## Backup and export

V1's existing Backup screen shares a *copy* of the SQLite database file (deliberately not the live file, to avoid write races) plus the audio recordings directory, via the system share sheet. V2 extends the same mechanism to also include the `documents/` directory in that shared bundle — no new backup UI, no new sharing mechanism, just a larger set of files/directories included in the existing one-tap export.

## What does not change

The app-private, OS-sandboxed storage model; the "share a copy, not the live file" backup discipline; the no-cloud-sync constraint (backup remains a manual, user-initiated, local-file-share action, never an automatic upload); and the principle that deleting content deletes everything derived from it immediately, with no trash/recovery period — extended via `ON DELETE CASCADE` to documents and knowledge chunks the same way it already applies to meetings.
