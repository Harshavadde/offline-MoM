# V2 Product Requirements Document

See [01-product-vision.md](01-product-vision.md) for the strategic framing and [02-market-positioning.md](02-market-positioning.md) for competitive context. This document specifies *what* V2 builds. See [08-functional-requirements.md](08-functional-requirements.md) for the atomic, traceable requirement list.

## Modules

V2 is organized into five modules. Four already exist in some form; one is new. None of this requires a new top-level architecture — see [10-system-architecture.md](10-system-architecture.md) for how each module maps onto the existing Clean Architecture / feature-first structure.

| Module | Status | Description |
|---|---|---|
| **Meetings** | Existing, unchanged | Record/import, transcribe, summarize. Becomes one content type among several rather than the whole product. |
| **Documents** | New | Import PDF/DOCX/TXT/Markdown, extract text, make it summarizable/searchable/askable the same way a meeting transcript already is. |
| **Offline AI Chat** | New (generalizes existing Ask AI) | Two surfaces: chat scoped to the workspace (meetings + documents + notes, retrieval-backed) and general-purpose offline chat with no content scoping. |
| **Workspace Search** | Evolved | Existing search (meetings, transcripts, action items) extended to cover documents and notes — a gap that exists even for meetings alone today — and moved from substring `LIKE` scanning to FTS5. See [13-search-architecture.md](13-search-architecture.md). |
| **Knowledge Base** | New (organizing layer) | Not a separate screen so much as a property of the other four modules working together: everything imported or recorded becomes part of one retrievable corpus, with the chunking/embedding infrastructure in [14-rag-architecture.md](14-rag-architecture.md) as its technical foundation. |

## User stories

Numbered to continue from where V1's PRD left off (US-1 through US-17 already exist and are unchanged).

| # | As a... | I want to... | So that... |
|---|---|---|---|
| US-18 | user | import a PDF, Word document, Markdown file, or text file | I can bring existing knowledge into the app the same way I already bring in audio |
| US-19 | user | see extracted text and a summary for an imported document | I get the same at-a-glance value I already get from a meeting summary |
| US-20 | user | ask a question and get an answer drawn from across all my meetings and documents, not just one at a time | I can actually use the app as a knowledge base, not a per-meeting tool |
| US-21 | user | see which meeting or document an AI answer's information came from | I can verify the answer myself instead of trusting it blindly, consistent with the app's existing "always show the transcript" trust pattern |
| US-22 | user | start a general offline chat that isn't tied to any specific meeting or document | I can think something through with an assistant, privately, without needing to have "content" to ask about first |
| US-23 | user | search across meetings, documents, and notes from one search screen | I don't have to remember which module something lives in to find it |
| US-24 | user | see my past chat conversations again later | I can pick up a line of thinking I had with the assistant, the same way I can reopen an old meeting |
| US-25 | user | delete a document (and everything derived from it: extracted text, chunks, embeddings) | my data doesn't accumulate forever, the same guarantee I already have for meetings |

## Explicit reuse mapping

This is the section that keeps V2 honest about "reuse before rebuild":

| New capability | Existing pattern it reuses |
|---|---|
| Document import (pick file → process → store) | `ImportController` / `AudioImportService` pattern from audio import — same `Notifier`-based sealed-state controller shape (`Idle/Processing/Succeeded/Failed`) |
| Document processing state machine (extracting → ready/error) | `MeetingStatus` enum pattern (`created → downloadingModel → transcribing → ... → ready/error`) |
| Document repository | `MeetingRepository`/`TranscriptRepository` shape: interface + single `Sqflite*` implementation, injected at the composition root |
| Chat failure/retry UI | `AiPipelineFallback` widget's existing states (loading/downloading-model/error-with-retry) |
| Chat generation timeout | The existing 45-second stall timeout + `cancelGeneration()` pattern in the shared LLM engine — applied to chat the same way it already applies to summarization and Ask AI |
| Document/chat model download UX | The existing onboarding model-download screen's multi-select-and-progress pattern (just shipped for Whisper model sizes) |
| Search across new content types | `SearchMeetingsUseCase`'s fan-out-and-union pattern, extended with new repository query methods, evolving to FTS5 |

## Explicitly out of scope for V2

Restated from V1, still true unless [18-subscription-model.md](18-subscription-model.md) is explicitly adopted: cloud sync, accounts/login, a backend server of any kind, third-party integrations (Zoom/Teams/Meet/WhatsApp), an enterprise admin dashboard. Also out of scope: reintroducing the Conversation Translator (removed deliberately for quality reasons — not revisited here) and AI-extracted action items/decisions (already deferred in V1's own future-scope list, conditioned on a future larger model — V2 does not resolve that condition by itself, though a larger default model is one of the levers under discussion in [11-ai-architecture.md](11-ai-architecture.md)).

## Success criteria

V2 is successful if, for a real user with a real backlog of meetings and documents:

1. They can import a document as easily as they can import an audio file today.
2. A question like "what did we decide about X across my last three meetings and that contract PDF" gets a real, source-cited answer — not a "couldn't find an answer" that a working RAG system would have handled.
3. Search finds a note, a document, and a meeting transcript from one query, instantly, without the user knowing or caring which module the content lives in.
4. None of the above requires them to create an account, agree to data leaving their device, or pay a recurring fee (unless [18-subscription-model.md](18-subscription-model.md)'s recommended one-time-purchase model is adopted, in which case: without a subscription).
