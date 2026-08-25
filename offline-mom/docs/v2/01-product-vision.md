# V2 Product Vision — OfflineMoMAI as a Private Offline AI Workspace

Status: this vision document was written before implementation began and is kept as originally written (see [README.md](README.md) for why). The thesis and guiding principles below have held up through implementation without revision — see [implementation/10-v2-progress.md](implementation/10-v2-progress.md) for what has actually shipped against this vision (through Phase 5B: meetings, documents, workspace chat/search, and the Student Toolkit) and [implementation/03-decisions.md](implementation/03-decisions.md) for where reality required a decision this document left open.

## From meeting assistant to workspace

V1 shipped a complete, working product: record or import a meeting, transcribe it on-device, get an AI summary and Minutes of Meeting, ask questions about your own meetings, search, export, lock, back up — all with zero data ever leaving the device.

V2 does not replace any of that. It generalizes the same pattern that already works for meetings — capture content, process it on-device, make it searchable and askable — to more content types, and adds a way to talk to all of it at once.

Meetings become **one module** in a workspace that also handles documents, notes, and a knowledge base spanning everything the user has put into the app.

## The thesis

Every serious "AI second brain" product on the market today — Notion AI, Mem, Rewind, NotebookLM, and the cloud-hosted meeting tools OfflineMoMAI already competes with — does its AI work in the cloud. That means: the content you're organizing your private life or your organization's confidential information around is, at some point, sent to someone else's server. Retention policies vary, training-data policies vary, and in regulated fields (legal, healthcare, journalism, government, defense-adjacent research) sending that content off-device may simply not be allowed at all, independent of how good the tool is.

OfflineMoMAI's structural claim — verified at the architecture level, not just asserted in a privacy policy — is that there is exactly one network-capable edge in the entire system: the one-time AI model download on first use. Everything after that, forever, runs locally. V2's job is to extend that same guarantee to a much larger surface area (documents, cross-content chat, a knowledge base) without weakening it anywhere.

## What "workspace" means concretely

A user should be able to:

- Record a meeting or import an existing recording (already shipped).
- Import a PDF, a Word document, a Markdown file, or a plain text file, and have it become searchable and askable the same way a meeting transcript already is.
- Ask a free-form question and get an answer synthesized from *everything relevant they've put into the app* — not just one meeting at a time, and not just meetings.
- Search across meetings, documents, and notes from one place.
- Have a general offline AI conversation that isn't tied to any one piece of content, when they just want to think something through with an assistant that has no internet access to leak to.
- Trust, without having to think about it, that none of this ever leaves their device except the one-time model download.

## Guiding principles for V2

1. **Reuse before rebuild.** Meetings already prove out the pattern (import → process → store → status machine → retrieve). Documents should follow the same shape, not invent a parallel one. See [10-system-architecture.md](10-system-architecture.md) for the explicit reuse mapping.
2. **Don't touch what already works.** The Clean Architecture layering, the Riverpod composition root, the repository pattern, the shared-engine timeout/cancellation discipline — all proven in production use this session (the `flutter_llama` → `llamadart` swap cost one provider re-point specifically because of this discipline) — carry forward unchanged.
3. **Privacy is an architectural constraint on every new module, not a checkbox on the last one.** Any new feature that would require even one additional network call for anything other than a one-time model asset download does not ship as designed. See [17-privacy.md](17-privacy.md).
4. **Small, honest steps over an all-at-once rewrite.** The single largest technical bet in V2 — real retrieval (chunking + on-device embeddings + vector search, see [14-rag-architecture.md](14-rag-architecture.md)) — is unproven in this codebase today. It gets a validation spike before it gets a commitment, the same discipline that caught `flutter_llama`'s broken build early in V1 rather than late.
5. **Existing hard constraints stay hard unless explicitly revisited.** No accounts, no login, no cloud sync, no backend — restated from V1's executive summary as still true by default. The one place this is deliberately reopened for discussion, not silently overridden, is monetization — see [18-subscription-model.md](18-subscription-model.md).

## What V2 is not

- Not a rewrite. Not a new architecture. Not a reason to touch the meeting pipeline, the database schema for existing tables, or the AI reliability/timeout machinery that already works.
- Not a cloud product with an offline mode bolted on. If a feature can't be built entirely on-device, it doesn't ship in V2 as specified — it goes on the future-scope list ([20-future-roadmap.md](20-future-roadmap.md)) for explicit reconsideration later.
- Not a reintroduction of the Conversation Translator. That feature was removed deliberately after real-device testing showed the on-device model's translation quality wasn't reliable enough — nothing in this vision revisits that call.
