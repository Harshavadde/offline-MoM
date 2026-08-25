# V2 Software Requirements Specification

Companion to [03-prd.md](03-prd.md) (product narrative) and structured the same way V1's `docs/03-srs.md` is: this document defines scope, interfaces, and constraints; the atomic numbered requirements live in [08-functional-requirements.md](08-functional-requirements.md) (FR) and [09-non-functional-requirements.md](09-non-functional-requirements.md) (NFR) so they can be traced independently of narrative changes here.

## Scope

V2 adds Documents, Offline AI Chat, and evolved Workspace Search to the existing, unchanged Meetings module. It does not modify the meeting recording/import/transcription/summarization pipeline, the existing database tables, or the app's authentication-free, account-free design.

## System overview

Same single-artifact deployment as V1: one Android APK/AAB, no server, one network-capable path (one-time model downloads — now potentially including an embedding model, see [11-ai-architecture.md](11-ai-architecture.md)). V2 does not introduce a second deployable component of any kind.

## External interfaces

- **Document input**: Android's system file picker (`file_picker`, already a dependency), extended to accept `.pdf`, `.docx`, `.txt`, `.md` in addition to the existing audio/video allow-list.
- **AI model sources**: Hugging Face, as today, for any additional model (e.g., an embedding model) required by [14-rag-architecture.md](14-rag-architecture.md).
- **No new external interfaces of any other kind** — no APIs, no OAuth, no push notifications beyond the existing foreground-service download notification.

## Constraints

- Android-only, same as V1 (iOS remains a scope decision, not a technical blocker — see V1's `06-risk-and-future-scope.md`, restated in [20-future-roadmap.md](20-future-roadmap.md)).
- No cloud services of any kind, including for embeddings — this is a harder version of V1's existing "no cloud" constraint, since RAG systems in general very commonly *do* call a cloud embedding API even when the chat model itself is local. V2 explicitly rules that pattern out.
- Every new AI-backed feature must integrate with the single shared LLM engine and its existing timeout/cancellation discipline (45-second stall timeout, `cancelGeneration()` on expiry) rather than inventing a parallel mechanism.
- Must not require the LLM's context window to be treated as unbounded. The model's practical context is 2048 tokens; every new prompt contract (chat, RAG context assembly) must be designed within that limit until/unless the default model changes (see [11-ai-architecture.md](11-ai-architecture.md)).

## Assumptions

- Users importing documents are importing their own content (contracts, notes, PDFs they have rights to), the same trust assumption V1 already makes about imported audio/video.
- A typical user's total corpus (meetings + documents combined) is realistically in the tens-to-low-thousands of items for the lifetime of the app on one device — this shapes the retrieval design in [14-rag-architecture.md](14-rag-architecture.md), which is scoped for personal/small-team scale, not enterprise-scale corpora.
- Device storage is sufficient for both the existing ~1.25GB of AI models and whatever the user chooses to import — the existing Storage settings screen's usage/clear-cache pattern extends to cover this rather than needing new UX invented from scratch.

## Requirement traceability

Every FR/NFR in [08-functional-requirements.md](08-functional-requirements.md) and [09-non-functional-requirements.md](09-non-functional-requirements.md) is tagged by module (Meetings/Documents/Chat/Search/Knowledge Base) and, where applicable, points at the existing V1 component it reuses or extends — following the same implementation-location-pointer convention V1's SRS already uses for its own FR-1 through FR-21.
