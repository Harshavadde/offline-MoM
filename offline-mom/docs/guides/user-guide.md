# User Guide

> **Sync note (documentation synchronization pass):** updated to describe the current app — meetings, documents, chat, and the Productivity Toolkit (Student Toolkit). The Conversation Translator described in an earlier version of this guide has been removed from the app; Ask AI has been superseded by Chat and is no longer reachable from any screen. Updated again 2026-08-06 for document folders, Chat's no-AI-model empty state, and the always-visible AI-generated-response note (see [`10-v2-progress.md`](../v2/implementation/10-v2-progress.md), Phase 9.3, tag `phase-9-3`).

## Getting started

The first time you record, import, chat, or use the AI Model Manager, OfflineMoMAI downloads the AI model(s) it needs (transcription is ~140MB and up depending on the tier you pick; the chat/summarization model is ~1.1GB; the embedding model that powers chat search is ~300MB) — this needs an internet connection just once per model, ideally Wi-Fi for the larger ones. After that, everything works with no internet at all. If the connection is too slow or drops, the download fails with a clear error and a Retry option rather than hanging indefinitely.

## Recording a meeting

1. On **Home**, tap **New meeting** → **Record a meeting**.
2. Type a title, tap **Start recording**. Grant microphone access if asked.
3. Use **Pause**/**Resume** as needed; tap the **Mark** button at any point worth flagging (you can jump straight back to it later); tap **Stop** when you're done.
4. You'll land on the meeting's details page. The transcript, then the summary, appear automatically over the next moments as they finish generating — no need to wait on this screen. Action items are added by you, not generated automatically (see below).

## Importing a meeting

1. On **Home**, tap **New meeting** → **Import audio/video**.
2. Pick a file (MP3, WAV, M4A, AAC, MP4, MKV, or MOV). If it's a video, the audio is extracted automatically.
3. Same as recording — transcript and summary appear automatically.

## Renaming or deleting a meeting

- **Rename**: open the meeting, tap the pencil icon next to its title.
- **Delete**: swipe a meeting left in Home or History, or tap the trash icon on its details page. Confirm — this permanently removes the meeting, its transcript, summary, action items, and notes.

## Reading a meeting

From a meeting's details page:
- **Transcript** — the full text of what was said, with your Marks as tappable jump-points during playback.
- **Summary** — a short AI-written summary and key topics.
- **Minutes of Meeting** — a more formal write-up.
- **Action items** — a checklist you add to yourself (tap **+**); not AI-generated, so add what you actually need tracked.
- **Notes** — free-text notes you write yourself, separate from the AI output.

While the transcript/summary are generating, you'll see a status like "Downloading the AI model…" (only the very first time) or "Generating with on-device AI…"; if something goes wrong or takes too long, you'll see a clear error state with a Retry button instead of a stuck spinner.

## Importing a document

1. On **Home**, tap **Import files**, then **Import** on the Documents screen.
2. Pick a PDF, Word (DOCX), plain text, or Markdown file.
3. The document is extracted (searchable right away), then summarized and indexed for chat, entirely on-device.

## Organizing documents into folders

The Documents screen has a row of chips above the list: **All Documents** plus one per folder you've created.

- **Create a folder**: tap the **New folder** chip at the end of the row and give it a name.
- **Rename or delete a folder**: long-press its chip. Deleting a folder never deletes the documents in it — they move back to All Documents.
- **Move a document into a folder**: open the document's details page and tap **Move to folder**, or use the same action from the Documents list.

Folders are purely organizational — search, chat, and everything else still see every document regardless of which folder it's in.

## Chat

Chat lets you ask questions in plain language and get answers grounded in your own meetings and documents:

1. Open a conversation from a "Chat about this" button on a meeting or document's details page, or continue a recent conversation from Home.
2. Use the in-chat scope selector to ask about everything in your workspace, or just the one meeting/document you opened it from.
3. If your own content has a confident answer, you'll see it with citations back to the meeting(s)/document(s) it came from — each citation shows a "% match" score for how relevant that source was to your question, not how complete or finished the answer is. If nothing in your content is a confident match, the app still answers using the AI model's own general knowledge — clearly labeled as such, with no citations attached, so you always know which kind of answer you're looking at. Every answer, either way, carries a small "AI-generated response — please verify important information" note underneath it.
4. Edit or resend a question, regenerate an answer, copy or delete individual messages, and export a conversation as text, Markdown, or PDF from the menu in the chat screen.
5. Open **Chat History** to resume, rename, pin, or delete past conversations.
6. If you haven't installed a chat AI model yet, Chat shows a short explanation instead of an empty conversation, with a one-tap button to get a recommended model set up.

There is no separate "Ask AI" screen in normal use any more — Chat replaced it. (An old Ask AI screen still technically exists in the app but is not linked from anywhere; you shouldn't need it.)

There is no Conversation Translator in this app — an earlier version had one; it has been removed.

## Productivity Toolkit

Tap **Productivity tools** on Home (or its icon in the toolkit section) for everyday file utilities that don't need any AI model: compress or resize images, scan documents with a phone camera (multi-page, with perspective correction), and compress/merge/split/reorder PDFs. Every output is saved to **Recent Files** within the toolkit, independent of your meetings and documents.

## Searching

Open the **Search** tab and type — it searches meeting names, document names, transcript content, extracted document text, and action items all at once, grouped by content type. Tap the calendar icon to search by a specific date instead.

## Exporting to PDF

From a meeting's details page, tap **Export as PDF**:
- **Export & share** — one tap, opens your device's share sheet immediately.
- **Preview first** — see the PDF before sharing, with print/share buttons built into the preview, and toggles for which sections to include.

The PDF includes the summary, minutes of meeting, key topics, action items, and the full transcript.

## Settings

- **Appearance** — switch between **Light**, **Dark**, or **Match system** theme.
- **App lock** — require your device's own PIN/pattern/password or fingerprint to open the app — useful if someone else might pick up your phone. This uses your device's existing lock, not a separate account or password; if your device has no screen lock set up, set one up in your phone's settings first. Once on, the app locks again every time it's backgrounded, not just when fully closed.
- **AI Models** — download, switch, or delete the transcription/chat/embedding model tier you're using; pick a recommended set-up based on your profession (with live per-model progress and a Cancel option), or manage each model independently.
- **Storage** — see how much space recordings, documents, the database, cached AI models, and toolkit outputs are each using, and clear what you don't need.
- **Language** — set the transcription language.
- **Recording** — recording-related preferences.
- **Backup** — export your meetings database and audio files via your device's share sheet, e.g. to move them to a new phone.
- See **About**, **Privacy**, and **Help** for more information about the app.

## Your privacy

Nothing you record, import, generate, or ask in Chat ever leaves your device — see the in-app **Privacy** screen (Settings → Privacy) or [`docs/legal/privacy-policy.md`](../legal/privacy-policy.md) for the full statement. The only time the app ever touches the network at all is a one-time download of an AI model you've chosen to install.
