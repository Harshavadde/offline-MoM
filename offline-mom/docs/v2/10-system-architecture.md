# V2 System Architecture

Status: this document was written before implementation began and is kept as originally written (see [README.md](README.md) for why); the foundation it describes below held up unchanged through implementation. See [implementation/12-architecture-diagrams.md](implementation/12-architecture-diagrams.md) for as-built Mermaid diagrams (module dependencies, clean-architecture layers, data flow) generated from the real code, and [implementation/10-v2-progress.md](implementation/10-v2-progress.md) for what's shipped.

## Unchanged foundation

V2 keeps every architectural decision V1's `docs/architecture/hld.md` and `lld.md` already made and justified:

- Clean Architecture (presentation / domain-as-use-cases / data) + MVVM via Riverpod.
- A single composition root (`lib/providers/app_providers.dart`) — every repository, service, and use-case provider for the new modules is wired there too, not scattered.
- Feature-first folders under `lib/features/`.
- Use cases exist only for real multi-repository/service orchestration; simple CRUD stays inline in a provider — the "no ceremony" rule.
- Repository pattern: interface + single concrete implementation, injected by interface type.
- One shared, timeout-guarded AI engine layer (`lib/services/ai/`) — extended, not replaced.

This is a deliberate decision, not an oversight: the same layering already survived one real backend swap (`flutter_llama` → `llamadart`) at the cost of re-pointing a single provider. There is no architectural reason to change it for V2, and every risk in this document assumes it stays in place.

## New feature modules

Following the existing `lib/features/<name>/` convention:

```
lib/features/
  documents/                  (new)
    presentation/{screens,providers}
    document_import_use_case.dart       (mirrors ImportController's orchestration)
    extract_document_text_use_case.dart (mirrors TranscribeMeetingUseCase)
    summarize_document_use_case.dart    (mirrors GenerateMeetingSummaryUseCase)
  chat/                        (new)
    presentation/{screens,providers}
    workspace_chat_use_case.dart        (generalizes ask/ask_about_meetings_use_case.dart)
    general_chat_use_case.dart          (new, no content scoping)
  ask/                         (existing, evolves)
    ask_about_meetings_use_case.dart -> becomes a thin meeting-only entry point into chat/,
    or is retired in favor of chat/'s workspace-scoped mode — an implementation decision for
    Phase 1, not resolved here; either way the module boundary between "meetings" and "asking
    questions about content" already exists today and V2 only needs to widen it.
  search/                      (existing, evolves)
    search_meetings_use_case.dart -> search_workspace_use_case.dart, extended to documents/notes
```

There is no new top-level "Knowledge Base" feature folder — per [03-prd.md](03-prd.md), the knowledge base is a property of Documents + Meetings + the retrieval layer working together, not a screen of its own. Its only dedicated code is the cross-cutting retrieval service described below.

## New cross-cutting services (`lib/services/`)

| Service | Responsibility | Mirrors |
|---|---|---|
| `services/documents/document_text_extraction_service.dart` (+ per-format implementations: PDF, DOCX, plain text/Markdown) | Turn an imported file into plain text | `WhisperSpeechToTextEngine` (interface + native-backed implementation) |
| `services/ai/embedding_engine.dart` (interface) + one implementation | Turn a chunk of text into a vector | `SpeechToTextEngine`/`LlmEngine` interface pattern |
| `services/retrieval/chunking_service.dart` | Split long text into retrieval-sized chunks | New; see [14-rag-architecture.md](14-rag-architecture.md) |
| `services/retrieval/vector_store.dart` (interface) + one implementation | Store and query chunk embeddings | New; see [14-rag-architecture.md](14-rag-architecture.md) |
| `services/ai/llm_request_queue.dart` | Serialize/queue concurrent calls to the shared LLM engine explicitly | New; closes the gap described in [11-ai-architecture.md](11-ai-architecture.md) |

Every one of these follows the existing convention: an abstract interface consumed by use cases/providers, a concrete implementation wired at the composition root, swappable the same way `flutter_llama` was swapped for `llamadart` without touching a screen.

## Component diagram (textual)

```
                         ┌─────────────────────────────┐
                         │   Presentation (screens)     │
                         │  Meetings / Documents / Chat  │
                         │      / Search / Settings      │
                         └───────────────┬───────────────┘
                                         │ Riverpod providers
                         ┌───────────────┴───────────────┐
                         │      Use cases (orchestration)  │
                         │  Process*, Extract*, Summarize*, │
                         │  WorkspaceChat, GeneralChat,     │
                         │  SearchWorkspace                 │
                         └───────┬───────────────┬─────────┘
                                 │               │
                 ┌───────────────┘               └───────────────┐
                 │                                                │
     ┌───────────┴───────────┐                       ┌────────────┴────────────┐
     │      Repositories       │                       │      AI/Retrieval        │
     │ Meeting/Document/Chat/  │                       │ SpeechToTextEngine        │
     │ Note/... (sqflite)      │                       │ LlmEngine (shared,        │
     │ Settings (Hive)         │                       │   queued via              │
     └───────────┬───────────┘                       │   LlmRequestQueue)         │
                 │                                     │ EmbeddingEngine            │
                 │                                     │ ChunkingService            │
                 │                                     │ VectorStore                │
                 │                                     └────────────┬────────────┘
                 │                                                  │
                 └───────────────────┬──────────────────────────────┘
                                     │
                         ┌───────────┴───────────┐
                         │   SQLite (app-private)  │
                         │  + Hive (settings)       │
                         │  + local file storage    │
                         │    (audio, documents)    │
                         └───────────────────────────┘

  Only network-capable edge in the entire diagram: AI model download (Hugging Face),
  triggered once per model, cached thereafter. No other component ever initiates a
  network call.
```

## Reuse mapping (component-level)

| Existing V1 component | V2 role |
|---|---|
| `MeetingStatus` state-machine pattern | Template for `DocumentStatus` |
| `ImportController` / `AudioImportService` | Template for `DocumentImportController` / per-format extraction services |
| `AiPipelineFallback` widget | Reused as-is for document processing and chat failure/loading states |
| `LlmTimeoutException` / `cancelGeneration()` | Reused as-is for every new LLM call site (document summary, document chat, workspace chat, general chat) |
| `AskAboutMeetingsUseCase`'s "answer only from provided context, plain fallback if nothing found" discipline | Carried forward into `WorkspaceChatUseCase`, now backed by real retrieval instead of keyword overlap |
| `SearchMeetingsUseCase`'s fan-out-and-union pattern | Evolves into `SearchWorkspaceUseCase`, backed by FTS5 instead of `LIKE` |
| Single composition root | Every new provider/service above is registered there, no exceptions |
| Onboarding's multi-model-download screen (just shipped for Whisper sizes) | Template for offering an optional embedding-model or larger-LLM-tier download in Settings |

## What does not change

The recording pipeline, the transcription pipeline (short of the shared queue in NFR-11), the existing seven database tables' existing columns, the existing repositories' existing methods, the app's navigation shell (`AppShell`), the settings screens, backup/export, and app lock are all out of scope for structural change in V2. New modules are added alongside them, not through them.
