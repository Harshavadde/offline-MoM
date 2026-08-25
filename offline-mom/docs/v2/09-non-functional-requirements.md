# V2 Non-Functional Requirements

Continues V1's `docs/03-srs.md` NFR numbering (NFR-1 through NFR-9 already exist and are unchanged — notably NFR-9, the bounded-latency/reliability requirement, which V2 extends rather than replaces).

## Reliability

- **NFR-10**: No AI operation introduced by V2 (document summarization, document chat, workspace chat, general chat, embedding generation) shall be able to hang indefinitely — every such call shall fail with a clear, retryable error after a bounded time, using the existing 45-second stall-timeout mechanism rather than a newly invented one. Extends NFR-9 to the new call sites instead of duplicating its logic.
- **NFR-11**: Because all LLM-backed features (meeting summarization, Ask AI, document chat, workspace chat, general chat) share one serialized on-device engine, the system shall queue concurrent requests explicitly (see [11-ai-architecture.md](11-ai-architecture.md)) rather than allowing a second concurrent call to fail outright — closing a gap that exists in the current implementation, where the documented assumption of graceful queuing does not match the underlying library's actual behavior.
- **NFR-12**: Document extraction failures (malformed PDF, unsupported DOCX variant, unreadable encoding) shall never crash the app or leave a `Document` row in an ambiguous state — every failure path resolves to a clear `error` status with a retry option, mirroring NFR from the existing meeting pipeline.

## Performance

- **NFR-13**: A workspace-scoped chat query shall not require a linear-time sequential database fetch per item in the user's entire content history before returning an answer — the current Ask AI implementation does exactly this (an O(N) fetch, done twice, for every question) and must not be the pattern V2's retrieval layer inherits. See [14-rag-architecture.md](14-rag-architecture.md).
- **NFR-14**: Search queries shall use indexed lookups (FTS5) rather than full-table substring scans, so search latency does not grow linearly (and, for leading-wildcard `LIKE` queries, effectively worse than linearly) with total transcript/document text volume.
- **NFR-15**: Document import (file pick through to `ready` status) shall report progress to the user for any step expected to take more than a couple of seconds (extraction, embedding), consistent with the existing progress-reporting standard already applied to model downloads and, most recently, to per-model download progress in onboarding.

## Scalability

- **NFR-16**: The retrieval and search design shall remain usable (sub-second search, chat answers returned within the existing generation-timeout budget) at a realistic personal/small-team corpus size — hundreds to low thousands of meetings and documents accumulated over the lifetime of the app on one device. Enterprise-scale corpora are explicitly out of scope for V2 (see [04-srs.md](04-srs.md) assumptions).

## Privacy

- **NFR-17**: No new feature introduced by V2 shall add a network-capable code path other than the existing one-time AI model download mechanism (potentially extended to one additional embedding-model download). This is the single hardest constraint in this entire document and is verified architecturally in [10-system-architecture.md](10-system-architecture.md) and [17-privacy.md](17-privacy.md), not merely asserted in a policy document.
- **NFR-18**: Chat history (workspace-scoped and general) shall be stored locally only, deletable by the user with the same immediacy and completeness as every other user-generated content type in the app.

## Security

- **NFR-19**: Document parsing (PDF/DOCX text extraction) shall rely on well-maintained upstream libraries for the actual format parsing, the same way the existing pipeline relies on ffmpeg/whisper.cpp for audio rather than hand-rolling format parsing in application code — untrusted file parsing is a real attack surface and should not be reinvented. See [16-security.md](16-security.md).

## Maintainability

- **NFR-20**: Every new module (Documents, Chat) shall follow the existing feature-first folder structure, the existing "use cases only for real multi-repository orchestration" discipline, and the existing single-composition-root dependency injection pattern — no new architectural style is introduced for V2. See [10-system-architecture.md](10-system-architecture.md).
- **NFR-21**: Any file implementing the LLM request queue (NFR-11) shall carry the same "handle with care, read the architecture doc first" warning comment convention the developer guide already applies to `llamadart_llm_engine.dart` — this is now the second most load-bearing file in the codebase and should be flagged as such for future maintainers.

## Compatibility

- **NFR-22**: V2 shall not require any change to the existing `meetings`, `transcripts`, `summaries`, `action_items`, `decisions`, `recording_marks`, or `notes` tables' existing columns — new tables and, where unavoidable, new columns (additive only) are the only permitted schema changes. See [12-database-design.md](12-database-design.md).
