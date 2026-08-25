# V2 Module Implementation Order

The linearization of [05-dependency-graph.md](05-dependency-graph.md), with parallel tracks called out explicitly. Numbers match [01-master-roadmap.md](01-master-roadmap.md) milestone IDs. No module below is ever scheduled before every module in its "Requires" column has shipped.

| # | Module | Requires (must already exist) | May run in parallel with |
|---|---|---|---|
| 1 | M0.1 — FTS5 for existing content | Nothing | M0.2, M0.3 |
| 2 | M0.2 — LLM request queue | Nothing | M0.1, M0.3 |
| 3 | M0.3 — Schema hygiene (`decisions` resolution, `audioMissing`) | Nothing | M0.1, M0.2 |
| 4 | M0.4 — V1 documentation sync | Nothing (docs-only) | Everything — no code dependency at all |
| 5 | M1.0 — Embedding + vector-store feasibility spike | M0.2 (spikes against the queued engine-access pattern) | M1.1 |
| 6 | M1.1 — Document import + text extraction | M0.2 (uses the queue for summarization) | M1.0 |
| 7 | M1.2 — Chunking + embedding + vector storage | M1.0 (validated approach), M1.1 (content to index) | Nothing — this is the critical-path bottleneck; nothing meaningful can start until it's done |
| 8 | M1.3 — Workspace-scoped chat | M1.2 | Nothing further within Phase 1 |
| 9 | M1.4 — Document-scoped chat | M1.3 | M2.1 (both build on the same chat infrastructure once M1.3 exists) |
| 10 | M2.1 — General chat | M1.3 | M1.4 |
| 11 | M2.2 — Unified search UI | M0.1, M1.1 | M2.1, M1.4, M2.4 |
| 12 | M2.4 — Chunked/map-reduce summarization | M1.1 | M2.1, M1.4, M2.2 (does not need chat infrastructure at all) |
| 13 | M2.3 — Navigation shell integration | M1.1, M1.3 (and M2.1 if it's ready — otherwise nav can integrate Documents/Chat incrementally as each becomes available) | Nothing — this is a genuine integration point that needs the screens it links to |
| 14 | M3.1 — Battery/thermal/performance benchmarking | M2.3 (needs the full feature surface to benchmark realistically) | M3.2 |
| 15 | M3.2 — Accessibility pass | M2.3 | M3.1 |
| 16 | M3.3 — Configurable LLM tier | M3.1, M3.2 (must know the baseline is sound before adding a second tier on top of it) | Nothing |
| 17 | M3.4 — Play Billing integration | M3.3 (Pro-tier gating needs something real to gate), business pricing decision finalized (external, not a code dependency) | M3.5's non-blocking items (keystore, hosted policy, etc. — see below) |
| 18 | M3.5 — Play Store launch close-out | M3.4 for the Data-Safety-form/billing-review items specifically; the purely administrative items (keystore, AAB pipeline, hosted privacy policy, support contact) have **no code dependency at all** and should be done as early as convenient, not held until the end | — |

## Explicit note on M3.5's administrative items

Unlike every other row in this table, generating a release keystore, wiring the AAB build pipeline, hosting the privacy policy, and setting up a support contact do not depend on any feature module shipping. Per [02-backlog.md](02-backlog.md) (Epic 8, tasks 8.3–8.7), these should be scheduled opportunistically alongside Phase 0/1 work — there's no reason a keystore doesn't exist by the time Phase 1 starts, for example. They're listed at the end of this table only because that's where they sit in the roadmap's phase narrative, not because they're blocked until then.

## Why this order, not another

The three genuinely non-negotiable gates in this sequence are: (1) the LLM queue must exist before anything spikes or builds against the shared engine, since spiking against the wrong access pattern would produce false confidence; (2) the embedding/vector-store spike must resolve before any chunking/embedding code is written for real, since building production code against an unvalidated approach is exactly the mistake V1's `flutter_llama` episode already taught this project to avoid; (3) chat features must wait for validated retrieval infrastructure, since a chat UI built against fake/unvalidated retrieval would need to be substantially reworked once real constraints (the ADR-011 token budget, the winning vector-storage approach) are known. Every other ordering choice in this document is about minimizing idle time around those three gates, not about any dependency that would break if reordered.
