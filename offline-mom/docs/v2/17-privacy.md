# V2 Privacy Architecture

This is the architecture-level privacy specification for V2 — the design constraints every new module must satisfy. `docs/legal/privacy-policy.md` remains the user-facing legal document and is not duplicated here; this document is what that policy is required to remain true to.

## The invariant that must survive V2 unchanged

V1's deployment architecture has exactly one network-capable edge: the one-time AI model download. Every privacy claim the product makes rests on that being verifiably true, not just asserted. **V2 must preserve this invariant exactly** — the only permitted addition is one more model download (an embedding model, if [11-ai-architecture.md](11-ai-architecture.md)'s feasibility spike requires one), which is the same *kind* of network event as what already exists, not a new kind.

Concretely, this rules out, regardless of how much better they might make the product:

- A cloud embedding API for retrieval (a very common RAG pattern elsewhere — explicitly not used here; see [14-rag-architecture.md](14-rag-architecture.md)).
- Any analytics, crash reporting, or telemetry SDK.
- Any "sync your workspace across devices" feature that isn't fully peer-to-peer/local-network (and even that is out of scope for V2 — see [20-future-roadmap.md](20-future-roadmap.md)).

## Data handled by each new module

| Module | Data | Leaves the device? |
|---|---|---|
| Documents | Original file, extracted text | Never |
| Knowledge base / retrieval | Chunk text, chunk embeddings | Never — embeddings are generated on-device and never transmitted, including to any embedding-model provider |
| Chat | Questions, answers, source citations | Never |

## Why chat history is persisted, unlike the old Conversation Translator

This is worth stating explicitly since it's a deliberate departure from a precedent, not an inconsistency. The Conversation Translator was designed to never persist anything, on the reasoning that a translated conversation with a stranger is *someone else's* spoken words as much as the user's, and treated as more sensitive-by-default than a recorded meeting. Chat in V2 is different in kind: it is the user's own questions and the app's own synthesized answers about the user's own content. Persisting it locally (deletable, same as everything else, never transmitted) is the more useful default — a user should be able to reopen a chat the way they reopen a meeting — and does not weaken the privacy invariant, since "persisted locally" and "sent somewhere" are not the same thing. If a future feature ever needs the Conversation Translator's stricter never-persist pattern again, the developer guide already documents it as a reusable pattern — it is not lost, just not the default here.

## Verification, not just assertion

Per [02-market-positioning.md](02-market-positioning.md), the product's differentiation depends on this being checkable, not just claimed. Practically, this means:

- Any code review or audit of V2 should be able to confirm the "one network edge" claim by inspecting the deployment architecture ([10-system-architecture.md](10-system-architecture.md)), the same way it can for V1 today.
- Any new dependency introduced for document parsing or embedding should be checked for its own network behavior before adoption (some PDF/DOCX libraries or ML runtimes phone home for telemetry by default) — this is a due-diligence step for [11-ai-architecture.md](11-ai-architecture.md)'s embedding spike and the document-parsing library choice in [16-security.md](16-security.md), not an afterthought.

## Children's privacy, permissions, and other carried-forward commitments

Unchanged from V1: the app collects no personal information from anyone, so there's nothing distinct to say about children specifically; new permissions (if any — document import via the system file picker likely needs none beyond what's already granted) are requested only when the relevant feature is used, for that feature only.
