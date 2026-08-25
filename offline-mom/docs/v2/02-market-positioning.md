# V2 Market Positioning

## The category

"Private, offline, AI-assisted knowledge workspace" — a category that today is served either by cloud AI note/knowledge tools that are not actually private, or by local-LLM enthusiast tooling that is private but not a consumer product. OfflineMoMAI V2 aims at the gap between those two.

## Competitive landscape

| Product | AI location | Offline capable | Accounts required | Recurring cost | Meeting capture | Document chat | Notes |
|---|---|---|---|---|---|---|---|
| Otter.ai, Fireflies.ai | Cloud | No | Yes | Yes (per-minute/subscription) | Yes | No | Direct V1 competitors; audio leaves the device by design. |
| Cloud Zoom/Teams/Meet transcription | Cloud | No | Yes (platform account) | Bundled into platform cost | Yes | No | Not a standalone product; tied to a specific meeting platform. |
| Notion AI, Mem | Cloud | No | Yes | Yes (subscription) | No (notes-first) | Yes | Closest analog to the "workspace" vision, but every AI call is a network call. |
| Google NotebookLM | Cloud | No | Yes (Google account) | Free tier + paid | No | Yes | Strong "chat with your documents" UX; the product this space benchmarks against for RAG quality — fully cloud-side. |
| Rewind.ai | Local capture, cloud AI for some features | Partial | Yes | Yes (subscription) | Some | Some | Markets "privacy" but AI processing/sync is not fully local; a useful cautionary example of privacy-as-marketing vs. privacy-as-architecture. |
| LM Studio, GPT4All, Ollama + a UI | Local | Yes | No | No | No | Manual/DIY | Proves offline LLM chat is technically viable on consumer hardware, but these are developer tools, not a meeting-capture-plus-knowledge-base consumer product. |
| **OfflineMoMAI V2 (proposed)** | **100% on-device** | **Yes, after one-time model download** | **No** | **No recurring cost by default (see [18-subscription-model.md](18-subscription-model.md))** | **Yes** | **Yes (new)** | Only entry in this table that is simultaneously a polished consumer product *and* structurally offline for every AI operation. |

## Why "privacy-as-architecture" beats "privacy-as-policy"

Most competitors that market privacy do so as a policy commitment — a promise about what they *won't* do with data that is nonetheless transmitted to their servers. OfflineMoMAI's claim is different in kind: there is exactly one network-capable code path in the entire application (the one-time AI model download), verifiable by reading the deployment architecture rather than trusting a policy document. This is a harder claim to make and a much stronger one to defend, including to procurement/compliance teams at organizations where "we promise not to look" is not sufficient and "the software is architecturally incapable of transmitting your data" is.

## Target segments (extending V1's personas)

V1 already validated: students, teachers, developers, small team leads, researchers. V2's document + knowledge-base capability opens segments for whom cloud AI tools are not merely undesirable but often **contractually or legally prohibited**:

- **Legal professionals** — client confidentiality (privilege) makes cloud transcription/summarization of case discussions a genuine liability, not just a preference.
- **Healthcare practitioners** — patient-related notes/meetings face regulatory constraints (even without claiming formal compliance certification — see [16-security.md](16-security.md)) that a zero-transmission architecture is structurally well-suited to.
- **Journalists** — source protection is incompatible with any tool that sends recordings or notes to a third-party server, cloud AI included.
- **Independent consultants/freelancers** — juggle client meetings, contracts (documents), and their own notes across multiple confidential engagements; a workspace that unifies these without a subscription or account is a direct cost and trust win over cloud "second brain" tools.

## Positioning statement

*OfflineMoMAI is the private workspace for people and professions who cannot — or simply refuse to — send their meetings, documents, and notes to someone else's server, without giving up the AI assistance that makes those meetings, documents, and notes actually useful.*

## Addendum (Phase 5A/5B, not in this document's original scope): Student Toolkit competitive set

The Student Toolkit (Image Tools/Scanner/PDF Tools) competes in a second, largely separate category this document's original table doesn't cover: on-device document utilities (Adobe Scan, Microsoft Lens, CamScanner, SmallPDF, iLovePDF). Recorded here rather than added to the table above (which is scoped to the meeting/knowledge-workspace category) since the comparison axes are different — those products compete on scan quality and PDF-editing breadth, not on the privacy-as-architecture claim that's this document's actual thesis. OfflineMoMAI's honest differentiator in *this* category specifically is that scanning/compressing/merging never uploads a file anywhere (several named competitors process at least some operations server-side, e.g. cloud-based compression tiers), at the cost of not yet matching their PDF-editing breadth (true text-preserving edits, OCR) — see ADR-034's disclosed rasterize-and-rebuild trade-off, `docs/v2/implementation/03-decisions.md`. A full competitive table for this category (feature-by-feature against Adobe Scan/CamScanner/SmallPDF) is not built out here — worth doing if/when the Toolkit becomes a primary (not secondary) part of the product's marketing positioning, per [20-future-roadmap.md](20-future-roadmap.md)'s student-first-launch note.

## What this positioning requires of the roadmap

Every V2 feature decision should be checked against this positioning before it's checked against anything else: does it require a new network call for anything beyond the existing one-time model download? If yes, it does not ship as specified in this document set — see the constraint restated throughout [01-product-vision.md](01-product-vision.md), [14-rag-architecture.md](14-rag-architecture.md) (embeddings must be computed on-device, not via a cloud embedding API), and [17-privacy.md](17-privacy.md).
