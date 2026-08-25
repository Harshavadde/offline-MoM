# Beyond V2 — Future Roadmap

This document distinguishes three tiers, from most to least certain:

1. **Approved Future Architecture** — officially approved and *will* be built. Not yet implemented, not "ideas" — a committed direction. Described here as future architecture, never as current implementation. See [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md) for how each of these relates to what exists today (marked "Current Architecture → Approved Future Architecture" where a diagram already shows the current state).
2. **Future Ideas** — not yet approved; genuinely open product questions, carried-forward V1 items, or directions worth recording but not committed to.
3. **Permanently out of scope** — restated at the bottom, so it never quietly drifts.

For what is actually implemented today, see [implementation/10-v2-progress.md](implementation/10-v2-progress.md) and [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md) — nothing in this document should be read as describing shipped behavior.

## Approved Future Architecture

These are committed directions the product will build. Everything listed below is genuinely **not yet built** (verified by direct code inspection, most recently during the Phase 6B documentation pass) — this section describes only what remains future; anything that has since shipped is removed from here, not left alongside the real items with a "shipped" label. See [implementation/10-v2-progress.md](implementation/10-v2-progress.md) and [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md) for what has actually shipped, including the AI Model Manager and profession-based Whisper recommendations (both Phase 6A, ADR-036) and Hybrid Retrieval (Phase 6B, ADR-037, [implementation/03-decisions.md](implementation/03-decisions.md)).

### Additional Chat LLM / Embedding model tiers

The AI Model Manager itself (download/install/switch/verify/delete for Chat LLM, Embedding, and Speech-to-text models) shipped in Phase 6A — it is **not** future architecture and is not described here; see [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md)§5b for the as-built diagram. What remains future is narrower than "the AI Model Manager": `ModelCatalog` has exactly one real Chat LLM tier and one real Embedding tier today (honestly scoped rather than padded with unverified additional model sources — ADR-036; R-38, [implementation/04-risk-register.md](implementation/04-risk-register.md)). Speech-to-text already has all 6 real Whisper sizes, so that part of "downloadable models" is fully delivered, not future.

Approved future architecture: a second Chat LLM tier and a second Embedding tier, each added to `ModelCatalog` following the same feasibility-spike discipline ADR-003 already established for the embedding model itself, extending the already-shipped AI Model Manager rather than requiring a new one.

### Profession-based recommendations for Chat LLM / Embedding

Profession-based recommendations for Speech-to-text (9 profiles, real accuracy/RAM/storage/speed reasoning across all 6 real Whisper tiers) shipped in Phase 6A (ADR-036) — **not** future architecture, and not described here.

What remains future: the Chat LLM and Embedding recommendations `ProfessionRecommendations` gives today are the same single catalog entry for every profession, because that's all there is to recommend between (see the item above) — disclosed honestly in `ProfessionRecommendations`'s own doc comment, not presented as more personalized than it is. Approved future architecture: once a second LLM/embedding tier exists (above), extend `ProfessionRecommendations` to genuinely differentiate those two kinds per profession too — a data change to one file, not new architecture, since the recommendation engine, UI, and one-tap setup flow are already built to support it.

### Productivity Toolkit evolution

The Student Toolkit (Image Tools, Scanner, PDF Tools — Phases 5A/5B, ADR-033/034) already serves a broader set of real-world workflows than "student" alone implies: resumes, passports, visas, government forms, invoices, ID cards, medical reports.

Approved future architecture:
- **"Student Toolkit" → "Productivity Toolkit" as the product-facing name.** The underlying module already serves job seekers, teachers, freelancers, accountants, and small business owners as much as students. The code's own naming (`StudentToolkitScreen`, `/toolkit` routes, `student_toolkit/` folder) is not required to change — a cosmetic, mechanical rename that can happen independently of and later than the marketing/UI-copy change.
- **Student-first launch strategy.** Play Store marketing/positioning leads with the student segment specifically (exam season, admission season, scholarship deadlines — the concrete, high-frequency trigger moments this toolkit's own preset names already target: Government Exam, Scholarship, College Admission) before broadening messaging to the other personas the toolkit already technically serves. A go-to-market sequencing decision belonging with whoever owns [19-playstore-launch.md](19-playstore-launch.md) and [02-market-positioning.md](02-market-positioning.md).

### Licensing Architecture, Premium Architecture, Backend Licensing Service & Play Billing integration

Today there is no licensing system, no premium tier, no backend of any kind, and no Play Billing integration — the app is fully unlocked, fully offline, with zero accounts.

Approved future architecture: a licensing/premium system will be built, on these fixed constraints (restated from [18-subscription-model.md](18-subscription-model.md), which laid out the implementation options this approval now commits the *category* of, not yet a specific option):
- The **only** architecturally acceptable backend shape is one whose sole job is licensing/account management — never a general-purpose backend, never a path for user content (meetings, documents, chat, toolkit files) to leave the device under any circumstance.
- Entitlement checking uses Google Play Billing's on-device purchase-state API wherever possible, avoiding a custom backend entirely for the common case (Option B in [18-subscription-model.md](18-subscription-model.md)); a dedicated backend is reserved for scenarios Play Billing alone can't cover (e.g. B2B/organizational licensing, [implementation/04-risk-register.md](implementation/04-risk-register.md) R-14).
- What becomes premium is scoped to capacity/quality gates (document limits, model tier, Toolkit output caps or higher-quality presets) — never the core privacy guarantees, data deletion, or app-lock/security features (restated from [18-subscription-model.md](18-subscription-model.md)).

**Still an open implementation decision, not resolved by this approval**: which specific option (A: paid-app-no-freemium, B: free + one-time Pro unlock, or a B2B-only backend addition) is the one actually built — see [18-subscription-model.md](18-subscription-model.md) for the trade-offs. This approval commits to *building licensing/premium architecture*, not to a specific option among those already laid out. Needs its own ADR, its own threat-model update to [16-security.md](16-security.md), before implementation begins.

### Future model lifecycle enhancements

Once a second Chat LLM/Embedding tier exists (above) and real OCR/Vision/Translation engines are eventually added (`ModelKind` already reserves these three, with zero catalog entries today — Phase 6A, ADR-036), letting capable devices opt into meaningfully better retrieval/chat quality becomes a natural extension of `ModelLifecycleManager`'s existing load/unload/idle-timeout machinery, already generic over every `ModelKind` — additional model kinds and tiers managed the same way, not a new lifecycle mechanism.

## Future Ideas

Not yet approved — genuinely open product questions, or directions worth recording but not committed to. Nothing in this section should be read as scheduled or as architecture the product is currently moving toward.

### Carried forward from V1, still unresolved (restated, not re-decided)

- **iOS support** — blocked only by scope decision, not technology; `whisper_flutter_new`, `llamadart`, and every other native plugin already support iOS.
- **Speaker diarization** — whisper.cpp doesn't provide this natively; would need additional tooling.
- **Re-introducing AI-extracted action items/decisions** — conditional on a future larger default model handling structured JSON extraction more reliably than the current 1.5B model does; the schema (`ActionItem.owner`/`.dueDate`, the `decisions` table) was deliberately left forward-compatible for exactly this.
- **Bundling AI models inside the app package** instead of downloading on first use — explicitly still an open, undecided product question in V1's own documentation, not resolved here either (trades a much larger install size for zero first-run network dependency at all). Distinct from the already-shipped AI Model Manager (Phase 6A), which manages multiple *downloaded* models, not bundling them.

### New, V2-dependent ideas

- **Multi-device access without cloud sync.** Peer-to-peer or local-network-only sync (e.g., a phone and a tablet on the same Wi-Fi exchanging an encrypted local backup, with no server involved) would extend the workspace to multiple devices without touching the "no cloud sync, ever" constraint — genuinely interesting, genuinely hard, and not attempted until the single-device workspace (V2) is solid.
- **Structured knowledge extraction** (entities, relationships, a lightweight local graph over meetings/documents) — a much larger bet than the now-shipped Hybrid Retrieval work (Phase 6B, [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md)§4), worth considering only once real usage shows plain chat-with-your-content isn't enough on its own.
- **A desktop companion**, if the Flutter codebase's existing Android-only scope is ever revisited — would face its own toolchain-isolation questions analogous to what V1's installation guide already documents for the isolated Flutter SDK setup on a shared machine.
- **Extensibility/plugin model** for new document types or content sources beyond PDF/DOCX/TXT/Markdown, if user demand shows up for formats not in V2's initial set (e.g. EPUB, HTML clippings, email exports) — the `DocumentTextExtractionService` interface in [10-system-architecture.md](10-system-architecture.md) is deliberately structured to make adding a new format an additive change, not a redesign, whenever that need arises.

### New, retrieval-adjacent ideas not covered by the shipped Hybrid Retrieval scope

- **User-facing metadata filter/facet UI.** `KnowledgeChunkFilter` already exists and is used internally by the now-shipped Hybrid Retrieval pipeline (Phase 6B) as a pipeline stage; exposing it directly to users (date ranges, content-type toggles, favorite-only) as visible Search/Chat filter controls is a smaller, separate UI step not yet approved on its own.
- **Search-screen ranking/semantic matching.** Phase 6B's Hybrid Retrieval pipeline deliberately covers Chat only (ADR-037) — the Search screen's own `content_fts` query still has no `bm25()` ranking and no semantic-similarity path. Extending Search to reuse `knowledge_chunks_fts`/`VectorStore` is a plausible, contained follow-up, not yet approved.

## Permanently out of scope regardless

Restated one more time because it's the one list in this entire document set that should never quietly drift: cloud sync, accounts/login for the core product, a general-purpose backend, third-party platform integrations (Zoom/Teams/Meet/WhatsApp), an enterprise admin dashboard. The Approved licensing backend above is a named, narrow exception — scoped to licensing/account management only, never a path for user content — not a reopening of this list. If any item on this list is ever seriously reconsidered, that reconsideration should happen explicitly, in a document like this one, the same way [18-subscription-model.md](18-subscription-model.md) explicitly reopened the subscription question rather than silently deciding it either way.
