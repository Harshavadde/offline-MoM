# V2 AI Architecture

Status: this document was written before implementation began and is kept as originally written (see [README.md](README.md) for why). The embedding feasibility spike recommended below (option 1, a dedicated GGUF embedding model through the existing `llama.cpp` path) succeeded: the shipped embedding model is `ggml-org/embeddinggemma-300M-GGUF` (Q8_0), run as a second independent `LlamaEngine` instance alongside the chat LLM — no separate ONNX/TFLite runtime (option 2) was needed. The LLM request queue described below also shipped as `DefaultLlmRequestQueue`. See [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md) for the as-built pipeline and [implementation/03-decisions.md](implementation/03-decisions.md) for the related ADRs.

Extends V1's `docs/architecture/ai-architecture.md`, which remains the accurate description of the existing STT/LLM engines, their timeout/cancellation machinery, and the strict-JSON summarization contract — none of that changes. This document covers what's new: an explicit request queue (fixing a real gap), an embedding strategy for retrieval, and a new prompt contract for chat.

## Correction to the existing documented model

V1's documentation states that the shared `llamadart` engine "serializes requests — a new call waits for whatever's currently running rather than being rejected." A trace of the actual `llamadart` 0.8.17 source shows this is not accurate for the library version currently in use: a second concurrent `generate()` call on the same engine instance fails immediately with a `StateError`-derived exception, rather than queuing. This was lower-risk in V1 because concurrent AI calls were rare (a background summarization finishing to coincide with a user opening Ask AI). It becomes a real correctness requirement in V2, where document chat, workspace chat, general chat, and background meeting/document summarization all compete for the same one engine far more often. **NFR-11 in [09-non-functional-requirements.md](09-non-functional-requirements.md) exists specifically to close this gap.**

## The LLM request queue

A new component, `services/ai/llm_request_queue.dart` (see [10-system-architecture.md](10-system-architecture.md)), sitting between every use case that currently calls `LlmEngine` directly and the engine itself.

**Design (spec-level, not code):**

- A single in-process FIFO queue. Every generation request (summarize meeting, summarize document, answer a document-scoped question, answer a workspace-scoped question, general chat turn) is submitted to the queue rather than calling the engine directly.
- Exactly one request is in flight against the shared engine at a time — matching what the engine can actually do, rather than what the old documentation assumed it did.
- Each request keeps its own existing 45-second stall timeout once it starts running; queueing time (waiting for an earlier request to finish) is not counted against that budget, since a queued-but-not-yet-started request isn't stalled, it's simply waiting its turn.
- **Open design question for Phase 1, not resolved here**: should a user-initiated foreground request (e.g., the user is actively waiting on a chat answer) be able to preempt a background request (e.g., a meeting just finished transcribing and is about to auto-summarize)? A simple FIFO queue treats them equally; a priority queue would make the app feel more responsive during active chat use at the cost of delaying background summaries. Recommendation: start with plain FIFO (simplest, matches existing behavior where nothing currently preempts anything) and revisit only if real usage shows background summarization noticeably blocking chat responsiveness.
- On engine failure (including the existing stall-timeout path), the queue advances to the next request rather than getting stuck — the same "the engine must always be freed for the next caller" principle that already motivates calling `cancelGeneration()` on timeout today.

## Embedding strategy

Retrieval (see [14-rag-architecture.md](14-rag-architecture.md)) requires turning text into vectors, on-device, with no cloud embedding API — a harder constraint than the chat model itself, since cloud embedding calls are common even in otherwise-local RAG setups and are explicitly ruled out here (NFR-17).

**This is the single largest unvalidated assumption in the entire V2 plan and should be treated as such.** Two candidate approaches, in preference order:

1. **A dedicated small embedding model, run through the same `llama.cpp`-based path the LLM already uses**, if `llamadart` (or the underlying `llama.cpp` build it wraps) exposes an embedding-mode inference API for compatible GGUF embedding models. This would reuse the existing model-download-and-cache infrastructure (Hugging Face source, same timeout/cancellation pattern, same Settings-screen model management) almost unchanged. **Not yet confirmed feasible** — `llamadart`'s API surface used by this app today is generation-oriented (`generate()`/`answerQuestion()`-style streaming), and whether it exposes a usable embedding extraction path needs a direct spike against the actual package, the same way `flutter_llama`'s viability was checked (and rejected) before committing to it in V1.
2. **A separate, smaller on-device embedding runtime** (e.g., a lightweight ONNX or TFLite embedding model bundled/downloaded independently of the `llama.cpp` path), if option 1 proves infeasible. Higher integration cost (a new native dependency, a new ProGuard rule to verify per V1's established convention, a new download/cache path) but decouples embedding capability from whatever `llamadart` does or doesn't expose.

**Recommendation**: a one-to-two-day feasibility spike against option 1 is the first concrete engineering task of Phase 1, before any Document or Chat UI work begins. If it's not viable, fall back to option 2 rather than blocking the whole roadmap on it — but do not proceed on an assumption either way.

## Chat prompt contract

A new prompt contract, versioned the same way the existing summarization contract is (`promptVersion`, currently `3`, bumped on every change so failures can be traced to a specific contract version):

- **Document-scoped chat**: system prompt instructs the model to answer only from the provided document excerpt(s), say plainly if the answer isn't present, and — unlike the summarization contract — respond in free text, not strict JSON, since a conversational answer doesn't benefit from JSON's structure the way a summary's fixed fields do.
- **Workspace-scoped chat**: same discipline, context assembled from retrieval across meetings + documents (see [14-rag-architecture.md](14-rag-architecture.md)), with an instruction to reference which source each part of the answer came from in a parseable way (e.g., a trailing "Sources:" line the UI can extract) so [FR-30](08-functional-requirements.md) (source citation) doesn't require a second model call.
- **General chat**: minimal system prompt (assistant identity, offline-only disclosure if relevant to the conversation), no retrieved context — the closest thing to a "raw" chat experience the app offers.

## Context window discipline, unchanged constraint

The model's practical context remains 2048 tokens (V1's existing `ModelParams(contextSize: 2048)`), shared by every feature including the new ones. This is why retrieval (selecting a *small*, relevant slice of content) rather than "stuff everything in" is not optional for V2 — it's the only way a workspace-wide question can be answered at all within the existing window. If a future larger default LLM tier is adopted (see [07-feature-roadmap.md](07-feature-roadmap.md) Phase 3), this constraint loosens but the retrieval architecture doesn't become unnecessary — it just gets to work with a bigger context budget per call.

## What does not change

The Whisper STT engine, the existing summarization JSON contract for meetings, the 45-second generation stall timeout, the 90-second/15-minute model-download timeout pair, and the `_stallTimeout`/`cancelGeneration()` mechanism itself are all reused exactly as they are today for every new call site.
