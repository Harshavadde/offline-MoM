# Executive Summary, Problem Statement, Objectives & Scope

## Executive Summary

OfflineMoMAI is an Android application that turns a recorded or imported meeting into a searchable transcript and an AI-generated summary/Minutes of Meeting (MoM) — without any of that audio or text ever leaving the device. It also includes an on-device conversational assistant (Ask AI) and a fully offline, bidirectional speech/text translator for nine Indian languages plus English, aimed at travelers communicating with locals who don't share a language. Speech-to-text runs on [whisper.cpp](https://github.com/ggerganov/whisper.cpp) and every LLM-backed feature (summarization, Ask AI, translation) shares a single on-device model ([llama.cpp](https://github.com/ggerganov/llama.cpp) running Qwen2.5-1.5B-Instruct), both via native (FFI) bindings inside the Flutter app. There is no backend server, no user account, and no analytics collection of any kind.

The project demonstrates that a privacy-preserving, zero-cloud-cost meeting assistant (and, more broadly, a small on-device-LLM-powered application) is practical on commodity Android hardware today, using only open-source, locally-run models — at the cost of using smaller/quantized models than a cloud service would, and a one-time internet-dependent model download on first use. A significant part of the engineering effort went into making that trade-off *safe*: bounding every AI call and the one-time model download with hard timeouts, so a slow connection or a stuck generation degrades to a clear, retryable error instead of an indefinite hang — a real failure mode encountered and fixed during development.

## Problem Statement

Commercial meeting-assistant tools (e.g. Otter.ai, Fireflies, cloud-based Zoom/Teams transcription) universally rely on uploading raw audio to a third-party server for transcription and summarization. This has two consequences that matter to students, small teams, and privacy-conscious professionals in particular:

1. **Privacy/confidentiality risk.** Meeting audio often contains sensitive discussion (grades, personnel matters, unreleased research, business terms) that the participants may not have consented to sending to an external company's servers, and that company's data-retention/training policies are usually opaque.
2. **Recurring cost.** Cloud transcription and LLM summarization APIs charge per-minute or per-token, which is a real barrier for students and small teams who need this occasionally, not as a paid subscription.

OfflineMoMAI addresses both by moving the entire pipeline — audio capture, transcription, and summarization — onto the device.

## Objectives

1. Record or import a meeting (audio or video) and produce a full-text transcript, entirely offline.
2. Generate a summary, Minutes of Meeting, and key topics from that transcript, entirely offline (action items are user-entered — see Scope).
3. Store all of the above locally, searchable by meeting name, transcript content, action items, and date.
4. Export a meeting's transcript, summary, and action items as a single shareable PDF.
5. Provide an offline, bidirectional speech/text translator so a user can communicate with someone who speaks a different language, with no internet connection.
6. Ensure no AI operation can hang the app indefinitely, regardless of network or model conditions.
7. Do all of this with a clean, maintainable, testable codebase suitable for a final-year engineering deliverable — not a prototype.

## Scope

### In scope (implemented)

- Live audio recording (start/pause/resume/stop, rename, mid-recording bookmarks)
- Import of MP3/WAV/M4A/AAC/MP4/MKV/MOV, with automatic audio extraction from video
- Offline speech-to-text (whisper.cpp)
- Offline AI summary generation: summary, Minutes of Meeting, key topics (llama.cpp) — action items are manually entered by the user, and decisions are no longer AI-extracted at all (see [`ai-architecture.md`](architecture/ai-architecture.md) for why)
- Free-text notes per meeting, independent of the AI output
- Ask AI: on-device question answering scoped to the user's own meetings
- Conversation Translator: fully offline bidirectional speech/text translation across ten languages, with text-to-speech playback, never persisted to disk
- Local SQLite storage of meetings/transcripts/summaries/action items/notes, plus Hive for settings
- Search across meeting name, transcript text, action items, and date
- PDF export with interactive preview, per-section toggles, and share
- Optional device-native app lock (PIN/biometric), and a backup/export flow for the user's own data
- Material 3 UI, light/dark/system theme
- Hard timeouts on every AI call and the one-time model download, so none of the above can hang indefinitely
- Unit tests (repositories, use cases with fake AI engines) and an on-device integration test scaffold

### Explicitly out of scope (belongs to a hypothetical commercial/startup version, not this project)

- Cloud sync, user accounts, or authentication of any kind
- Firebase or any other third-party backend
- Integrations with Teams, Zoom, Google Meet, or WhatsApp
- An enterprise admin dashboard
- Subscription billing

These are excluded deliberately, not for lack of time — introducing any of them would contradict the project's core privacy premise (see [`docs/legal/privacy-policy.md`](legal/privacy-policy.md)) and the "no login" requirement set for this project.

## Target users

Students, teachers, developers, small teams, researchers, and professionals who run their own meetings and want a private record of them without paying for or trusting a cloud service — plus, for the Conversation Translator specifically, travelers who need to communicate with someone in a different Indian language with no internet connection available.
