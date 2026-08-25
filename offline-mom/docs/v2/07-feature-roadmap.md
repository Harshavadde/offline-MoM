# V2 Feature Roadmap

Status: this document was written before implementation began and is kept as originally written (see [README.md](README.md) for why) — it does not reflect which phases have actually shipped. See [implementation/10-v2-progress.md](implementation/10-v2-progress.md) for real progress (Phases 0 through 5B complete as of this writing) and [20-future-roadmap.md](20-future-roadmap.md) for what's been added to the plan since.

Phased by dependency, not by calendar — each phase's output is a precondition for the next. This roadmap supersedes and extends (does not contradict) V1's own `docs/06-risk-and-future-scope.md`, which remains accurate for what it covers; items already listed there as V1 future scope are marked **(already planned in V1)** below rather than re-presented as new.

## Phase 0 — Foundation repair

Independent of the workspace pivot; makes everything after it safer to build. No new modules.

- Fix Workspace Search to cover summaries and notes (a gap that exists for meetings alone today, before Documents even exist).
- Migrate search from `LIKE`-scan to SQLite FTS5 (see [13-search-architecture.md](13-search-architecture.md)).
- Add an explicit request queue in front of the shared LLM engine (see [11-ai-architecture.md](11-ai-architecture.md)) — required before Documents/Chat can safely coexist with the existing meeting pipeline's background summarization calls.
- Resolve the vestigial `decisions` table/pipeline: either finally remove it, or leave it explicitly documented as permanent schema-compatibility dead weight — a decision, not a default.
- Add the disclosed-but-missing "audio file missing" `Meeting.status` state (V1 risk R5).
- Documentation sync pass: update V1 docs to reflect the Conversation Translator's removal and the Whisper default model change, so the documentation set as a whole stops describing a slightly different app than what's shipped.

## Phase 1 — Workspace infrastructure

The real technical bet. Nothing in Phase 2 or 3 is buildable without this landing first.

- **Document module**: `Document` model, repository, and import pipeline for PDF/DOCX/TXT/Markdown, following the existing audio-import architecture pattern exactly (see [10-system-architecture.md](10-system-architecture.md)).
- **Retrieval infrastructure**: chunking strategy, on-device embedding generation, local vector storage/search (see [14-rag-architecture.md](14-rag-architecture.md)). This item carries the most technical risk in the entire roadmap and should be preceded by a short feasibility spike — the same discipline that caught `flutter_llama`'s broken native build early in V1, rather than committing UI/product work against an unvalidated foundation.
- **Generalize Ask AI**: replace the current keyword-overlap-over-summaries implementation with retrieval-backed context assembly, extended to cover documents and notes, not just meeting summaries.

## Phase 2 — Workspace surface

User-facing modules built on Phase 1's infrastructure.

- General offline chat (no content scoping), with local chat history.
- Cross-content search UI (meetings + documents + notes in one result list).
- Source-cited answers (which meeting/document a chat answer's information came from), extending the existing "always show the transcript" trust pattern.
- Chunked/map-reduce summarization for long meetings and long documents, replacing the current flat ~4000-character truncation. **(already planned in V1, item 3 — now also required for documents, not just meetings)**.

## Phase 3 — Scale, quality, and monetization

- Configurable LLM size (extending the Whisper-model-size picker precedent already shipped), so users on capable devices can opt into a larger default model for better workspace-wide quality. **(already planned in V1, item 1, for Whisper; extending the same pattern to the LLM is new to V2)**.
- Byte-level download progress for any newly required model (embedding model, larger LLM tier). **(already planned in V1, item 4 — already substantially delivered for the existing models this session; extends automatically to new models)**.
- The premium-tier decision and implementation (see [18-subscription-model.md](18-subscription-model.md)).
- Real quality/battery/thermal benchmarking across devices — V1's own IEEE report calls this "the most important next step before considering this production-ready"; V2 should not launch commercially without addressing it.
- Play Store launch (see [19-playstore-launch.md](19-playstore-launch.md)) — substantially staged already; this phase closes the remaining gaps (hosted privacy policy, AAB, store listing assets).

## Explicitly not in this roadmap

Speaker diarization **(already planned in V1, item 5)** and re-introducing AI-extracted action items/decisions **(already planned in V1, item 7, conditional on a future larger model)** remain V1 future-scope items this roadmap doesn't resolve one way or the other — they're independent of the workspace pivot and can be picked up whenever, not blocked by anything above. iOS support **(already planned in V1, item 8)** is likewise unblocked by V2 (all native plugins already support it; it remains a scope decision) and is restated in [20-future-roadmap.md](20-future-roadmap.md) rather than scheduled here.
