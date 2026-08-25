# V2 Retrieval-Augmented Generation (RAG) Architecture

Status: this document was written before implementation began and is kept as originally written (see [README.md](README.md) for why), so it still poses the embedding-model and vector-store choices below as open feasibility questions. Both are now resolved and shipped: the embedding model is `ggml-org/embeddinggemma-300M-GGUF` (Q8_0, ~300MB), running as a second independent `LlamaEngine` instance alongside the chat LLM (not a separate runtime); the vector store is brute-force cosine similarity over the `knowledge_chunks` table (`BruteForceVectorStore`), not `sqlite-vec` — approach 1 in this document's own recommendation. As of Phase 6B (ADR-037), Workspace Chat's retrieval is a genuinely fused hybrid pipeline — this vector path plus chunk-level BM25 keyword search, merged via Reciprocal Rank Fusion, with confidence-gated context assembly and a general-knowledge LLM fallback — superseding this document's original vector-only sketch; the Search screen's own keyword search (`content_fts`) remains a deliberately separate, unranked system (different granularity/consumer, ADR-037). This also supersedes §"Fallback behavior when nothing relevant is found" below: rather than always returning the same plain "couldn't find anything" string, a low/no-confidence retrieval result now lets the LLM answer from its own general knowledge, with the answer clearly labeled as not coming from the user's own content and never carrying fabricated citations (`sources` stays empty for that path) — an explicit, approved product decision, not a quiet regression of the original "never guess" intent below. See [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md)§4 for the as-built pipeline diagram and [implementation/03-decisions.md](implementation/03-decisions.md) for the related ADRs (ADR-003/004/011/037).

This is the single largest new technical component in V2, and the one carrying the most unvalidated risk — flagged honestly throughout rather than presented as settled. See [11-ai-architecture.md](11-ai-architecture.md) for the embedding-model feasibility question this entire document depends on.

## Why RAG, specifically

The existing Ask AI feature (`AskAboutMeetingsUseCase`) is not retrieval-augmented generation today — it's keyword-overlap scoring over meeting *summaries* (never raw transcripts), selecting the top 4 by shared-word count, with no semantic understanding at all. That approach cannot extend to "chat with everything," for three concrete reasons confirmed by reading the implementation:

1. It only ever sees summaries, never the original transcript or document text — so any answer is bottlenecked by whatever the summarization step already chose to compress away.
2. Pure keyword overlap fails on paraphrase and synonyms — a question about "budget" won't match a meeting that only used the word "spend."
3. It performs a sequential database fetch per candidate meeting (done twice, redundantly), which does not scale as content volume grows — exactly the regime a "workspace" accumulates into over time.

Real RAG — chunk the source content, embed each chunk, retrieve the most semantically relevant chunks for a given question, and only then hand a small, relevant context to the LLM — fixes all three, and is the only way to answer a cross-content question at all within the model's 2048-token context window.

## Pipeline

```
Content becomes ready (Meeting: transcript persisted; Document: text extracted)
        │
        ▼
  Chunking (ChunkingService)
        │
        ▼
  Embedding (EmbeddingEngine, on-device)
        │
        ▼
  Storage (knowledge_chunks table, see 12-database-design.md)
        │
        │  ... later, on a chat question ...
        ▼
  Query embedding (same EmbeddingEngine)
        │
        ▼
  Similarity search (VectorStore) → top-K chunks
        │
        ▼
  Context assembly (chunk text + source references)
        │
        ▼
  LLM generation (via LlmRequestQueue, chat prompt contract — see 11-ai-architecture.md)
        │
        ▼
  Answer + cited sources shown to user
```

## Chunking strategy

- Chunk by paragraph/sentence-boundary-aware splitting up to a target size (a starting point of roughly 300–500 tokens per chunk, small enough that several can fit in the 2048-token budget alongside the question and system prompt, large enough to preserve meaningful context within a chunk) — not a fixed-character-count cut like the current `_maxTranscriptChars` truncation, which the chunking approach replaces conceptually for retrieval purposes (the existing flat truncation may still apply separately for *summarization*, per V1's already-planned chunk-and-reduce future-scope item).
- A small overlap between consecutive chunks (e.g. one to two sentences) so an answer-relevant sentence sitting near a chunk boundary isn't split away from its surrounding context.
- Chunking runs once per content item, in the background, as part of the `indexing` status stage ([FR-40](08-functional-requirements.md)) — not recomputed on every query.

## Embedding

Depends entirely on the feasibility spike described in [11-ai-architecture.md](11-ai-architecture.md) — either a `llama.cpp`-based embedding model (preferred, reuses existing model infrastructure) or a separate lightweight on-device embedding runtime. This document does not assume the answer; it specifies the pipeline stage's contract (`text chunk in → fixed-dimension vector out, entirely on-device`) independent of which implementation satisfies it.

## Vector storage and similarity search

Given the existing, deliberate commitment to SQLite as the only data store (no ORM, no second database engine, stated explicitly in V1's database-design rationale), two viable approaches, in preference order:

1. **`sqlite-vec`** (a lightweight SQLite extension purpose-built for vector similarity search) if it can be integrated into the existing `sqflite`-based Android build without introducing a new, separate database engine — the best fit for the project's stated philosophy of using SQLite's own capabilities (mirrors the FTS5 decision in [13-search-architecture.md](13-search-architecture.md)) rather than adding new infrastructure. **Feasibility on Flutter/Android via `sqflite` needs direct validation** — not assumed.
2. **Brute-force cosine similarity in Dart**, computed over embeddings loaded from the `knowledge_chunks` table, as a fallback if (1) proves infeasible. At the personal/small-team corpus scale this app is scoped for (NFR-16: hundreds to low thousands of chunks, not millions), a brute-force scan is genuinely viable — this is not a compromise unique to a resource-constrained app, it's a reasonable engineering choice at this scale, and avoids a real-ANN-index dependency (e.g. HNSW) that would be substantial over-engineering for the actual data volumes involved.

**Recommendation**: prototype approach 1 first during the same feasibility spike as the embedding model; fall back to approach 2 without hesitation if it doesn't pan out cleanly — a working brute-force implementation beats a blocked "ideal" one.

## Context assembly and citation

For a workspace-scoped question, the top-K retrieved chunks (K starting around 4–6, tuned against the 2048-token budget alongside the system prompt and question) are assembled into the chat prompt with their source (meeting title + date, or document title) attached to each chunk. The chat prompt contract ([11-ai-architecture.md](11-ai-architecture.md)) asks the model to reference sources in its answer, which the UI parses out to satisfy [FR-30](08-functional-requirements.md) (citation) — this reuses one LLM call rather than requiring a second "which sources did you use" call.

## Reuse of existing patterns

- Fallback behavior when nothing relevant is found: same plain "couldn't find anything about that" response `AskAboutMeetingsUseCase` already returns today, rather than a guess.
- Generation timeout/cancellation: identical 45-second stall timeout, routed through the new `LlmRequestQueue` ([11-ai-architecture.md](11-ai-architecture.md)).
- Background indexing status: `indexing`, alongside `extracting`, in the `Document.status` state machine — same UI pattern (`AiPipelineFallback`) already used for "downloading model"/"summarizing" states.

## What this document deliberately does not commit to

Exact chunk-size tokenization details, the specific embedding model/dimensionality, and the final choice between `sqlite-vec` and brute-force search are all pending the Phase 1 feasibility spike referenced throughout. This document specifies the pipeline shape and the constraints that shape (on-device only, SQLite-first, reuse the existing timeout/queue discipline) — not implementation details that should be validated against real code before being written down as settled.
