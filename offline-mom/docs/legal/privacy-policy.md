# Privacy Policy

**Last updated:** 2026

## Summary

OfflineMoMAI is designed to work entirely offline. This policy exists to state plainly what that means in practice.

## What data OfflineMoMAI handles

Meeting audio, transcripts, AI-generated summaries and minutes of meeting, action items and notes you enter yourself; documents you import (PDF/DOCX/TXT/Markdown) and their extracted text/summaries; folders you create to organize documents (a folder is just a name — it holds no content of its own); Chat conversations (your questions and the AI's answers, including which of your meetings/documents an answer cited, if any); and outputs from the Productivity Toolkit (compressed/resized images, scans, processed PDFs). All of it is created by your own use of the app. (An earlier version also had the AI extract "decisions"; that's no longer generated at all — see the Responsible AI Statement.)

## Where that data goes

**Nowhere but your device.** Specifically:

- Audio, documents, and toolkit files you record, import, or create are written to this app's private storage on your device only.
- Speech-to-text transcription runs on-device (whisper.cpp); the audio is never uploaded anywhere for this purpose.
- Summarization, document processing, and Chat (including retrieval/search over your own content) run on-device (llama.cpp / Qwen2.5-1.5B-Instruct for generation, embeddinggemma-300M for the search index that powers Chat); none of that text is ever uploaded anywhere for these purposes.
- The app has no user account, no login, and no server component to send data to even if it wanted to.
- The app collects no analytics, crash reports, or telemetry of any kind.

## The one exception (network access)

The first time you use transcription, summarization, or Chat, the app downloads the corresponding AI model file (not your data — a generic model file, the same one every user downloads) from Hugging Face's public model hosting. This is the only network request the app makes as part of its core functionality, and it carries no information about you, your meetings, or your documents — it's a one-time software asset download, comparable to downloading an app update. This download is bounded by a timeout, so a slow or interrupted connection fails with a clear retry prompt rather than leaving the app in an unclear state; the app also checks for a working connection before starting a model download and explains clearly if none is found, rather than appearing to hang.

If you turn on "Allow background downloads" (Settings), the app runs a foreground service so this one-time download can continue while you switch to another app; Android requires a persistent notification to show while that service is active. This setting is off by default and does not change what the app does with your data — it only affects whether the model download itself can continue in the background.

## Exporting and sharing

If you export a meeting as a PDF and choose to share it (via the system share sheet), that sharing is your explicit action, going wherever you direct it (email, another app, etc.) — the app does not share anything on your behalf without you initiating it.

## App lock

If you turn on App lock (Settings), the app asks Android's own authentication system to verify you using whatever your device already has configured (fingerprint, face, PIN, pattern, or password). The app never sees or stores your fingerprint, face data, or device passcode — Android handles the check itself and only tells the app "yes" or "no." This is your device's existing security, not an account or credential the app creates or manages.

## Deleting your data

Deleting a meeting or document in the app permanently removes its file (audio or document) and all associated transcript/summary/action items/notes/search index records from your device immediately. There is no "trash" or recovery period, and no copy exists anywhere else for the app to also delete. Deleting a folder only removes that organizational label — the documents that were in it are kept, moved back to "All Documents," not deleted.

## Permissions

- **Microphone** — required to record meetings; requested only when you tap "Start recording."
- **Storage/file access** — required to import existing audio/video files and to save exported PDFs/backups.
- **Notifications** — used only to show the required persistent notification if you opt in to background downloads (see above); no other notifications are sent.

No permission is used for anything beyond the feature it's requested for.

## Children's privacy

The app collects no personal information from anyone, so there is nothing to collect from children specifically.

## Changes to this policy

Since the app has no account system, there's no mechanism to notify users individually of changes — check this document (or the in-app Privacy screen) for the current version.

## Contact

See the project's README for maintainer/support contact information.
