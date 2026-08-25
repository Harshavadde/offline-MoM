# Product Requirements Document (PRD)

## Product

OfflineMoMAI — a fully offline Android meeting assistant. See [`01-executive-summary.md`](01-executive-summary.md) for problem/objectives/scope.

## Personas

| Persona | Need |
|---|---|
| **Student** | Record a lecture/group project meeting, get a searchable transcript and action items without paying for a transcription service |
| **Teacher** | Keep a private record of parent/staff meetings without sending audio to a third party |
| **Developer** | Record a standup/design review, get action items without manual note-taking |
| **Small team lead** | Distribute a formal MoM as a PDF after every meeting, with zero recurring cost |
| **Researcher** | Transcribe interview recordings without an internet-dependent, per-minute-billed service |
| **Traveler** | Communicate with a local who speaks a different Indian language, with no internet connection, using the Conversation Translator |

## User Stories

| # | As a... | I want to... | So that... | Status |
|---|---|---|---|---|
| US-1 | user | record a live meeting with pause/resume/stop | I can capture a conversation as it happens | Done |
| US-2 | user | rename a meeting after recording | my meeting list stays organized | Done |
| US-3 | user | import an existing audio or video file | I can process a meeting I recorded elsewhere | Done |
| US-4 | user | have video files automatically have their audio extracted | I don't need a separate video-to-audio tool | Done |
| US-5 | user | get a full transcript automatically | I don't have to type it myself | Done |
| US-6 | user | get an AI-generated summary and Minutes of Meeting | I don't have to read the whole transcript to know what happened | Done |
| US-7 | user | add and check off action items manually | I can track what needs doing, in my own words | Done (was AI-extracted; changed — see below) |
| US-8 | user | ~~see extracted decisions~~ | ~~I have a record of what was agreed~~ | Removed — see below |
| US-9 | user | search my meetings by name, transcript content, action items, or date | I can find a specific meeting quickly | Done |
| US-10 | user | export a meeting as a PDF | I can share it with people who don't have the app | Done |
| US-11 | user | delete a meeting I no longer need | my data doesn't accumulate forever | Done |
| US-12 | user | switch between light/dark/system theme | the app matches my device preference | Done |
| US-13 | user | be confident nothing leaves my device | I can discuss sensitive topics without a privacy concern | Done (see Privacy Policy) |
| US-14 | user | add free-text notes to a meeting | I can capture context the transcript/AI doesn't | Done |
| US-15 | user | ask a free-form question about my own meetings | I don't have to re-read transcripts to find one fact | Done (see Ask AI) |
| US-16 | user | lock the app with my device's own PIN/biometric | someone else picking up my phone can't read my meetings | Done (App lock) |
| user (traveler) | user | speak or type in my language and have it translated and spoken aloud in the other person's language, fully offline | I can communicate without a shared language or an internet connection | Done (Conversation Translator) |

**US-7/US-8 revision note:** action items and decisions were originally both AI-extracted from the transcript alongside the summary. This was changed: a small on-device model reliably producing that much structured JSON made generation slower and more failure-prone (see [`ai-architecture.md`](architecture/ai-architecture.md#why-decisions-and-structured-action-items-were-dropped)). Action items are now added manually from their own tab; decisions were dropped entirely and the Decisions tab was removed from the UI (the `decisions` table still exists in the schema, referenced only by the Export screen's per-section toggle and the Search use case, both effectively no-ops now since nothing populates it).

## Use Cases

### UC-1: Record and process a new meeting

**Actor:** User
**Precondition:** Microphone permission available (requested at record time)
**Flow:**
1. User taps "New meeting" → "Record a meeting" on Home.
2. User enters a title, taps "Start recording".
3. App requests mic permission if not yet granted; creates a `Meeting` row (status `created`).
4. User can pause/resume; a live timer and level indicator are shown.
5. User taps "Stop" (or confirms "Stop & save" if navigating away mid-recording).
6. App finalizes the audio file path and duration on the `Meeting` row, then — in the background — transcribes it (status → `transcribing` → possibly `downloadingModel` first if this is the first-ever transcription → `summarizing`, possibly `downloadingSummaryModel` first if this is the first-ever AI summary) and generates the AI summary (status → `ready`, or `error` on failure/timeout).
7. User is taken to Meeting Details, where Transcript/Summary/MoM/Action Items/Notes become populated as each stage completes. Action items are added manually, not AI-generated.

**Postcondition:** A `Meeting` row with an audio file, and (once the pipeline completes) a `Transcript` and a `Summary`. Action items and notes are added by the user, not generated by this flow.

### UC-2: Import an existing recording

Same as UC-1 from step 6 onward, except step 1-3 is: user picks a file via the system file picker; if it's a video, audio is extracted via ffmpeg first.

### UC-3: Search for a meeting

**Actor:** User
**Flow:** User types a query (or picks a date) on the Search screen. The app searches meeting titles, transcript text, and action item descriptions in parallel (a decision-description search still runs too, but can never match anything now that decisions aren't generated), unions the matching meeting ids, and lists the resulting meetings (most recent first).

### UC-4: Export a meeting as PDF

**Actor:** User
**Flow:** From Meeting Details, user taps "Export as PDF" → either previews it interactively (with print/share built into the preview) or taps "Export & share" for a one-tap share-sheet export. The PDF contains: title/date, summary, Minutes of Meeting, key topics, action items, and the full transcript, in that order, with a per-section include/exclude toggle (a "Decisions" toggle still exists but has nothing to include).

### UC-5: Delete a meeting

**Actor:** User
**Flow:** User swipes a meeting tile left (Home/History) or taps the delete icon (Meeting Details), confirms in a dialog. The app deletes the on-disk audio file and the `Meeting` row; the database's foreign-key cascade removes the associated transcript/summary/action items/notes automatically.

### UC-6: Have a bidirectional conversation via the Translator

**Actor:** User (typically while traveling)
**Precondition:** None persisted — the conversation session starts empty every time the screen opens.
**Flow:**
1. User opens Conversation Translator from Home, sets "their" and "my" language (or leaves "their" as auto-detect).
2. The local person speaks (mic) or their message is imported/typed; the app transcribes (if spoken) and translates it into the user's language, shown in the left/blue bubble.
3. The user speaks or types their reply in their own language; the app translates it into the other person's language, shown in the right/green bubble, and speaks it aloud via TTS if that language has an installed voice.
4. Either bubble's speaker icon replays its translated audio. "Clear Conversation" wipes the in-memory session permanently — nothing here was ever saved to disk.

**Postcondition:** No persistent data of any kind — this use case is entirely in-memory, per the app's privacy design.

### UC-7: Ask a question about your own meetings

**Actor:** User
**Flow:** User opens Ask AI, types a free-form question. The app gathers relevant excerpts from the user's own meeting transcripts/summaries and asks the on-device LLM to answer using only that context — never the model's general knowledge — and shows the answer, or a clear "couldn't find an answer" response if the notes don't contain one.

## Functional requirements summary

See [`03-srs.md`](03-srs.md) for the numbered functional/non-functional requirement list traced to implementation.

## Out of scope

See [`01-executive-summary.md`](01-executive-summary.md#explicitly-out-of-scope-belongs-to-a-hypothetical-commercialstartup-version-not-this-project).
