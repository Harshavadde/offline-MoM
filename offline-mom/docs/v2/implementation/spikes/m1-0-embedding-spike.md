# M1.0 — Embedding & Vector-Storage Feasibility Spike

**Milestone:** M1.0, [01-master-roadmap.md](../01-master-roadmap.md). **Resolves:** ADR-003, ADR-004, ADR-011 ([03-decisions.md](../03-decisions.md)). **Date:** 2026-07-29. **Status:** Complete.

## What kind of spike this is (read this first)

This spike could not execute a real on-device model download, load a GGUF embedding model, or run actual `llama.cpp` inference — this development environment is a Windows desktop with no Android device/emulator and no ability to execute native FFI model inference. **It is a code-level, API-level feasibility spike**: direct inspection of the `llamadart` 0.8.17 package's actual source code (the same package `LlamaDartLlmEngine` already uses for chat), not an on-device benchmark. This is disclosed explicitly, the same way this project already discloses other real, unresolved limitations (ADR-015's OCR gap, R-05's "no battery/thermal benchmarking has ever been performed"), rather than presenting inspection-level confidence as if it were execution-level confidence.

**What this means concretely:** the API surface, wiring, and architecture below are verified correct by reading the package's real implementation (file paths and line numbers cited throughout). Whether a specific GGUF embedding model downloads cleanly and produces sane vectors on a real Android device has **not** been executed. This is flagged as a required manual QA step before M1.2's implementation ships to any real device or user (see "Recommendations," below).

## ADR-003 — Embedding model approach

### Question
Does `llamadart` (or the `llama.cpp` build it wraps) expose a usable embedding-mode inference API, per ADR-003's option 1?

### Finding: **Yes, confirmed.**

`llamadart` 0.8.17 exposes `LlamaEngine.embed(String text, {bool normalize = true}) → Future<List<double>>` and `LlamaEngine.embedBatch(List<String> texts, {bool normalize = true}) → Future<List<List<double>>>` (`lib/src/core/engine/engine.dart:935-984` in the package). This is the **exact same `LlamaEngine`/`LlamaBackend` class pair** `LlamaDartLlmEngine` already uses for chat generation (`llamadart_llm_engine.dart`) — same package, same native `llama.cpp`-backed worker-isolate infrastructure, same model-download-and-cache machinery (`loadModelSource`, `ModelSource.parse('hf://...')`, `ModelDownloadCancelToken`, progress callbacks). This is precisely ADR-003 option 1 as originally framed: "reuse the existing LLM's `llama.cpp` path."

Evidence trail, in order of inspection:
1. `llamadart-0.8.17/example/basic_app/bin/llamadart_embedding_example.dart` — the package's own maintainers ship a working CLI example calling `engine.embedBatch(texts, normalize: normalize)` against `LlamaEngine(LlamaBackend())`, using model `hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf`.
2. `llamadart-0.8.17/lib/src/core/engine/engine.dart:928-1017` — the public `embed`/`embedBatch` API, delegating to a `BackendEmbeddings`-typed backend, raising a typed `LlamaUnsupportedException` if the active backend doesn't support it (the `llama_cpp` backend does — see next).
3. `llamadart-0.8.17/lib/src/backends/llama_cpp/llama_cpp_backend.dart:28` — the `llama_cpp` backend (the one this app's `ModelParams`/`LlamaBackend` already select) implements `BackendEmbeddings, BackendBatchEmbeddings`.
4. `llamadart-0.8.17/lib/src/backends/llama_cpp/llama_cpp_service.dart:4426-4693` — the actual native call: `llama_set_embeddings(ctx, true)` is toggled on the context immediately before extracting embeddings via `llama_get_embeddings`/`llama_get_embeddings_seq`, and set back to `false` afterward. This confirms embedding extraction works against a normally-loaded context (no special "embedding mode" load-time flag is required) — a real, load-bearing detail that determines the implementation shape below (a second `LlamaEngine` instance, loaded the normal way, with a different model).
5. `llamadart-0.8.17/lib/src/backends/llama_cpp/worker.dart:188-202` and `worker_messages.dart` — embedding requests route through the same dedicated worker Isolate as generation requests (`EmbedRequest`/`EmbedBatchRequest`/`EmbedResponse`), so nothing about this touches the UI isolate directly, exactly like the existing chat engine.

### Decision (implementation)
`LlamaDartEmbeddingEngine` (`lib/services/ai/llamadart_embedding_engine.dart`) is a **second, independent** `LlamaEngine(LlamaBackend())` instance — not a mode-switch on the existing chat engine, since the chat model (Qwen2.5-1.5B-Instruct) is not an embedding model and a context's embedding output only makes sense for a model whose GGUF metadata actually declares embedding/pooling support. Model chosen: `embeddinggemma-300M` (Q8_0 quantization, ~300MB) — the exact model the package's own maintainers demonstrate working, chosen specifically to minimize integration risk given this spike could not itself validate a different model path end to end.

**Not yet validated (flagged for manual QA before shipping):** the actual download of this model, its real output dimensionality, and whether its vectors are semantically sane for retrieval. **License note:** `embeddinggemma` ships under Google's Gemma Terms of Use, not a plain permissive OSS license — flagged for the same kind of pre-launch check ADR-016 already mandates for parsing *libraries*, now extended to a model *asset* since this is the first time that question has come up for this project.

**ADR-003 status: updated from `Accepted — Pending Validation` to `Accepted`** (see [03-decisions.md](../03-decisions.md)).

## ADR-004 — Vector storage approach

### Question
Can `sqlite-vec` (or an equivalent SQLite vector-search extension) be integrated into this app's existing `sqflite`-based database layer, per ADR-004 option 1?

### Finding: **No — a real, structural infeasibility, not a preference.**

`llamadart`'s own example app demonstrates SQLite vector search (`example/basic_app/lib/services/sqlite_vector_search_service.dart`), but it depends on `package:sqlite3` (`sqlite3: ^3.1.6`) and `package:sqlite_vector` (`^0.9.85`) — direct Dart FFI bindings to a SQLite build the app itself links against (`sqlite3.loadSqliteVectorExtension()`). **This app uses `package:sqflite`/`sqflite_common_ffi` everywhere in `lib/database/`**, a completely different Flutter database package that wraps the *platform's own* SQLite (via a Java/Kotlin plugin bridge on Android) and does not expose an extension-loading API to Dart at all. Making `sqlite-vec` work would require replacing this app's entire database access layer — every existing repository, every migration, the whole `AppDatabase` — with `package:sqlite3`, a change with a blast radius far outside this milestone's scope and directly contradicting the explicit instruction to "reuse repositories... do not duplicate architecture."

### Decision (implementation)
`BruteForceVectorStore` (`lib/services/retrieval/vector_store.dart`) — ADR-004 option 2, exactly as its own "fall back without hesitation" framing anticipated. Cosine similarity computed in pure Dart over every row in `knowledge_chunks` (`KnowledgeChunkRepository.getAll()`), which stays genuinely viable (not a compromise) at this app's stated corpus scale (NFR-16: hundreds to low thousands of chunks, not millions) — see the benchmark section below for measured numbers at 100/500/1000/3000-document corpora.

**ADR-004 status: updated from `Accepted — Pending Validation` to `Accepted`** (see [03-decisions.md](../03-decisions.md)).

## ADR-011 — Chunk size and K calibration

### Question
Are ADR-011's starting parameters (chunk ~200-250 tokens, K=3) confirmed against real token counts?

### Finding: **Not empirically measured — same environment limitation as above.**

`llamadart`'s `LlamaEngine.tokenize()`/`getTokenCount()` exist and would give an exact answer once a real model is loaded, but that requires the same on-device execution this spike cannot perform. `DefaultChunkingService` (`lib/services/retrieval/chunking_service.dart`) therefore chunks by a **character** budget (900 characters, paragraph/sentence-boundary-aware, 2-sentence overlap), derived from ADR-011's 200-250 token target using the commonly-cited ~4 characters-per-token average for English prose with a BPE/SentencePiece-family tokenizer (the family `embeddinggemma`'s tokenizer belongs to) — a documented, widely-used estimate, not a measurement. K stays at 3 (`RetrievalEngine`'s default), the low end of ADR-011's range, kept conservative given the token budget was never itself re-validated either.

**ADR-011 status: remains `Accepted — Pending Validation`** — the character-based calibration above is a reasonable interim implementation, not the empirical validation ADR-011 itself calls for. Re-validate against `LlamaEngine.tokenize()`'s real output on real content once on-device execution is possible (recommended as the first task of M1.3, before any chat prompt-budget work locks in a number that hasn't actually been checked).

## Chunking, embedding, and retrieval — implemented (M1.2, folded into this same pass)

Given the spike above confirms ADR-003 option 1 works, the full pipeline was implemented rather than left as a prototype, per this project's own precedent (Phase 1A similarly moved straight from validation into production code within one milestone once a spike question resolved cleanly):

- `EmbeddingEngine`/`LlamaDartEmbeddingEngine` (`lib/services/ai/`)
- `ChunkingService`/`DefaultChunkingService` (`lib/services/retrieval/chunking_service.dart`)
- `KnowledgeChunkRepository`/`SqfliteKnowledgeChunkRepository` (`lib/repositories/`), migration v7 (`lib/database/migrations/v7.dart`)
- `VectorStore`/`BruteForceVectorStore` (`lib/services/retrieval/vector_store.dart`)
- `IndexingService`/`DefaultIndexingService` (`lib/services/retrieval/indexing_service.dart`)
- `RetrievalEngine`/`DefaultRetrievalEngine` (`lib/services/retrieval/retrieval_engine.dart`)
- `DocumentIndexer` (`lib/features/documents/document_indexer.dart`), wired into `ProcessNewDocumentUseCase`/`RetryDocumentProcessingUseCase` so a newly-imported document is chunked and embedded automatically, without user action, per FR-40.

**Scope decision, disclosed here and in [10-v2-progress.md](../10-v2-progress.md):** meeting indexing (the roadmap's "meetings gain the same background indexing step retroactively") was **not** wired in this pass. `KnowledgeChunk`/`IndexingService` are already meeting-capable (content-type-agnostic by design), so adding a `MeetingIndexer` mirroring `DocumentIndexer` is a small, low-risk follow-up — deliberately deferred rather than expanding this milestone's blast radius into `MeetingStatus` (a wider-reaching enum with more exhaustive-switch call sites than `DocumentStatus`) without a dedicated pass.

**Chat/retrieval UI, general chat, workspace chat:** explicitly out of scope for this milestone (M1.3+) and not touched — `RetrievalEngine` exists and is fully tested as a standalone component so `WorkspaceChatUseCase` (still a throwing stub, untouched) has a validated contract to call when that milestone starts.

## Benchmarks

`test/performance/indexing_benchmark_test.dart` (100/500/1000/3000-document synthetic corpora, `FakeEmbeddingEngine`, desktop dev machine via `sqflite_common_ffi`):

| Corpus | Chunks | Indexing (total / per-doc) | Retrieval (top-3) |
|---|---|---|---|
| 100 docs | 200 | 324ms / 3.24ms | 28ms |
| 500 docs | 1000 | 1272ms / 2.54ms | 44ms |
| 1000 docs | 2000 | 1482ms / 1.48ms | 77ms |
| 3000 docs | 6000 | 3845ms / 1.28ms | 182ms |

**These numbers isolate the Dart/SQLite-side cost** (chunking, batch insert, brute-force cosine scan) **from real embedding-model inference latency**, which cannot be measured without a real device — the same gap this whole report discloses throughout. Retrieval time grows sub-linearly with corpus size in this run, a reasonable early signal at this app's scoped scale (NFR-16) but not a substitute for real on-device numbers. Memory usage was not measured (no practical way to sample native heap/RSS from a `flutter test` process in this environment). Real on-device numbers (model load time, per-chunk embed latency, total indexing wall-clock for a realistic document, memory usage) are a required input to M3.1's benchmarking pass, not something this spike can substitute for.

## Recommendations

1. **Before M1.2's code ships to any real device:** manually verify the `embeddinggemma-300M-Q8_0.gguf` download completes, loads, and produces a plausible (non-NaN, correctly-dimensioned, not-all-zero) vector via `LlamaDartEmbeddingEngine.embed()` on an actual Android device or emulator. This spike's confidence is source-inspection-level, not execution-level, for this specific step.
2. **Before adopting `embeddinggemma` as a permanent dependency for a commercial release:** a lightweight legal check of the Gemma Terms of Use, mirroring ADR-016's parsing-library discipline.
3. **Early in M1.3 (before locking in a chat prompt-budget number):** re-run ADR-011's chunk-size calibration using `LlamaEngine.tokenize()`'s real output against representative meeting/document text, correcting `DefaultChunkingService.targetChunkChars`'s char-per-token estimate if it's meaningfully off.
4. **When meeting indexing is prioritized:** add a `MeetingIndexer` mirroring `DocumentIndexer`, plus `MeetingStatus.indexing` and its exhaustive-switch call sites (`meeting_list_tile.dart`, `meeting_details_screen.dart`) — the retrieval infrastructure underneath already supports it without change.
