# OfflineMoMAI

**Your Meetings. Your Documents. Your Device. Your Privacy.**

OfflineMoMAI started as a fully offline AI meeting assistant for Android — record or import a meeting, transcribe it on-device with [whisper.cpp](https://github.com/ggerganov/whisper.cpp), and generate a summary, Minutes of Meeting, and key topics using an on-device LLM ([llama.cpp](https://github.com/ggerganov/llama.cpp), Qwen2.5-1.5B-Instruct). It also includes an offline **Conversation Translator** for real-time bidirectional speech/text translation between English and nine Indian languages.

It has since grown into a broader **private, offline AI workspace**: import and chat with documents (PDF/DOCX/TXT/Markdown) — including attaching a file directly from the chat composer, or asking a question by voice via an in-composer mic button — organize them into folders, and chat through a **Hybrid Retrieval Engine** (fused vector + keyword search with confidence-scored answers — every source citation shows a "% match" relevance score, not a completion percentage — and a clearly-labeled general-knowledge fallback, with an always-visible "AI-generated" disclaimer, for questions your content doesn't cover), search across everything you've recorded and imported from one place, a **Productivity Toolkit** (document scanning with perspective correction, image compress/resize, and a full offline PDF suite — compress/merge/split/organize/edit (text, signatures, annotations, watermark)/permanent redaction/password-protect/unlock, convert between images and PDF, and an on-device OCR engine that turns a scan into a real searchable PDF — plus a file manager with folders, search, sort, favorites, and multi-select bulk actions), and an **AI Model Manager** (download, switch, verify, and delete the Chat/Embedding/Speech-to-text/OCR models the app runs on, with profession-based recommendations, live per-model download progress, and a Cancel option) — all still governed by the same architectural guarantee the original meeting assistant made: nothing is ever uploaded anywhere. There is exactly one network-capable code path in the entire app, the one-time AI model download on first run; everything else, forever, runs on-device — no cloud, no login, no accounts. A **Settings → Offline Readiness** screen (also surfaced as a compact card on Home) shows exactly which required models are installed and states this network boundary plainly, rather than asserting "100% offline" as an unqualified claim. Errors are always shown in plain language, never as a raw exception or stack trace. Anywhere the app shows AI-generated text — a meeting summary, a chat answer, a resume bullet rewrite — a short, consistent disclaimer is shown alongside it, prompting the user to verify before relying on it.

It also includes a **Resume / Career workspace**: build a resume from a reusable library of experience/education/project/skill blocks (never duplicated per resume), tailor it against a pasted or imported Job Description with deterministic + on-device-semantic matching and bounded, review-gated AI rewrite suggestions (nothing reaches your resume without an explicit Accept), and export it through any of 5 beta-curated PDF templates rendered entirely on-device. A **"Create a Beginner Resume"** path, aimed at first-time job seekers with little or no work history, walks through basic details, a target role (picked from 14 curated categories or matched from a pasted JD/short title), then optional education/experience/skills/languages/certifications/achievements, and generates a resume containing only what was actually entered — nothing fabricated or padded — with an optional, clearly-disclaimed AI polish step on the summary text only. See [`docs/v3/implementation/10-v3-progress.md`](docs/v3/implementation/10-v3-progress.md) for exactly what's shipped in this area.

Full documentation lives in [`docs/`](docs/) (the original meeting-assistant product, as shipped), [`docs/v2/`](docs/v2/) (the workspace evolution — read [`docs/v2/README.md`](docs/v2/README.md) first for how the two relate, and [`docs/v2/implementation/10-v2-progress.md`](docs/v2/implementation/10-v2-progress.md) for exactly what's shipped as of today), and [`docs/v3/`](docs/v3/) (the Resume/Career workspace — [`docs/v3/01-prd.md`](docs/v3/01-prd.md) for the frozen product spec, [`docs/v3/implementation/10-v3-progress.md`](docs/v3/implementation/10-v3-progress.md) for live status).

## Features (V1: Meetings)

- **Record** — start/pause/resume/stop, rename, mid-recording bookmarks ("Marks")
- **Import** — MP3, WAV, M4A, AAC, MP4, MKV, MOV (audio auto-extracted from video)
- **Offline transcription** — whisper.cpp, runs entirely on-device
- **Offline AI summary** — summary, Minutes of Meeting, key topics (see "Why decisions and action items aren't AI-extracted" below)
- **Action items** — manual checklist per meeting (not AI-extracted)
- **Notes** — free-text notes per meeting
- **Ask AI** — ask a free-form question answered only from your own meetings' transcripts, on-device
- **Conversation Translator** — offline bidirectional speech/text translation (see below)
- **Search** — by meeting name, transcript content, action items, or date
- **PDF export** — interactive preview and one-tap share
- **App lock** — optional, uses the device's own biometric/PIN, no separate account
- **Backup** — export your data (SQLite DB + audio files) via the system share sheet
- **Local-only storage** — SQLite (meetings/transcripts/summaries/action items/notes) + Hive (settings); no analytics
- **Material 3** — light/dark/system theme, no accounts

### Conversation Translator

A separate, standalone feature (`/conversation`) for talking to someone who speaks a different language, entirely offline: pick "their" and "your" language (auto-detect, or one of Tamil, Telugu, Bengali, Marathi, Kannada, Malayalam, Hindi, Punjabi, Gujarati, English), then speak (mic), import an audio file, or type — including romanized text (e.g. "ikkadiki randi"). Each turn is transcribed (if spoken), translated by the same on-device LLM, and optionally spoken aloud via the phone's own installed TTS voice. Conversation history is **in-memory only** — nothing is written to disk, and it's cleared on request or when the screen closes, per the app's privacy design.

### Why decisions and action items aren't AI-extracted

Earlier iterations had the LLM extract "decisions" and structured action items (task/owner/deadline) alongside the summary. This was removed: getting a small on-device model to reliably produce that much structured JSON on top of summarizing made the prompt bigger, generation slower, and the JSON more likely to come back malformed — a bad trade for an app whose whole point is speed and reliability on modest hardware. Action items are now a simple manual checklist instead; decisions were dropped entirely (the `decisions` database table still exists for schema-compatibility/PDF-export toggles but is no longer populated).

## Tech stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.44 / Dart 3.12 (isolated per-project SDK — see installation guide) |
| State management / DI | Riverpod |
| Navigation | go_router |
| Relational storage | sqflite (raw SQL) |
| Key-value storage | Hive |
| Recording | `record` |
| File import | `file_picker` |
| Video → audio | `ffmpeg_kit_flutter_new` |
| Speech-to-text | `whisper_flutter_new` (whisper.cpp) |
| On-device LLM | `llamadart` (llama.cpp, Qwen2.5-1.5B-Instruct Q4_K_M) |
| Text-to-speech | `flutter_tts` (device's own installed voices) |
| PDF | `pdf` + `printing` (generate/rasterize) · `read_pdf_text` (text search) · `flutter_tesseract_ocr` (OCR) · `pdf_cos` + `pdf_document` (password protection/unlock) |
| Biometric/PIN app lock | `local_auth` |

Architecture is Clean Architecture (domain/data/presentation) + MVVM + Repository pattern, feature-first folders. See [`docs/architecture/hld.md`](docs/architecture/hld.md) for the full breakdown and why.

## Getting started

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

`android/app/build.gradle.kts` defines a custom per-ABI output filename convention (`offlinemomai-<versionCode>-<abi>-<buildType>.apk`), but as of a 2026-08-20 Release Candidate audit that convention does not actually take effect — every build observed in `build/app/outputs/flutter-apk/` uses Flutter's own default naming instead (`app-debug.apk`, `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, or `app-release.apk` for a plain `flutter build apk --release` with no `--split-per-abi`). Treat the custom-naming code as currently inert, not as a description of what you'll actually find on disk. minSdk is **24** (not a lower value), because `ffmpeg_kit_flutter_new` and `record_android` require it.

See [`docs/guides/installation-guide.md`](docs/guides/installation-guide.md) for full setup (Android SDK/NDK versions, first-run model downloads, known toolchain quirks) and [`docs/guides/developer-guide.md`](docs/guides/developer-guide.md) for how the codebase is organized.

**Note on AI models:** the whisper (~140MB) and Qwen2.5-1.5B (~1.1GB) GGUF models are downloaded from Hugging Face automatically the first time transcription/summarization runs, then cached on-device — the one deliberate exception to "fully offline" (a one-time asset fetch, not a runtime dependency). Both the download itself and every LLM generation call are bounded by hard timeouts (see [`docs/architecture/ai-architecture.md`](docs/architecture/ai-architecture.md#reliability-timeouts-and-cancellation)) so a slow or dropped connection can never hang the app indefinitely — it fails with a clear, retryable error instead.

## Project status

The original nine V1 build phases (scaffold, recording, import, transcription, AI summary, search, PDF export, polish, documentation) are complete — Ask AI, Notes, recording bookmarks, app lock, backup/storage management, and the Conversation Translator all shipped as part of that arc. See [`docs/09-viva-questions.md`](docs/09-viva-questions.md) and [`docs/06-risk-and-future-scope.md`](docs/06-risk-and-future-scope.md) for what was deliberately out of scope for V1.

The project has since moved into a V2 arc (the workspace evolution described above), tracked as a separate set of phases in [`docs/v2/implementation/10-v2-progress.md`](docs/v2/implementation/10-v2-progress.md) — Documents, Chat, Search, the Student/Productivity Toolkit (image tools, Scanner, PDF Tools), and the AI Model Manager are shipped as of today; see that file for exactly what's done and [`docs/v2/20-future-roadmap.md`](docs/v2/20-future-roadmap.md) for what's next.

A parallel V3 arc (the Resume/Career workspace described above) is tracked in [`docs/v3/implementation/10-v3-progress.md`](docs/v3/implementation/10-v3-progress.md) — the resume template engine, JD tailoring pipeline, progressive Resume Wizard, "Create Resume from a JD," and the Beginner Resume Builder are shipped as of today. A debug APK has been built for physical-device testing; production (release) signing and Play Store distribution readiness are not yet done — see that file's own "Known limitations" notes for the current, honest state.

## License

Not currently published to pub.dev or any app store. This started as a final-year engineering project; V2 (see [`docs/v2/01-product-vision.md`](docs/v2/01-product-vision.md)) is being developed with a possible future commercial release in mind, but no distribution, pricing, or licensing decision has been made yet — see [`docs/v2/18-subscription-model.md`](docs/v2/18-subscription-model.md) for the open options under consideration.
