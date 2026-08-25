# V2 Engineering Backlog

Organized Epic → Feature → Story → Task, mapped to the milestones in [01-master-roadmap.md](01-master-roadmap.md). Every task lists Priority (P0=blocking/critical, P1=high, P2=medium, P3=low), Estimated Difficulty (S/M/L/XL, roughly half-day / 1–2 days / 3–5 days / spike-or-unknown), Dependencies, Acceptance Criteria, and Status (all `Not Started` — this is the initial backlog, not a live tracker; see [10-v2-progress.md](10-v2-progress.md) for the status dashboard). Subtasks are shown in full for a representative sample of the most complex tasks (the LLM queue and the embedding spike) to establish the pattern; the remaining tasks are specified at Task granularity, since fully subtasking all ~90 tasks in a planning document would be noise, not signal — subtasks for the rest are created in the team's tracker as each Story is picked up.

---

## EPIC 1 — Foundation Repair

*Corresponds to Roadmap Phase 0 (M0.1–M0.4).*

### Feature 1.1 — Workspace search parity

**Story 1.1.1**: As a user, I want search to find content in summaries and notes, not just titles/transcripts/action items.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 1.1.1.1 Design FTS5 schema for existing content types | P0 | M | None | Schema reviewed against `docs/v2/13-search-architecture.md`; covers meetings/transcripts/summaries/action_items/notes | Not Started |
| 1.1.1.2 Write migration v4 (FTS5 tables + sync triggers) | P0 | M | 1.1.1.1 | Fresh install and upgrade-from-v3 both land on identical schema | Not Started |
| 1.1.1.3 Rewrite `SearchMeetingsUseCase` to query FTS5 | P0 | M | 1.1.1.2 | All existing search tests pass; new tests cover summary/note matches | Not Started |
| 1.1.1.4 Regression-test search latency on a seeded large dataset | P1 | S | 1.1.1.3 | No latency regression vs. current `LIKE`-based search on an equivalent dataset size | Not Started |

### Feature 1.2 — LLM request queue

**Story 1.2.1**: As the system, concurrent LLM requests must never fail outright — they must queue safely.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 1.2.1.1 Implement `LlmRequestQueue` (FIFO + foreground-pause behavior, per ADR-008) | P0 | L | None | See subtasks below | Not Started |
| 1.2.1.2 Route `GenerateMeetingSummaryUseCase` through the queue | P0 | S | 1.2.1.1 | Existing summary generation tests pass unmodified in behavior | Not Started |
| 1.2.1.3 Route `AskAboutMeetingsUseCase` through the queue | P0 | S | 1.2.1.1 | Existing Ask AI tests pass unmodified in behavior | Not Started |
| 1.2.1.4 Write the concurrency regression test (two simultaneous calls both succeed) | P0 | M | 1.2.1.2, 1.2.1.3 | Test fails on the pre-queue codebase, passes after | Not Started |

**Subtasks of 1.2.1.1** (representative full depth):
- Define the queue's public interface (`enqueue(request) → Future<Response>`).
- Implement FIFO ordering with a single in-flight slot, matching the engine's actual one-at-a-time capability.
- Implement the foreground-pause rule: a background-originated request checks for pending/in-flight foreground requests before starting.
- Wire the existing 45-second stall timeout to apply per dequeued request, not to queue wait time.
- Ensure engine failure (including timeout) advances the queue to the next request rather than stalling it.
- Unit test: FIFO ordering under simulated concurrent submission.
- Unit test: foreground-pause behavior under simulated background+foreground contention.

### Feature 1.3 — Schema/pipeline hygiene

**Story 1.3.1**: As a maintainer, disclosed V1 gaps should be closed or explicitly closed-out before more schema work lands on top.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 1.3.1.1 Add `audioMissing` to `Meeting.status` + handling in the pipeline | P1 | M | None | A meeting with a missing audio file at pipeline start reaches `audioMissing`, not generic `error` | Not Started |
| 1.3.1.2 Document `decisions` table resolution (ADR-012) in code comments | P2 | S | None | `DecisionRepository`/related code carries a comment pointing at ADR-012 so a future reader isn't left guessing | Not Started |

### Feature 1.4 — V1 documentation sync

**Story 1.4.1**: As a reader of `docs/`, the documentation should describe the app as it actually ships.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 1.4.1.1 Remove Conversation Translator references across `docs/` | P2 | M | None | Zero remaining references to it as a live feature | Not Started |
| 1.4.1.2 Correct Whisper default model references (`base` → `small`) | P2 | S | None | Zero remaining stale references | Not Started |

---

## EPIC 2 — Document Ingestion Module

*Corresponds to Roadmap M1.1.*

### Feature 2.1 — Document import pipeline

**Story 2.1.1**: As a user, I want to import a PDF/DOCX/TXT/Markdown file the same way I already import audio.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 2.1.1.1 License-audit candidate PDF/DOCX parsing libraries (ADR-016) | P0 | S | None | A permissively-licensed library is selected and the audit result is recorded | Not Started |
| 2.1.1.2 `Document` model + repository + migration v5 | P0 | M | None | Mirrors `MeetingRepository`'s shape; CRUD + status transitions covered by tests | Not Started |
| 2.1.1.3 `summaries.document_id` nullable FK + CHECK constraint (ADR-005) | P0 | S | 2.1.1.2 | Existing meeting-summary behavior unaffected; constraint verified with a negative test (both/neither FK set is rejected) | Not Started |
| 2.1.1.4 `DocumentImportController` (mirrors `ImportController`) | P0 | M | 2.1.1.2 | File picker extended to accept pdf/docx/txt/md; sealed-state UI pattern matches existing `ImportUiState` | Not Started |
| 2.1.1.5 `DocumentTextExtractionService` — PDF implementation | P0 | L | 2.1.1.1 | Correct extraction on a corpus of real-world PDFs; empty-text-layer PDFs produce the ADR-015 error, not garbage | Not Started |
| 2.1.1.6 `DocumentTextExtractionService` — DOCX implementation | P0 | M | 2.1.1.1 | Correct extraction on a corpus of real-world DOCX files | Not Started |
| 2.1.1.7 `DocumentTextExtractionService` — TXT/Markdown implementation | P1 | S | None | Correct extraction incl. non-UTF8 encoding fallback handling | Not Started |
| 2.1.1.8 Document detail screen (extracted text tab) | P1 | M | 2.1.1.4–2.1.1.7 | Mirrors `MeetingDetailsScreen`'s tab pattern | Not Started |

### Feature 2.2 — Document summarization

**Story 2.2.1**: As a user, I want an AI summary for an imported document, the same way I get one for a meeting.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 2.2.1.1 `SummarizeDocumentUseCase` (reuses existing LLM engine + queue) | P0 | M | Feature 2.1, Epic 1 Feature 1.2 | Summary generated and persisted via the shared `summaries` table | Not Started |
| 2.2.1.2 Summary tab on document detail screen | P1 | S | 2.2.1.1 | Reuses `AiPipelineFallback` for loading/error states | Not Started |
| 2.2.1.3 Retry path for failed document summarization | P1 | S | 2.2.1.1 | Mirrors `RetryMeetingProcessingUseCase`'s resume-from-failure behavior | Not Started |

---

## EPIC 3 — Knowledge Retrieval Infrastructure

*Corresponds to Roadmap M1.0 (spike) and M1.2.*

### Feature 3.1 — Embedding & vector-storage feasibility spike

**Story 3.1.1**: As the team, we need evidence — not assumption — that on-device embeddings and vector search are viable before committing further engineering time.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 3.1.1.1 Spike: `llama.cpp`/`llamadart` embedding-mode feasibility (ADR-003 option 1) | P0 | XL | None | See subtasks below | Not Started |
| 3.1.1.2 Spike: fallback embedding runtime, only if 3.1.1.1 fails | P0 | XL | 3.1.1.1 (conditional) | A working alternative embedding path is demonstrated end-to-end | Not Started |
| 3.1.1.3 Spike: `sqlite-vec` integration feasibility (ADR-004 option 1) | P0 | L | None | Can run in parallel with 3.1.1.1 | Not Started |
| 3.1.1.4 Spike: brute-force Dart cosine similarity, only if 3.1.1.3 fails | P0 | M | 3.1.1.3 (conditional) | Benchmarked against a realistic chunk count (NFR-16 scale) | Not Started |
| 3.1.1.5 Validate ADR-011's chunk-size/K numbers against real token counts | P0 | M | 3.1.1.1 or 3.1.1.2 | Written conclusion: numbers confirmed or corrected, with evidence | Not Started |
| 3.1.1.6 Write the spike report and update ADR-003/004/011 if conclusions differ from the pending default | P0 | S | 3.1.1.1–3.1.1.5 | Report exists at `docs/v2/implementation/spikes/m1-0-embedding-spike.md`; ADRs amended if needed | Not Started |

**Subtasks of 3.1.1.1** (representative full depth):
- Determine whether `llamadart`'s exposed API surface supports embedding-mode inference for a compatible GGUF embedding model, by direct experimentation against the package (not documentation alone, since V1's own experience shows package docs and actual behavior can diverge).
- If supported: load a small candidate embedding model and confirm it produces stable, sane vectors for known-similar and known-dissimilar text pairs.
- If not supported: confirm definitively (not just "couldn't find it") before falling back to 3.1.1.2.
- Measure on-device embedding generation latency per chunk on at least one real (not emulator) device.

### Feature 3.2 — Chunking, embedding, and storage pipeline

**Story 3.2.1**: As the system, every ready meeting/document is automatically chunked and embedded in the background.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 3.2.1.1 `knowledge_chunks` table + migration v6 | P0 | S | Feature 3.1 (spike conclusions) | Two-nullable-FK + CHECK pattern per ADR-005 | Not Started |
| 3.2.1.2 `ChunkingService` implementation | P0 | M | 3.1.1.5 | Paragraph/sentence-boundary-aware splitting at validated chunk size, with overlap | Not Started |
| 3.2.1.3 `EmbeddingEngine` concrete implementation | P0 | L | Feature 3.1 conclusion | Produces stored vectors matching the validated approach | Not Started |
| 3.2.1.4 `VectorStore` concrete implementation | P0 | L | Feature 3.1 conclusion | Similarity search returns correct top-K on a hand-verified test corpus | Not Started |
| 3.2.1.5 Background indexing step wired into `Document.status` (`indexing` stage) | P0 | M | 3.2.1.1–3.2.1.4 | New documents reach `indexing` then `ready` automatically | Not Started |
| 3.2.1.6 Retroactive indexing for existing `ready` meetings | P1 | M | 3.2.1.1–3.2.1.4 | A one-time backfill task indexes pre-existing meetings without user action | Not Started |

---

## EPIC 4 — Offline AI Chat Module

*Corresponds to Roadmap M1.3, M1.4, M2.1.*

### Feature 4.1 — Workspace-scoped chat (generalized Ask AI)

**Story 4.1.1**: As a user, I want to ask a question and get an answer drawn from across my meetings and documents, with sources cited.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 4.1.1.1 `chat_sessions`/`chat_messages` tables + migration v8 | P0 | S | Epic 3 | Schema per `docs/v2/12-database-design.md` | Not Started |
| 4.1.1.2 New chat prompt contract (versioned, per existing `promptVersion` convention) | P0 | M | None | Free-text response format, source-reference instruction included | Not Started |
| 4.1.1.3 `WorkspaceChatUseCase` | P0 | L | Epic 3 Feature 3.2, 4.1.1.1, 4.1.1.2 | Retrieval-backed context assembly within ADR-011's validated token budget | Not Started |
| 4.1.1.4 Source citation parsing and display | P1 | M | 4.1.1.3 | Answer UI shows which meeting(s)/document(s) were used, each opening its detail screen | Not Started |
| 4.1.1.5 Port existing Ask AI test suite to the new implementation | P0 | M | 4.1.1.3 | All existing meaningful test cases pass against the new code path | Not Started |
| 4.1.1.6 Retire `AskAboutMeetingsUseCase` (ADR-010) | P1 | S | 4.1.1.5 passing in production build | Old code path removed; no functional regression observed | Not Started |

### Feature 4.2 — Document-scoped and general chat

**Story 4.2.1**: As a user, I want to chat with one document specifically, and separately, have a general offline conversation.

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 4.2.1.1 Chat scope selector UI (ADR-013 — one screen, not three routes) | P0 | M | Feature 4.1 | Scope defaults to "All"; can be narrowed to one document or meeting | Not Started |
| 4.2.1.2 Document-scoped filtering in `WorkspaceChatUseCase` | P0 | S | 4.2.1.1 | A document-scoped answer never draws on unrelated content | Not Started |
| 4.2.1.3 `GeneralChatUseCase` (no retrieval context) | P1 | S | Feature 4.1 infra | Works with zero relevant content in the corpus | Not Started |
| 4.2.1.4 Chat history list/reopen/delete UI | P1 | M | 4.1.1.1 | A past conversation reopens with full message history; delete is immediate and complete | Not Started |

---

## EPIC 5 — Workspace Search

*Corresponds to Roadmap M2.2.*

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 5.1 Migration v7 — extend FTS5 to `documents` | P0 | S | Epic 2 | Document title/text becomes searchable | Not Started |
| 5.2 Unified search results UI (content-type tagged) | P0 | M | 5.1 | One query returns meetings/documents/notes together, correctly labeled | Not Started |
| 5.3 Result-to-detail-screen routing per content type | P0 | S | 5.2 | Tapping any result type opens the correct detail screen | Not Started |

---

## EPIC 6 — Navigation & UX Integration

*Corresponds to Roadmap M2.3.*

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 6.1 Home screen entry points for Documents/Chat | P0 | M | Epics 2, 4 | Discoverable without instruction, per ADR-014 | Not Started |
| 6.2 Secondary nav surface for Documents/Chat (exact treatment per ADR-014) | P0 | M | 6.1 | Primary bottom-nav item count unchanged (still 4) | Not Started |
| 6.3 Deferrable embedding-model download UX (ADR-017) | P0 | M | Epic 3 spike conclusion | Onboarding gate unchanged; embedding model prompted at first document/chat use if needed | Not Started |
| 6.4 Chunked/map-reduce summarization for long meetings/documents | P1 | L | Epics 2, 3 | Long-content test fixture produces a summary reflecting the whole source | Not Started |

---

## EPIC 7 — Quality, Performance & Accessibility

*Corresponds to Roadmap M3.1, M3.2.*

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 7.1 Real-device battery/thermal/latency benchmarking pass | P0 | L | Phases 1–2 feature-complete | Documented results, bounds defined in `08-quality-gates.md`, met on ≥1 low-end + ≥1 mid-range device | Not Started |
| 7.2 Accessibility audit and fixes (TalkBack, font scaling, contrast) | P0 | L | Phases 1–2 feature-complete | Every new screen passes the bar in `08-quality-gates.md` | Not Started |
| 7.3 V2 testing strategy document (mirrors V1's `05-testing-strategy.md`) | P1 | M | None — can start anytime | Written, covers fake-engine patterns extended to embeddings/retrieval | Not Started |
| 7.4 Legal docs revision pass for V2 data categories | P1 | M | Epics 2, 4 (data categories exist) | `docs/legal/` reflects documents/chat as real, disclosed data types | Not Started |

---

## EPIC 8 — Monetization & Play Store Launch

*Corresponds to Roadmap M3.3–M3.5.*

| Task | Priority | Difficulty | Dependencies | Acceptance Criteria | Status |
|---|---|---|---|---|---|
| 8.1 Configurable LLM tier (Settings, mirrors Whisper-size precedent) | P2 | L | Phases 1–2 | Larger-tier model selectable; ADR-011 numbers re-validated at new tier | Not Started |
| 8.2 Play Billing integration (Option B, ADR-007) | P1 | L | Business pricing decision finalized | Free/Pro gating verified fully on-device, no backend introduced | Not Started |
| 8.3 Release keystore generation + signing verification | P0 | S | None — can happen anytime | Real keystore exists, held securely, release build signs successfully | Not Started |
| 8.4 AAB build pipeline | P0 | S | None | `flutter build appbundle --release` produces a valid, signed bundle | Not Started |
| 8.5 Hosted privacy policy | P0 | S | None | Live, public URL serving current policy text | Not Started |
| 8.6 Store listing assets + Data Safety form | P0 | M | Epics 2, 4 (accurate data categories) | Form accurately reflects on-device-only processing | Not Started |
| 8.7 Support contact established | P0 | S | None | Monitored contact channel exists and is referenced in the privacy policy | Not Started |
