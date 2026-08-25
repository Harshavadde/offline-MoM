# Software Requirements Specification (SRS)

## 1. Introduction

### 1.1 Purpose
Specifies the functional and non-functional requirements for OfflineMoMAI v1.0, a fully offline Android meeting assistant. Intended audience: project evaluators, and anyone extending the codebase.

### 1.2 Scope
See [`01-executive-summary.md`](01-executive-summary.md).

### 1.3 Definitions

| Term | Meaning |
|---|---|
| MoM | Minutes of Meeting |
| STT | Speech-to-text |
| LLM | Large Language Model |
| GGUF | The model file format used by llama.cpp/whisper.cpp |
| TTS | Text-to-speech |

## 2. Functional Requirements

Each requirement lists the primary implementation location for traceability.

| ID | Requirement | Implementation |
|---|---|---|
| FR-1 | The system shall allow the user to start, pause, resume, and stop a live audio recording. | `lib/features/recording/presentation/providers/recording_providers.dart` (`RecordingController`), `lib/services/audio/recorder_service.dart` |
| FR-2 | The system shall allow the user to rename a meeting. | `lib/features/meetings/presentation/screens/meeting_details_screen.dart` |
| FR-3 | The system shall allow the user to import audio files (MP3, WAV, M4A, AAC) and video files (MP4, MKV, MOV). | `lib/services/audio/file_picker_audio_import_service.dart` |
| FR-4 | When a video file is imported, the system shall automatically extract its audio track. | `FilePickerAudioImportService.prepareAudioFile` (ffmpeg) |
| FR-5 | The system shall transcribe a meeting's audio into text entirely on-device. | `lib/services/ai/whisper_speech_to_text_engine.dart`, `lib/features/transcription/transcribe_meeting_use_case.dart` |
| FR-6 | The system shall generate a summary, Minutes of Meeting, and key topics from a transcript entirely on-device, as strict JSON. | `lib/services/ai/llamadart_llm_engine.dart`, `lib/features/ai_summary/generate_meeting_summary_use_case.dart` |
| FR-7 | The system shall persist meetings, transcripts, summaries, action items, notes, and settings locally. | `lib/database/`, `lib/repositories/` |
| FR-8 | The system shall let the user manually add, check off, and remove action items for a meeting. | `ActionItemRepository`, `_ActionItemsTab` (`meeting_details_screen.dart`) — action items are user-entered, not AI-extracted (see FR-6) |
| FR-9 | The system shall let the user search meetings by name, transcript content, action item text, or date. | `lib/features/search/search_meetings_use_case.dart` |
| FR-10 | The system shall let the user export a meeting's transcript, summary, and action items as a single PDF, with an interactive preview, per-section toggles, and a share action. | `lib/services/export/pw_pdf_export_service.dart`, `pdf_preview_screen.dart`, `export_screen.dart` |
| FR-11 | The system shall let the user delete a meeting, removing its audio file and all dependent data. | `lib/features/meetings/delete_meeting_use_case.dart` |
| FR-12 | The system shall let the user switch between light, dark, and system theme. | `SettingsController`, `appearance_screen.dart` |
| FR-13 | The system shall require no user account, login, or cloud connectivity for any of the above. | Architecture-wide; see [`01-executive-summary.md`](01-executive-summary.md) |
| FR-14 | The system shall optionally require the device's own PIN/pattern/password/biometric to open the app, without introducing an app-specific account or credential. | `lib/services/security/`, `AppLockController` (`lib/providers/app_providers.dart`), `LockScreen` |
| FR-15 | When an offline pipeline stage (transcription or AI summary) fails or times out, the system shall record and display the reason, and let the user retry without re-recording. | `Meeting.errorMessage`, `RetryMeetingProcessingUseCase`, `AiPipelineFallback`, `LlmTimeoutException`, `LlmModelDownloadTimeoutException` |
| FR-16 | The system shall let the user add free-text notes to a meeting. | `NoteRepository`, `_NotesTab` (`meeting_details_screen.dart`) |
| FR-17 | The system shall answer a free-form question using only the user's own meeting transcripts/summaries as context, entirely on-device, never the model's outside knowledge. | `lib/features/ask/ask_about_meetings_use_case.dart`, `LlmEngine.answerQuestion` |
| FR-18 | The system shall provide a bidirectional conversation translator: transcribe or accept typed text (including romanized Indic script) in a source language, translate it to a target language entirely on-device, and optionally speak the translation aloud using the device's own installed TTS voice. | `lib/features/conversation_translator/`, `LlmEngine.translate`, `TextToSpeechService` |
| FR-19 | Conversation Translator turns shall not be persisted to disk under any circumstance; they exist only in memory for the lifetime of the screen, and can be cleared on demand. | `ConversationSessionController` (in-memory `Notifier`, no repository) |
| FR-20 | The system shall let the user export/back up their data (database and audio files) via the system share sheet, and view/clear cached AI model storage. | `backup_screen.dart`, `storage_screen.dart`, `storage_providers.dart` |
| FR-21 | The system shall let the user flag a timestamp during live recording ("Mark") and jump to it during playback. | `RecordingMarkRepository`, `_PlaybackBar` (`meeting_details_screen.dart`) |

## 3. Non-Functional Requirements

| ID | Requirement | Notes |
|---|---|---|
| NFR-1 (Privacy) | No audio, transcript, or derived data shall be transmitted off-device during normal operation. | The only network access in the app is the one-time AI model download (whisper/Qwen2.5-1.5B GGUF from Hugging Face) on first use — see [`docs/architecture/ai-architecture.md`](architecture/ai-architecture.md). |
| NFR-2 (Offline-first) | Recording, import, transcription, summarization, search, export, and the Conversation Translator shall all function with the device in airplane mode (after the one-time model download). | Verified manually; no code path in these flows makes a network call. |
| NFR-3 (Maintainability) | The codebase shall follow Clean Architecture (domain/data/presentation) with the Repository pattern, so storage/AI engines can be swapped without touching UI code. | See [`docs/architecture/hld.md`](architecture/hld.md). |
| NFR-4 (Testability) | Business logic (use cases, repositories) shall be unit-testable without a device, using fakes for native AI engines. | `test/repositories/`, `test/use_cases/`, `test/test_helpers/fake_ai_engines.dart` |
| NFR-5 (Usability) | The UI shall use Material 3, support light and dark mode, and show a meaningful empty state for every screen with no data. | `lib/core/theme/app_theme.dart`, `lib/shared/widgets/empty_state.dart` |
| NFR-6 (Data integrity) | Deleting a meeting shall never leave orphaned transcript/summary/action item/note rows. | Enforced by `ON DELETE CASCADE` foreign keys — see [`docs/sql/schema.sql`](sql/schema.sql). |
| NFR-7 (Resource-awareness) | The default AI models shall be small enough to run on a modest phone. | Whisper `base` (~140MB), Qwen2.5-1.5B-Instruct Q4_K_M (~1.1GB) — see ADR in [`docs/architecture/ai-architecture.md`](architecture/ai-architecture.md). |
| NFR-8 (Portability) | The build shall reproduce on a machine other than the one it was built on, without manual pub-cache edits. | Verified: dependency versions are pinned in `pubspec.yaml`/`pubspec.lock`; no hand-patched packages. |
| NFR-9 (Reliability/bounded latency) | No AI operation (generation or first-time model download) shall be able to hang indefinitely; every such call shall fail with a clear, retryable error after a bounded time instead. | `LlmTimeoutException` (45s stall on generation), `LlmModelDownloadTimeoutException` (90s stall / 15min absolute cap on download) — both in `lib/services/ai/llamadart_llm_engine.dart`. Added after real-device testing surfaced a case where a single stuck generation call could block every AI feature in the app indefinitely, since all three (summary, Ask AI, Translator) share one underlying model engine that serializes requests. |

## 4. Constraints

- Android only (per project scope); no iOS/web/desktop target.
- No cloud services of any kind (Firebase, custom backend, etc.) — see Explicitly Out of Scope in the Executive Summary.
- Native AI plugins (whisper.cpp, llama.cpp bindings) require a modern Android/Gradle toolchain; see [`docs/guides/installation-guide.md`](guides/installation-guide.md) for the exact versions this project pins.

## 5. Assumptions

- The user's device has enough free storage for the app, its models (~1.25GB combined: whisper `base` + Qwen2.5-1.5B), and recorded audio.
- The user has internet access at least once, to download the whisper and Qwen2.5-1.5B models before first use — ideally Wi-Fi, since the LLM model alone is ~1.1GB.
- The device has at least one installed TTS voice for whichever language(s) the Conversation Translator is used with; if not, translation still works but audio playback for that language is silently skipped (`TextToSpeechService.isLanguageAvailable`).
