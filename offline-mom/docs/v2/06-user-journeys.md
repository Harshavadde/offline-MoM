# V2 User Journeys

Concrete, step-by-step flows through the new modules, written against the existing app's real navigation/screen patterns (see V1's `docs/architecture/navigation-flow.md` for the current route graph this extends). These are illustrative specifications, not final UI designs.

## Journey 1: Import a document and chat with it

1. From Home (or a new "Import document" entry point alongside the existing "Record"/"Import audio" actions), the user picks a PDF, DOCX, TXT, or Markdown file via the system file picker — same mechanism as today's audio import.
2. A new `Document` row is created with status `created`, then `extracting` while text is pulled out of the file (see [10-system-architecture.md](10-system-architecture.md) for the per-format extraction approach) — mirroring the existing `Meeting.status` state machine exactly.
3. Once extraction succeeds, the document is chunked and embedded in the background (status `indexing`), then `ready` — an additional sub-stage `Meeting`s don't have today, because retrieval indexing is new to V2 (see [14-rag-architecture.md](14-rag-architecture.md)).
4. The user opens the document's detail screen (mirroring `MeetingDetailsScreen`'s tabbed layout): Original text / Summary / Chat-with-this-document.
5. In the Chat tab, the user asks a question scoped to just this document. The answer is generated using only this document's chunks as context — the same "answer only from what's actually here" discipline Ask AI already uses for meetings.

**Failure path**: if extraction fails (corrupted file, unsupported encoding, password-protected PDF), the document enters `error` with a specific `errorMessage`, shown via the same `AiPipelineFallback`-style widget already used for meeting failures, with a Retry action — no new failure-UX pattern invented.

## Journey 2: Ask a cross-content question

1. From the workspace-wide Chat entry point (not scoped to any one meeting or document), the user asks: *"What did we agree on pricing across the client calls and the contract PDF?"*
2. The retrieval layer scores chunks across all `ready` meetings and documents (see [14-rag-architecture.md](14-rag-architecture.md)), selects the most relevant handful regardless of which module they came from, and assembles them into context.
3. The LLM answers using only that retrieved context — same "never the model's general knowledge" discipline as today's Ask AI — and the answer is shown with source references (e.g. "From: Client Call — March 4, and Service Agreement.pdf") so the user can open the original and verify, extending the existing "always show the transcript alongside the summary" trust pattern to a multi-source answer.
4. If nothing relevant is found, a plain "couldn't find anything about that" response is returned rather than a guess — the same fallback behavior `AskAboutMeetingsUseCase` already has today.

## Journey 3: General offline chat

1. The user opens a chat surface with no content scoping at all — just talking to the on-device model directly, the way they might use any chat assistant, except with zero network access beyond having already downloaded the model once.
2. This reuses the exact same LLM engine, request-queue, and timeout machinery as every other AI feature (see [11-ai-architecture.md](11-ai-architecture.md)) — it is not a separate model or a separate code path, just a different (empty) context.
3. Conversations are saved locally as chat history (a new capability — unlike the old Conversation Translator's deliberate never-persist design, a general chat thread is the user's own thinking, not someone else's spoken words, so persisting it locally is the right default; see [12-database-design.md](12-database-design.md) and [17-privacy.md](17-privacy.md) for why this is treated differently).

## Journey 4: Search across everything

1. From the existing Search screen, the user types a query. Today this searches meeting titles, transcripts, and action items; V2 extends it to also cover summaries, notes, and documents (closing a gap that exists even for meetings-only search today — see [13-search-architecture.md](13-search-architecture.md)).
2. Results are grouped or tagged by content type (meeting / document / note) so the user always knows what they're looking at, reusing the existing `MeetingListTile`-style list pattern generalized to a mixed-content result list.
3. Tapping a result opens that content's own detail screen — no new navigation concept, just more destination types feeding into the same "search result → detail screen" flow that already exists.

## Journey 5: Building a knowledge base over time

1. Over a semester or project, the user accumulates meetings and documents without any special "organize this" action — the knowledge base is not a separate thing the user builds, it is what naturally exists once content is imported (consistent with V1's principle of no manual organizational ceremony — no folders, no tags to maintain, matching the existing app's flat, chronological meeting list philosophy).
2. Later, a single chat question (Journey 2) or search (Journey 4) surfaces relevant content from across that entire history without the user needing to remember where or when they put it in.
3. Deleting a meeting or document removes it and everything derived from it (chunks, embeddings) from the knowledge base immediately and completely — extending the existing FK-cascade-delete guarantee (`ON DELETE CASCADE`) to the new tables.
