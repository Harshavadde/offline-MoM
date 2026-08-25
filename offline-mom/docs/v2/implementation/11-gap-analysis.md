# V2 Gap Analysis — Documentation vs. Shipped Codebase

This document compares `docs/v2/` and `docs/v2/implementation/` (the frozen specification) against the actual state of `lib/` as it exists today — read in full for this pass: every repository, use case, provider, model, database migration, service, screen, route, and the theme/DI layer. Nothing below is inferred from the spec; every claim about "what exists" is grounded in a specific file. Nothing in this document changes anything — it is a comparison, not a proposal.

## Scope note on codebase currency

Since `docs/v2` was written (frozen), the shipped app has continued to receive small, V1-scoped fixes unrelated to V2 (a multi-model Whisper download picker, legal-document rewrites, a release-signing scaffold). None of these touch the modules V2 cares about — they're noted here only so this analysis isn't mistaken for stale.

**Point-in-time snapshot, not continuously updated.** This document reflects the codebase as of its original writing (pre-Phase-1A). Phase 1A (documents, search) and Phase 1B (embeddings/retrieval infrastructure) have since closed many of the "missing" items below — §5-§9 in particular are now substantially out of date; the items each phase resolved are called out inline rather than rewriting the whole document retroactively, since a gap analysis's value is in what it found *at the time*, and [10-v2-progress.md](10-v2-progress.md) is the live, continuously-updated source for current status. Read §5-§9 with that in mind: an item marked "missing" there may already exist — check [10-v2-progress.md](10-v2-progress.md) first.

---

## Feature-by-feature classification

Every capability in `docs/v2/08-functional-requirements.md`, classified against what actually exists in `lib/` today.

| Requirement | Classification | Grounding |
|---|---|---|
| FR-22 Document import | **Needs New Module** | No `Document`-anything exists anywhere in `lib/`. `ImportController` (`lib/features/import/presentation/providers/import_providers.dart`) is the closest analog and is a copy-source, not reusable code. |
| FR-23 Document status state machine | **Needs New Module**, pattern **Already Exists** | `MeetingStatus` (`lib/models/meeting.dart`) is the exact pattern to mirror; no code sharing is possible since it's a different enum, but the *shape* (sealed progression + `error`) is proven and copy-worthy. |
| FR-24 Keep original file alongside extracted text | **Needs Extension** | `audio_paths.dart` (`lib/core/utils/`) already establishes the app-private-storage convention; a `document_paths.dart` sibling is additive, not new architecture. |
| FR-25 Extraction failure → clear error, retryable | **Needs New Use Case**, pattern **Already Exists** | `RetryMeetingProcessingUseCase` (`lib/features/meetings/retry_meeting_processing_use_case.dart`) is the exact pattern; `Meeting.errorMessage` (added in migration v2) is the precedent for `Document.errorMessage`. |
| FR-26 Delete document + cascade | **Needs New Use Case**, DB behavior **Already Exists** | `DeleteMeetingUseCase` is the pattern; `ON DELETE CASCADE` is already the schema convention (`lib/database/migrations/v1.dart` onward) and needs no new mechanism, only new FK declarations. |
| FR-27 Document summary | **Needs Refactoring** (of `summaries` table/`SummaryRepository`) + **Needs Extension** (of `GenerateMeetingSummaryUseCase`'s pattern) | `lib/repositories/summary_repository.dart` currently hard-requires `meeting_id`; ADR-005's nullable-FK change is a real, if small, modification to existing, shipped code, not purely additive. |
| FR-28 Document-scoped chat | **Needs New Module** | No chat capability of any kind exists beyond meeting-only Ask AI. |
| FR-29 Workspace-scoped chat | **Needs New Module**, built on **Needs Refactoring** of `AskAboutMeetingsUseCase` | `lib/features/ask/ask_about_meetings_use_case.dart` exists today and is genuinely reusable as a *behavioral reference* (its fallback-string discipline, its "answer only from provided context" prompt posture) — its actual keyword-overlap scoring logic is not reusable and is replaced per ADR-010. |
| FR-30 Source citations | **Needs New UI** + prompt-contract extension | No citation concept exists in `LlamaDartLlmEngine` today; `_systemPrompt` (`lib/services/ai/llamadart_llm_engine.dart`) only covers the summarization contract. |
| FR-31 General chat | **Needs New Module** | No unscoped chat surface exists. |
| FR-32 Chat persistence | **Needs New Database Table** (×2) + **Needs New Repository** (×2) | Nothing analogous exists; the closest precedent (Conversation Translator's deliberate *non*-persistence) was removed from the codebase entirely and is not a starting point. |
| FR-33 Delete chat conversation | **Needs New Use Case**, pattern **Already Exists** | Same cascade-delete pattern as every other entity. |
| FR-34 Honest "couldn't find anything" fallback | **Already Exists** (to port forward) | `AskAboutMeetingsUseCase` lines implementing this exact fallback (per the earlier codebase audit) should be carried into `WorkspaceChatUseCase` essentially unchanged. |
| FR-35 Chat generation timeout | **Already Exists**, zero new code required | `LlmTimeoutException`/`cancelGeneration()` (`lib/services/ai/llamadart_llm_engine.dart`) apply to any `generate()`-family call automatically — the new chat use cases inherit this for free by routing through the same engine. |
| FR-36 Search covers summaries + notes | **Needs Extension** + **Needs Migration** | `lib/features/search/search_meetings_use_case.dart` today only queries `meetings`/`transcripts`/`action_items`/`decisions` — confirmed by direct reading, `SummaryRepository` and `NotesTable` have no `findMeetingIdsBy*` method today. |
| FR-37 Search covers documents | **Needs New Repository method** (once `documents` exists) | N/A until Epic 2 lands. |
| FR-38 Unified, tagged search results | **Needs New UI** | `search_screen.dart` today renders one content type only. |
| FR-39 FTS5 instead of `LIKE` | **Needs Refactoring** + **Needs Migration** | Confirmed: zero `CREATE VIRTUAL TABLE ... fts5` anywhere in `lib/database/migrations/`; every existing text search is `WHERE column LIKE ?`. |
| FR-40 Automatic background chunking/embedding | **Needs New Infrastructure** entirely | No chunking, embedding, or vector-storage code of any kind exists in the codebase today — this is the one area with genuinely zero existing precedent to build from. |
| FR-41 No new network edges | **Already Exists** as an architectural property | `AndroidManifest.xml`'s `INTERNET` permission is used today only by the two existing model-download paths; this is a constraint to preserve (verify per new dependency), not a feature to build. |
| LLM request queue (NFR-11) | **Needs New Infrastructure** wrapping **Needs Refactoring** of 2 call sites | `generateMeetingSummaryUseCaseProvider` and `askAboutMeetingsUseCaseProvider` (`lib/providers/app_providers.dart`) currently call `LlmEngine` directly — both need their construction updated to route through the new queue. |

---

## 1. Existing reusable modules

These are load-bearing, proven, and directly reusable as either literal shared code or as an established pattern to mirror:

- **The single composition root** (`lib/providers/app_providers.dart`) — every new repository/service/use-case provider for V2 slots into this exact file, using the exact `Provider<Interface>((ref) => ConcreteImpl(...))` shape already used for all 8 existing repositories.
- **The repository pattern itself** — every `Sqflite*Repository` (`meeting_repository.dart`, `transcript_repository.dart`, `summary_repository.dart`, `action_item_repository.dart`, `decision_repository.dart`, `recording_mark_repository.dart`, `note_repository.dart`) shares one construction shape: takes a `Database`, uses `db.query`/`insert`/`update`/`delete`/`batch()`, never raw SQL for CRUD. New repositories (`DocumentRepository`, `KnowledgeChunkRepository`, `ChatSessionRepository`, `ChatMessageRepository`) should be indistinguishable in style from these.
- **The status-state-machine + `errorMessage` + `AiPipelineFallback` triad** — `Meeting.status`/`Meeting.errorMessage` (`lib/models/meeting.dart`) plus the shared `AiPipelineFallback` widget (`lib/shared/widgets/ai_pipeline_fallback.dart`) together are the proven pattern for "a background AI pipeline with honest loading/downloading/error states, including the stuck-in-progress retry affordance." `Document.status` should copy this exactly.
- **The shared AI engine layer's reliability machinery** — `LlmTimeoutException`, `cancelGeneration()`, `LlmModelDownloadTimeoutException`, `ProgressThrottle` (`lib/services/ai/`) apply to any new LLM/embedding call site automatically, with zero modification needed to the mechanism itself.
- **The migration convention** — `AppDatabase.open()` (`lib/database/app_database.dart`) applying every migration in sequence on `onCreate` and only missing ones on `onUpgrade` is a template, not something V2 needs to redesign — v4 onward slot in exactly like v2/v3 did.
- **Shared UI widgets** — `TintedIcon`, `EmptyState`, `AppShell` (`lib/shared/widgets/`) and `AppTheme`'s seed-color-driven theming (`lib/core/theme/app_theme.dart`) are reused as-is by every new screen with zero internal changes required.
- **`RoutePaths` + `go_router`** — the centralized-string-constants-plus-`GoRoute`-table convention (`lib/core/router/`) is additive: new routes are new constants and new `GoRoute` entries, not a routing redesign.
- **The fake-engine testing pattern** — `test/test_helpers/fake_ai_engines.dart`'s `FakeSpeechToTextEngine`/`FakeLlmEngine` establish exactly the pattern the V2 testing strategy (Epic 7, Task 7.3) extends to `FakeEmbeddingEngine` (done, Phase 1B — deterministic, text-sensitive vectors rather than a real model, for meaningful similarity-search assertions). A `FakeVectorStore` was not needed - `BruteForceVectorStore` is fast and deterministic enough to use directly (real SQLite via `sqflite_common_ffi`) in every retrieval/indexing test written this milestone.
- **Onboarding's multi-select model-download screen** (`lib/features/onboarding/presentation/screens/model_setup_screen.dart`, just shipped) — the concurrent-download-with-per-model-progress UI pattern is the direct template for offering an optional embedding-model download later (ADR-017).
- **Backup and Storage screens' usage-calculation pattern** (`lib/features/settings/presentation/screens/backup_screen.dart`, `storage_screen.dart`) — both are additive to extend (include a `documents/` directory) rather than needing new mechanisms.

## 2. Existing code that should NEVER change

Per `docs/v2`'s freeze and NFR-22:

- The seven existing tables' existing columns (`meetings`, `transcripts`, `summaries` — except its one additive nullable column per ADR-005 — `action_items`, `decisions`, `recording_marks`, `notes`).
- The recording pipeline: `RecorderService`/`RecordPackageRecorderService`, `RecordingController`, `record_screen.dart`/`recording_screen.dart`.
- The meeting transcription/summarization pipeline's core logic: `TranscribeMeetingUseCase`, the meeting-specific parts of `GenerateMeetingSummaryUseCase`, `ProcessNewMeetingUseCase`.
- `WhisperSpeechToTextEngine`'s download/timeout/transcription logic and `LlamaDartLlmEngine`'s core generation/timeout/cancellation logic (only their *call sites* change, per the queue work — their internals do not).
- App lock (`AppLockController`, `LocalAuthAppLockService`, `lock_screen.dart`) and Backup/Export mechanisms.
- The primary `AppShell` bottom-nav **item count** (four) — per ADR-014, Documents/Chat get new entry points elsewhere, not a fifth/sixth tab.
- Settings screens not touched by V2 scope (`recording_preferences_screen.dart`, `appearance_screen.dart`, `language_screen.dart`, `help_screen.dart`, `privacy_screen.dart`, `terms_screen.dart`).

## 3. Existing code that should be extended, not rewritten

- **`summaries` table / `SummaryRepository`** (`lib/repositories/summary_repository.dart`) — add nullable `document_id`, make `meeting_id` nullable, add the CHECK constraint (ADR-005) and a `getForDocument()` method mirroring the existing `getForMeeting()`. The existing meeting-summary code paths are untouched by this change.
- **`AskAboutMeetingsUseCase`** — kept running exactly as-is until `WorkspaceChatUseCase` is validated (ADR-010's no-regression-window rule); its fallback-string and context-discipline behavior is the reference implementation for the replacement, even though its scoring mechanism is not reused.
- **`SearchMeetingsUseCase`** — its four-repository-fan-out-and-union *use case shape* (one query in, one unioned result set out) is worth keeping as the public contract even though its internals move from `LIKE` fan-out to a single FTS5 query. **As of Phase 2B, resolved:** renamed to `SearchWorkspaceUseCase` (ADR-028) - the shape this bullet flagged as worth keeping is exactly what carried over unchanged; only the name and the addition of per-content-type result maps changed.
- **`MeetingListTile`/`DocumentListTile`** — near-duplicate widgets (the latter's own doc comment said so outright). **As of Phase 2B, resolved:** both now wrap a single shared `KnowledgeSourceCard` (ADR-028), taking generic/primitive parameters rather than `Meeting`/`Document` directly, same "plain booleans, not the entity's own enum" precedent `AiPipelineFallback` already established.
- **`speechToTextEngineProvider`/`llmEngineProvider`** (`lib/providers/app_providers.dart`) — unchanged themselves; a new `LlmRequestQueue` layer wraps around their consumers, not their construction.
- **File-picker-based import** (`FilePickerAudioImportService`, `lib/services/audio/`) — its allow-list mechanism is the template for accepting PDF/DOCX/TXT/MD, whether as an extension of this exact service or a sibling built the same way.
- **Storage screen and Backup screen** — both need their usage/bundle calculations extended to include a new `documents/` directory; neither needs a UI redesign.
- **AI Models settings screen** (`ai_models_screen.dart`) — gains an embedding-model row once ADR-003 resolves, using the exact same `RadioListTile`/download-status pattern already there for Whisper.

## 4. Existing code that should be deprecated

This is a short list by design — V2 is additive, not a rewrite:

- **`AskAboutMeetingsUseCase`'s keyword-overlap scoring implementation** — deprecated in favor of `WorkspaceChatUseCase`, removed only after the replacement is validated working (ADR-010). Not deprecated yet as of this analysis; flagged here so it's tracked from day one.
- **Nothing else in `lib/` is a deprecation candidate as a result of V2.** The `decisions` table/`DecisionRepository` remain intentionally-kept dead weight per ADR-012 (a V1-era decision reaffirmed, not newly deprecated by V2).

## 5. Missing infrastructure

**As of Phase 1B, resolved:** `LlmRequestQueue` (Phase 0), `DocumentTextExtractionService` + PDF/DOCX/TXT/Markdown implementations (Phase 1A), FTS5 virtual tables + sync triggers (Phase 0/1A), `ChunkingService`/`DefaultChunkingService`, `EmbeddingEngine`/`LlamaDartEmbeddingEngine`, `VectorStore`/`BruteForceVectorStore`, `IndexingService`/`DefaultIndexingService`, `RetrievalEngine`/`DefaultRetrievalEngine` (all Phase 1B — see [03-decisions.md](03-decisions.md) ADR-003/004 resolutions and [spikes/m1-0-embedding-spike.md](spikes/m1-0-embedding-spike.md)).

**As of Phase 1C, resolved:** A meeting-side indexing orchestrator (`MeetingIndexer`, mirroring `DocumentIndexer`) and `MeetingStatus.indexing` — previously deferred by ADR-020, now shipped per ADR-021/ADR-022 (`content_type`/`source_id` schema + `MeetingIndexer`, migration v8). `KnowledgeChunkFilter`-scoped retrieval (workspace/meeting-only/document-only/content-type filtering) — ADR-023.

**As of Phase 2A, resolved:** A chat prompt contract (`LlamaDartLlmEngine._chatSystemPrompt`/`chatPromptVersion`) and progressive streaming (`LlmEngine.answerQuestionStream`) — ADR-026. `WorkspaceChatUseCase` implemented for real (workspace/meeting/document scopes, retrieval-backed, never bypassing `RetrievalEngine`).

**As of Phase 2B, resolved:** Content-type-aware search results (`ContentSearchRepository`/`ContentSearchResults` now expose which content type(s) matched per meeting/document, additive - no new migration, the data already existed in `content_fts.content_type`) - closes the last piece of FR-38/M2.2 that Phase 1A's early FTS5-for-documents work didn't cover.

**As of Phase 3A, resolved:** A centralized model lifecycle manager (`ModelLifecycleManager`, `lib/services/ai/model_lifecycle_manager.dart`, ADR-029) - not called out as missing by any earlier pass of this analysis since `docs/v2` never explicitly named it, but a real gap all the same: every model-backed engine loaded once and stayed native-resident for the app's entire lifetime, with no unload path, no duplicate-load guard, and no shared status reporting. Also resolved: `BruteForceVectorStore`'s full-corpus re-fetch on every `similaritySearch` call (now cached, invalidated on every mutation path) and its full-sort-then-take-k candidate scoring (now a bounded top-k selection) - neither changes the retrieval algorithm itself (ADR-004 stays the standing decision).

**As of Phase 3B, resolved:** A whole-application production-performance review (ADR-030) — not a missing *module* in the sense the rest of this section tracks, since nothing here was ever named as a required-but-absent piece of `docs/v2`'s functional scope, but a real gap against `08-non-functional-requirements.md`'s NFR-13/14/15/16 all the same: `ChatScreen` rebuilt its entire widget tree (AppBar, scope selector, input bar) on every streamed token instead of only the region actually changing; `ChatHistoryScreen` built every pinned/recent session eagerly regardless of scroll position; `DocumentRepository.getAll()` fetched every document's full `extracted_text` column on every list load even though no list-view caller ever reads it; six dialog-local `TextEditingController`s were never disposed. All four fixed and covered by new tests (see [10-v2-progress.md](10-v2-progress.md)'s Phase 3B section for the full list). Startup, existing lazy lists (`HistoryScreen`/`DocumentsScreen`), and `AppLogger`'s debug-gating were reviewed against the same NFRs and found already adequate — no change made. As with Phase 3A, real-device battery/thermal/frame-timing validation (NFR-13's own enforcement point, `08-quality-gates.md` §5-7) remains explicitly deferred to M3.1, not fabricated here.

**As of Phase 4A, resolved:** A production UX/accessibility pass (ADR-031) — the gap this analysis's own scope note has flagged since before Phase 1A (`docs/v2` never addressed accessibility at all; M3.2 exists specifically to close it). A full-codebase inventory found: zero `Semantics`/`semanticLabel`/`Tooltip` usage anywhere in `lib/` before this pass; three `IconButton`s and five custom icon-only tappables with no accessible name at all; a confirmed WCAG AA contrast failure (1.58:1/1.70:1, need 4.5:1) in `AppTheme.heroGradient`'s original stops; five duplicated delete-confirmation dialogs with no destructive-color styling; one delete path (notes) with no confirmation dialog at all; two snackbars leaking raw exception text. All fixed and covered by new tests (see [10-v2-progress.md](10-v2-progress.md)'s Phase 4A section for the full list). This closes the *code-level* half of M3.2's gap; the real-device TalkBack-navigation-order half remains open, unaffected by this pass (no physical Android device available in this implementation environment).

**As of Phase 4B, resolved:** A production-readiness audit (ADR-032) covering release-mode code cleanliness, resource/provider lifecycle correctness, navigation/deletion recovery paths, storage cleanup, and Android release configuration — closing several real, previously-undiscovered gaps: unbounded per-id provider memory growth (eight `FutureProvider.family` providers gained `.autoDispose`), a stale-retrieval-cache-after-delete gap (`DeleteMeetingUseCase`/`DeleteDocumentUseCase` now call `VectorStore.invalidateCache()`), a leaked backup-export temp file, two release-mode-silent `assert`s converted to always-enforced exceptions, and three duplicated format helpers consolidated. **Also, and more significantly: this is the first phase with a real Android SDK toolchain in its implementation environment, and the first to actually attempt `flutter build apk --release` rather than disclaiming it as unmeasurable** — the build does not compile, for a confirmed, root-caused toolchain reason (R-26, docs/v2/implementation/04-risk-register.md) unrelated to application code. This is a genuinely new category of finding this gap analysis has never been able to surface before, since every earlier phase's own "no device/toolchain available" limitation applied equally to this document's own research.

**As of Phase 5A, a new module shipped that `docs/v2` never named at all** (unlike every prior phase's entries above, which closed a gap against the frozen spec's own stated scope): the Student Toolkit's Image Tools (`ImageCompressionService`/`ImageResizeService`, `lib/services/toolkit/`; `ToolkitFile`/`ToolkitFileRepository`; migration v11; `ImageCompressController`/`ImageResizeController`; `ImageCompressScreen`/`ImageResizeScreen`/`ToolkitRecentFilesScreen`/`StudentToolkitScreen`) — see ADR-033 (03-decisions.md). Originally pitched as a four-section module (Scanner, Image Tools, PDF Tools, Recent Files); scoped to Image Tools only via an explicit product-owner decision, not a unilateral cut. Reused, unmodified: the Clean Architecture/repository/provider pattern (new instances, no new architectural concept), `KnowledgeSourceCard` (for Recent Files rows), the `compute()`-isolated-processing + sealed-UI-state controller shape `DocumentImportUiState` already established. Genuinely new: the target-size JPEG compression algorithm itself (binary search + analytically-computed downscale retries) — the one piece of this phase with no prior-art pattern to mirror, the same category of "no precedent to build from" this document's §14 already flags for embedding/retrieval. A real `TextEditingController`-dispose-race bug was found and fixed in this phase's own new screen, and flagged (R-30, 04-risk-register.md) as likely also present in six pre-existing dialogs this phase did not touch.

**As of Phase 5B, the Student Toolkit's remaining two sections shipped** (Scanner, PDF Tools - `docs/v2` never named either, same as Phase 5A's own Image Tools): `PdfPageRenderingService`/`ScannerPdfService`/`PdfCompressionService`/`PdfMergeService`/`PdfSplitService`/`PdfOrganizeService` (`lib/services/toolkit/`), `scan_image_processing_service.dart`'s pure-Dart perspective-correction algorithm, `ScannerController` + four PDF Tools controllers, six new screens, migration v12 - see ADR-034 (03-decisions.md). The one open technical question Phase 5A's own scope-negotiation left unresolved ("no license-safe native PDF manipulation library exists") was resolved before writing any code: `pdf`/`printing`, already dependencies, cover the entire PDF-manipulation surface via rasterize-and-rebuild, after explicitly researching and rejecting an AGPL-3.0-licensed alternative. Reused, unmodified: `ToolkitFileRepository`/`toolkitFileListProvider` (extended with one new `duplicate()` action available to every toolkit output, not just this phase's), `KnowledgeSourceCard`, the Clean Architecture/provider pattern. Genuinely new, with no prior-art pattern in this codebase to mirror: the 4-point perspective-correction projective transform (classic, well-understood graphics math, not novel/experimental) and the native-platform-channel rasterization boundary itself (`Printing.raster()` cannot run in `compute()` and has no `flutter test` implementation, requiring a first-of-its-kind `FakePdfPageRenderingService` test double for this codebase). `StudentToolkitScreen` crossed from two tool sections to three, the point at which the Phase 5A architecture review had predicted a shared `_ToolSection` widget would become justified - extracted at exactly that point, not before.

**As of Phase 6A, the AI Model Manager shipped** (`docs/v2` never named this at all either - it entered the plan only via ADR-035's Phase 5B-freeze approval): `ModelCatalog`/`ProfessionRecommendations` (`lib/services/ai/`), `ModelDownloadService` (`HttpModelDownloadService`/`FakeModelDownloadService`), `InstalledModel`/`InstalledModelRepository`, migration v13, a new `ai_models/` feature (4 screens, 4 provider files) replacing the old `ai_models_screen.dart` - see ADR-036 (03-decisions.md). Reused, unmodified: the Clean Architecture/repository/provider pattern, the `_DownloadProgressRow`-style progress UI (`model_setup_screen.dart`'s existing convention), `showDestructiveConfirmDialog`, `formatFileSize`. Modified, minimally and additively (not rewritten): `LlamaDartLlmEngine`/`LlamaDartEmbeddingEngine` each gained a `modelSourceOverride` constructor parameter and an exposed `cancelActiveDownload()`/`isDownloading` pair (both required to let the Model Manager point either engine at a different catalog entry and request cancellation of an in-flight download - existing generation/summarization behavior is untouched); `WhisperSpeechToTextEngine` had its inline model-directory expression extracted into a shared `whisperModelDirectory()` helper (`core/utils/ai_model_paths.dart`) so the new controller resolves the identical path, a pure extraction with no behavior change; `app_providers.dart`/`AppSettings`/`tables.dart`/`app_database.dart`/`app_constants.dart` gained new providers/fields/migration wiring, the same kind of additive change every prior phase's own migration has made. Genuinely new: a resumable HTTP-Range download primitive (`ModelDownloadService`) built specifically because `whisper_flutter_new`'s own downloader (already known to be timeout-less, per the class doc comment predating this phase) also turned out to have no resume/checksum support at all - the one piece of this phase with a real prior-art gap, mirroring `Printing.raster()`'s "no `flutter test` implementation" pattern (the real network I/O is likewise untestable here; the resume/validator *decision logic* is unit-tested in isolation instead). This phase also deliberately did **not** pad the model catalog with unverified additional LLM/embedding tiers to make "Available Models" look richer than it honestly is - see ADR-036's "catalog is honest, not padded" decision, a direct continuation of this document's own no-fabrication standard.

**Still missing** (original list, items above removed):

- `GeneralChatUseCase`/`ChatScope.general` UI wiring — M2.1, deliberately not started (explicitly out of scope for Phase 2A and Phase 2B alike).

## 6. Missing repositories

**As of Phase 1B, resolved:** `DocumentRepository`/`SqfliteDocumentRepository` (Phase 1A), `KnowledgeChunkRepository`/`SqfliteKnowledgeChunkRepository` (Phase 1B, migration v7 not v6 — ADR-019).

**As of Phase 2A, resolved:** `ChatSessionRepository`/`SqfliteChatSessionRepository` and `ChatMessageRepository`/`SqfliteChatMessageRepository`, mirroring `NoteRepository`'s full-CRUD shape (migration v9, not v8 — ADR-025).

**Not missing, already modified**: `SummaryRepository` (see §3) — done in Phase 1A.

## 7. Missing providers

All to be added to `lib/providers/app_providers.dart`, matching existing naming/construction conventions exactly. **As of Phase 2B, resolved:** `searchWorkspaceUseCaseProvider` (replaces `searchMeetingsUseCaseProvider` outright, per ADR-028 - not kept alongside it, since the public contract moved with the rename). **As of Phase 2A, resolved:** every other item below except `generalChatUseCaseProvider` (still a throwing stub, `general` scope not wired to any UI - M2.1).

- `documentRepositoryProvider`, `knowledgeChunkRepositoryProvider`, `chatSessionRepositoryProvider`, `chatMessageRepositoryProvider`.
- `llmRequestQueueProvider`, `embeddingEngineProvider`, `vectorStoreProvider`.
- `documentTextExtractionServiceProvider` (or one per format, following whatever pattern `DocumentTextExtractionService`'s implementation lands on).
- `extractDocumentTextUseCaseProvider`, `summarizeDocumentUseCaseProvider`, `deleteDocumentUseCaseProvider`.
- `workspaceChatUseCaseProvider`, `generalChatUseCaseProvider` (document-scoped chat reuses the workspace one, filtered — per ADR-013/010, likely no separate provider needed).
- ~~`searchWorkspaceUseCaseProvider` (replaces `searchMeetingsUseCaseProvider`'s registration once FR-39 lands...)~~ — **shipped Phase 2B**, see above.
- New feature-level state controllers: `DocumentImportController`, `ChatController` (scope-aware per ADR-013), living in their respective feature folders' `presentation/providers/`, not the composition root — matching where `ImportController`/`RecordingController` live today, not where `SettingsController` lives (an intentional existing exception, not a pattern to copy for these).

## 8. Missing services

**As of Phase 1B, resolved:** `DocumentTextExtractionService` + PDF/DOCX/TXT/Markdown implementations (Phase 1A, license-audited per ADR-016). Concrete `EmbeddingEngine`/`VectorStore` implementations (Phase 1B — `LlamaDartEmbeddingEngine`, `BruteForceVectorStore`; see ADR-003/004 resolutions).

## 9. Missing models

**As of Phase 1B, resolved:** `Document` (Phase 1A). `KnowledgeChunk` (Phase 1B — implemented as a plain class as originally anticipated here, with BLOB embedding serialization via `KnowledgeChunk.encodeEmbedding`/`decodeEmbedding`).

**As of Phase 2A, resolved:** `ChatSession`, `ChatMessage` (freezed, migration v9) - plus a model not anticipated by this analysis, `ChatSourceRef` (plain class, mirrors `KnowledgeChunk`'s reasoning), for the citation chips ADR-026 derives from retrieved chunks rather than parsed model text.

**Not missing, already modified**: `Summary` (`lib/models/summary.dart`) — done in Phase 1A (nullable `documentId`, ADR-005).

## 10. Missing screens

- Document import entry flow (mirrors `import_screen.dart`).
- Document detail screen (mirrors `meeting_details_screen.dart`'s tabbed layout: Original text / Summary / Chat).
- **As of Phase 2A, resolved:** One chat screen with an in-chat scope selector (ADR-013) — not three screens. Chat history list (reopen/rename/delete past conversations).
- **As of Phase 2B, resolved:** `search_screen.dart` — rebuilt with grouped, content-type-tagged results and an All/Meetings/Documents/Notes filter (ADR-028). `home_screen.dart` — redesigned around four Knowledge Source pillar cards (Meetings/Documents/AI Workspace/Search), replacing the prior 6-tile grid (ADR-028); no longer just "needs extension," this is done for M2.3's scope.
- **Needs extension, not a new screen**: `storage_screen.dart` and `backup_screen.dart` (document-directory inclusion), `ai_models_screen.dart` (embedding-model row).

## 11. Missing navigation

New `RoutePaths` constants and corresponding `GoRoute` entries in `lib/core/router/app_router.dart` (both files confirmed to have zero Documents/Chat awareness today):

- `documents` (list/import entry), `documentDetailsPath(id)` (mirroring `meetingDetailsPath`'s builder-function convention).
- `chat` (single screen, scope passed as a route parameter or provider state per ADR-013, not separate routes per scope).
- The secondary nav surface ADR-014 calls for (exact widget/placement is an open UX task per [02-backlog.md](02-backlog.md) Task 6.2, not resolved by this analysis) is itself new — no analogous "secondary surface" exists in the app today (Settings' own sub-screens are reached by list-tile navigation from within Settings, which is a plausible but not yet confirmed precedent to reuse for this).

## 12. Missing database changes

**As actually shipped (superseding both `docs/v2/12-database-design.md`'s illustrative v4-v7 numbering and this table's original version below - see ADR-009, ADR-018, ADR-019 for why the numbering moved without the table *designs* changing):**

| Migration | Adds | Status |
|---|---|---|
| v4 | FTS5 tables + sync triggers, existing content only | ✅ Shipped (Phase 0) |
| v5 | `documents` table | ✅ Shipped (Phase 1A) |
| v6 | `summaries.document_id` (nullable) + `meeting_id` nullable + CHECK (ADR-005); `content_fts` rebuilt with `document_id` (ADR-018) | ✅ Shipped (Phase 1A) — not what ADR-009 originally illustrated for v6, see ADR-018 |
| v7 | `knowledge_chunks` table + indexes | ✅ Shipped (Phase 1B) — not v6 as ADR-009 originally illustrated, see ADR-019 |
| v8 | `knowledge_chunks.content_type`/`source_id` | ✅ Shipped (Phase 1C) — not `chat_sessions`/`chat_messages` as ADR-009 originally illustrated for v8, see ADR-021 |
| v9 | `chat_sessions` + `chat_messages` tables + indexes | ✅ Shipped (Phase 2A) — not v8 as ADR-009 originally illustrated, see ADR-025 |
| v10 | `chat_sessions.is_pinned` | ✅ Shipped (Phase 2B) — not part of `docs/v2/12-database-design.md`'s illustrative sequence at all (pin-conversation wasn't a Phase 1 concept), see ADR-028 |
| v11 | `toolkit_files` table (Student Toolkit Recent Files, no FKs, no FTS5 entry) | ✅ Shipped (Phase 5A) — not part of `docs/v2/12-database-design.md`'s illustrative sequence at all (the Student Toolkit isn't in `docs/v2`'s original functional scope), see ADR-033 |
| v12 | `toolkit_files.page_count` (Scanner + PDF Tools page counts) | ✅ Shipped (Phase 5B) — not part of `docs/v2/12-database-design.md`'s illustrative sequence at all, see ADR-034 |
| v13 | `installed_models` table (AI Model Manager, no FKs, no FTS5 entry) | ✅ Shipped (Phase 6A) — not part of `docs/v2/12-database-design.md`'s illustrative sequence at all (the AI Model Manager isn't in `docs/v2`'s original functional scope), see ADR-036 |

`AppConstants.sqliteDbVersion` is now `13`. Original table (pre-Phase-1A, kept for history):

| Migration | Adds | Confirmed absent today? |
|---|---|---|
| v4 | FTS5 tables + sync triggers, existing content only | Yes — zero FTS5 usage anywhere in `lib/database/` |
| v5 | `documents` table; `summaries.document_id` (nullable) + `meeting_id` nullable + CHECK | Yes |
| v6 | `knowledge_chunks` table + indexes | Yes |
| v7 | FTS5 extended to `documents` | Yes (depends on v4 + v5) |
| v8 | `chat_sessions` + `chat_messages` tables + indexes | Yes |

## 13. Migration strategy

1. **One migration file per version**, in `lib/database/migrations/`, following the existing `v1.dart`/`v2.dart`/`v3.dart` naming and internal shape (a single exported function, e.g. `migrateV3ToV4(Database db)`) — no departure from the established convention.
2. **`AppDatabase.open()`'s `onCreate` gets a new sequential call added for each new migration**, exactly as it already chains `createV1Schema` → `migrateV1ToV2` → `migrateV2ToV3` — so a fresh install always lands on the latest schema by replaying every step, never by a shortcut "create latest schema directly" path (preserves the existing guarantee that fresh-install and upgraded-install schemas are byte-for-byte identical).
3. **`onUpgrade` gets a matching new `if (oldVersion < N)` guard per migration**, so an app upgrading from any prior version — including a real V1 user upgrading directly to a V2 build — applies exactly the missing steps, never re-applies an already-done one.
4. **Testing requirement** (per [04-risk-register.md](04-risk-register.md) R-16): every new migration is tested against both a fresh install and an upgrade from *every* prior schema version it could realistically encounter in the field — not just the immediately preceding one, since a real user could be upgrading from a build several versions old.
5. **Pre-release backup-and-restore drill**: before any of v4–v8 ships to a real user, exercise the existing Backup feature (export → fresh install → restore) against a database that has actually been through the new migration, to catch any interaction between the new schema and the existing backup/restore code path before a real user does.
6. **No existing migration (v1–v3) is touched.** Every new migration is purely additive relative to the schema `AppConstants.sqliteDbVersion = 3` currently describes.

## 14. Estimated reuse percentage

A single number would be misleading — reuse varies enormously by layer:

| Layer | Reuse estimate | Basis |
|---|---|---|
| Architecture pattern (Clean Architecture, Riverpod, composition root, repository shape) | **~95%** | Every new module follows an existing, unmodified template; zero new architectural concepts introduced. |
| Existing meeting/recording/settings/backup/app-lock functionality | **100%** | Confirmed untouched by every ADR in [03-decisions.md](03-decisions.md) except the one additive `summaries` column. |
| Shared UI widgets and theming | **100%** as-is reuse | `AiPipelineFallback`, `TintedIcon`, `EmptyState`, `AppShell`, `AppTheme` need zero internal changes, only new call sites. |
| AI engine reliability machinery (timeouts, cancellation, progress throttling) | **100%** | Applies to new call sites automatically; the mechanism itself is not touched. |
| Database/repository/migration *pattern* | **~90%** | Every new table/repository/migration is a new instance of an established, unmodified template. |
| Document extraction, chunking, embedding, vector storage capability itself | **~5–10%** | Genuinely novel; the only prior art is the *pattern* (interface + swappable implementation), not any reusable logic — this is the one area of the codebase with no real precedent to build from. |
| Chat orchestration logic | **~30%** | `AskAboutMeetingsUseCase`'s context-discipline and fallback behavior carries forward conceptually; its actual retrieval mechanism does not. |

**Overall, weighted toward what V2 actually spends engineering time building** (not toward the much larger body of code that's simply left alone): roughly **60–65% of V2's net-new engineering effort is applying an already-proven pattern to a new instance** (new tables, new repositories, new screens shaped like existing ones), and **roughly 35–40% is genuinely novel work with no existing precedent in this codebase** — concentrated almost entirely in Epic 3 (retrieval infrastructure) and, to a lesser extent, Epic 4 (chat orchestration).

## 15. Estimated implementation effort

Rough, solo-developer-equivalent-pace ranges per phase (see [01-master-roadmap.md](01-master-roadmap.md) for milestone detail, [02-backlog.md](02-backlog.md) for the difficulty ratings these roll up from). Presented as ranges, not false-precision point estimates — the single largest source of variance is explicitly called out.

| Phase | Estimate | Primary driver of the range |
|---|---|---|
| Phase 0 (Foundation) | **1.5–2.5 weeks** | Well-understood patterns, low uncertainty; range mostly reflects FTS5 trigger-sync correctness taking longer than expected to get right. |
| Phase 1 (Infrastructure) | **5–9 weeks** | **Dominated by M1.0's outcome.** If the preferred embedding/vector-storage approach (ADR-003/004 option 1) works cleanly, this phase sits near the low end. If it fails and the fallback path (a new native embedding runtime) is needed, this phase could run meaningfully past the high end — this is the single least predictable estimate in the entire roadmap, by design (it's exactly the risk M1.0 exists to retire early). |
| Phase 2 (Surface) | **3–5 weeks** | Mostly UI/integration work on top of validated Phase 1 infrastructure; lower uncertainty. |
| Phase 3 (Scale/Quality/Monetization) | **4–7 weeks** | Benchmarking and accessibility work is inherently open-ended until real device results are in hand; Play Billing integration has real, if bounded, complexity. |
| **Total** | **~13.5–23.5 weeks** (roughly 3–5.5 months at solo full-time pace) | Multiple independent workstreams identified in [05-dependency-graph.md](05-dependency-graph.md) (e.g., M1.1 alongside M1.0, benchmarking alongside accessibility) can compress the calendar-time total below the effort-time total if more than one person is working in parallel. |

This estimate assumes no scope changes to the frozen `docs/v2`/`docs/v2/implementation` specification and no major surprise beyond the one already-flagged, already-budgeted-for uncertainty at M1.0.
