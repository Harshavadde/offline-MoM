# OfflineMoMAI V2 — Private Offline AI Workspace: Documentation Set

Status: **originally written as a pre-implementation specification; substantially implemented since.** This document set (`01`–`20`) was written before any V2 code existed, and is kept as originally written — a frozen record of intent and rationale, not retroactively edited to match what shipped. It remains a genuinely accurate description of *why* V2 looks the way it does. For **what has actually shipped, phase by phase, and how implementation diverged from this original spec where it did**, see [`implementation/10-v2-progress.md`](implementation/10-v2-progress.md) (live status tracker) and [`implementation/03-decisions.md`](implementation/03-decisions.md) (the decision log for everything this spec left open or that implementation reality required revisiting). As of Phase 6B, Phases 0 through 6B are done — meetings, documents, cross-content chat, workspace search, the Student Toolkit (Image Tools, Scanner, PDF Tools), the AI Model Manager (download/install/switch/verify/delete for Chat LLM, Embedding, and Speech-to-text models, plus profession-based recommendations), and a Hybrid Retrieval Engine (fused vector + BM25 keyword search with intelligent ranking, confidence-gated context assembly, and a general-knowledge LLM fallback with no fabricated citations) are all real, working, tested features, not proposals. `docs/` (the pre-V2 V1 documentation) is untouched and describes the original meeting-only product; this folder describes its evolution, both as originally specified and — via the `implementation/` subfolder — as actually built. See also [`implementation/12-architecture-diagrams.md`](implementation/12-architecture-diagrams.md) for diagrams of the system as it exists today.

**Three status tiers, used consistently across this folder:** (1) **Current Implementation** — exists in `lib/` today, verified against source, described in `implementation/12-architecture-diagrams.md` and `implementation/10-v2-progress.md`; (2) **Approved Future Architecture** — officially approved, committed directions the product *will* build (a second Chat LLM/Embedding model tier; the Productivity Toolkit rename; licensing/premium architecture — see [`20-future-roadmap.md`](20-future-roadmap.md) and ADR-035/ADR-036 in [`implementation/03-decisions.md`](implementation/03-decisions.md)), never described as already implemented; (3) **Future Ideas** — genuinely open, not yet approved, also in [`20-future-roadmap.md`](20-future-roadmap.md). The AI Model Manager and Whisper-tier profession recommendations moved from tier (2) to tier (1) in Phase 6A (ADR-036); Hybrid Retrieval moved from tier (2) to tier (1) in Phase 6B (ADR-037).

## Why this folder exists

OfflineMoMAI V1 is a complete, working, fully offline meeting assistant. This document set specifies its evolution into a broader private offline AI workspace — meetings becoming one content type among several (documents, chat, cross-content search, a knowledge base) — as a **commercial product**, not a college project. Every document here is grounded in the actual V1 codebase: its architecture, its database schema, its AI pipeline, its known gaps, and its already-documented future-scope plans. Nothing here proposes a rewrite, and nothing here contradicts what already works.

## How to read this folder

Read in order for the full narrative, or jump to what you need:

| Doc | Covers |
|---|---|
| [01-product-vision.md](01-product-vision.md) | The strategic pivot and its guiding principles |
| [02-market-positioning.md](02-market-positioning.md) | Competitive landscape and why privacy-as-architecture wins |
| [03-prd.md](03-prd.md) | Modules, user stories, explicit reuse mapping |
| [04-srs.md](04-srs.md) | Formal scope/interfaces/constraints |
| [05-user-personas.md](05-user-personas.md) | Who V2 is for, including new segments cloud AI can't serve |
| [06-user-journeys.md](06-user-journeys.md) | Step-by-step flows through the new modules |
| [07-feature-roadmap.md](07-feature-roadmap.md) | Phased build order (Phase 0 → 3) |
| [08-functional-requirements.md](08-functional-requirements.md) | Traceable FR-22 onward, continuing V1's numbering |
| [09-non-functional-requirements.md](09-non-functional-requirements.md) | Traceable NFR-10 onward, continuing V1's numbering |
| [10-system-architecture.md](10-system-architecture.md) | Module boundaries, new components, full reuse mapping |
| [11-ai-architecture.md](11-ai-architecture.md) | LLM request queue, embedding strategy, chat prompt contract |
| [12-database-design.md](12-database-design.md) | New tables, migration plan v4–v7 |
| [13-search-architecture.md](13-search-architecture.md) | FTS5 design, search vs. RAG |
| [14-rag-architecture.md](14-rag-architecture.md) | Chunking, embeddings, vector storage, retrieval pipeline |
| [15-storage-architecture.md](15-storage-architecture.md) | Document storage, backup extension |
| [16-security.md](16-security.md) | Extended threat model for documents/chat |
| [17-privacy.md](17-privacy.md) | The architecture-level privacy invariant and why it must hold |
| [18-subscription-model.md](18-subscription-model.md) | Monetization options compatible with "no accounts, ever" |
| [19-playstore-launch.md](19-playstore-launch.md) | Commercial launch readiness checklist |
| [20-future-roadmap.md](20-future-roadmap.md) | Beyond V2 |

## The three things every document in this set agrees on

1. **Reuse before rebuild.** Every new capability maps onto an existing, proven pattern from V1 — the meeting pipeline's state machine, the repository pattern, the shared AI engine's timeout discipline, the onboarding model-download UX. Where a document proposes something genuinely new (the retrieval/embedding layer, the LLM request queue), it says so explicitly and flags the risk.
2. **Privacy is architecture, not policy.** The one-network-edge invariant that already makes V1's privacy claims verifiable, not just asserted, is treated as the hardest constraint in this entire document set — see [17-privacy.md](17-privacy.md).
3. **Honesty about what's unvalidated.** The single largest open technical risk in V2 — whether on-device embeddings are feasible through the existing `llamadart`/`llama.cpp` path — is flagged as exactly that in [11-ai-architecture.md](11-ai-architecture.md) and [14-rag-architecture.md](14-rag-architecture.md), with a concrete recommendation (a short feasibility spike) rather than an assumption dressed up as a decision.

## What's explicitly a decision for the product owner, not resolved by this document set

- Which specific monetization option (A/B/C) to build — a premium tier *in general* is now Approved Future Architecture (ADR-035), but the choice among options remains open ([18-subscription-model.md](18-subscription-model.md)).
- The fate of V1's vestigial `decisions` table/pipeline ([07-feature-roadmap.md](07-feature-roadmap.md), Phase 0).
- The FIFO-vs-priority design of the LLM request queue, pending real usage data ([11-ai-architecture.md](11-ai-architecture.md)).
- Whether at-rest database encryption should be added before general availability ([16-security.md](16-security.md)).
