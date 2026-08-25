# V2 Functional Requirements

Continues V1's `docs/03-srs.md` numbering (FR-1 through FR-21 already exist and are unchanged). Each requirement below names the planned component that satisfies it, in the same traceability style V1 uses — pointing at *planned* locations (see [10-system-architecture.md](10-system-architecture.md)) rather than shipped code, since none of this is implemented yet.

## Documents module

- **FR-22**: The system shall let a user import a PDF, DOCX, TXT, or Markdown file via the system file picker. *(`DocumentImportController`, mirroring `ImportController`)*
- **FR-23**: The system shall extract plain text from an imported document, tracked through a status state machine (`created → extracting → indexing → ready`, or `error`). *(`DocumentTextExtractionService`, per-format; `Document.status`, mirroring `MeetingStatus`)*
- **FR-24**: The system shall persist the original imported file alongside its extracted text, so the user can always open the source document, not just its extracted text. *(`DocumentRepository`; see [15-storage-architecture.md](15-storage-architecture.md))*
- **FR-25**: On extraction failure (corrupted file, unsupported encoding, password-protected PDF), the system shall set the document to an `error` status with a specific, human-readable message and allow retry without re-importing. *(mirrors `Meeting.errorMessage` + `RetryMeetingProcessingUseCase`)*
- **FR-26**: The system shall let a user delete a document, which shall remove the original file, extracted text, and all derived chunks/embeddings immediately and completely. *(`ON DELETE CASCADE`, mirroring the existing meeting-delete guarantee)*
- **FR-27**: The system shall generate a summary for an imported document, reusing the same on-device LLM and summarization prompt contract used for meetings (adapted for document-length content — see [11-ai-architecture.md](11-ai-architecture.md)).

## Offline AI Chat module

- **FR-28**: The system shall let a user ask a free-form question scoped to a single document, answered using only that document's content. *(mirrors `AskAboutMeetingsUseCase`, generalized to `Document`)*
- **FR-29**: The system shall let a user ask a free-form question scoped across all `ready` meetings and documents, answered using retrieval-selected context from whichever sources are actually relevant. *(new `WorkspaceChatUseCase`, see [14-rag-architecture.md](14-rag-architecture.md))*
- **FR-30**: Every cross-content answer shall cite which meeting(s)/document(s) it drew from, allowing the user to open and verify the source. *(extends the existing "show the transcript alongside the AI summary" trust pattern)*
- **FR-31**: The system shall let a user start a general offline chat with no content scoping. *(new `GeneralChatUseCase`, same LLM engine, empty retrieval context)*
- **FR-32**: The system shall persist chat conversations locally (both workspace-scoped and general) so a user can reopen a past conversation. *(new `ChatSession`/`ChatMessage` tables — see [12-database-design.md](12-database-design.md))*
- **FR-33**: The system shall let a user delete a chat conversation, removing all its messages immediately. *(`ON DELETE CASCADE`, same pattern as every other deletable entity)*
- **FR-34**: If no relevant content is found for a workspace-scoped question, the system shall say so plainly rather than guessing from the model's general knowledge. *(existing fallback-string behavior in `AskAboutMeetingsUseCase`, carried forward)*
- **FR-35**: Every chat generation call shall be bounded by the same stall-timeout/cancellation mechanism already applied to meeting summarization. *(existing `LlmTimeoutException` / `cancelGeneration()` machinery in the shared engine)*

## Workspace Search module

- **FR-36**: The system shall search meeting titles, transcripts, summaries, action items, and notes — a superset of what's searched today (summaries and notes are not currently searched at all). *(evolves `SearchMeetingsUseCase`)*
- **FR-37**: The system shall search document titles and extracted text. *(new repository method, same pattern as existing text-search methods)*
- **FR-38**: Search results shall indicate which content type (meeting, document, note) each result is, in a single unified result list. *(evolves the existing meeting-only search results screen)*
- **FR-39**: Search shall use SQLite FTS5 rather than substring (`LIKE`) matching. *(see [13-search-architecture.md](13-search-architecture.md))*

## Knowledge Base (cross-cutting)

- **FR-40**: Every piece of ready content (meeting transcript, document text) shall be chunked and embedded automatically in the background once processing completes, with no separate "add to knowledge base" action required from the user. *(new background indexing step, part of each content type's own processing pipeline)*
- **FR-41**: The system shall never send content, or any derived representation of content (embeddings included), to any network destination. *(architectural constraint, verified at the design level in [14-rag-architecture.md](14-rag-architecture.md) and [17-privacy.md](17-privacy.md), not just stated as policy)*
