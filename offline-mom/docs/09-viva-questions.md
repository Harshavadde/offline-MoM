# Viva Questions & Answers

## Architecture

**Q: Why Clean Architecture instead of putting everything in the widgets?**
A: The two AI engines (whisper.cpp, llama.cpp wrappers) are the parts of this app most likely to change — and one of them *did* change mid-project (`flutter_llama` → `llamadart`, see below). Because screens depend only on the abstract `SpeechToTextEngine`/`LlmEngine` interfaces (declared in `lib/services/ai/`), that swap touched one line in the composition root (`lib/providers/app_providers.dart`) and zero screens.

**Q: What's the dependency rule, concretely, in this codebase?**
A: A ViewModel (Riverpod `Notifier`) depends on a repository/service *interface*, never the concrete `Sqflite*Repository` or plugin-backed implementation. The only place concrete implementations are constructed is `lib/providers/app_providers.dart`, the composition root.

**Q: When did you use a dedicated use-case class versus calling a repository directly from a ViewModel?**
A: Only when there's real multi-step orchestration crossing more than one repository/service — e.g. `TranscribeMeetingUseCase` touches `MeetingRepository`, `TranscriptRepository`, and `SpeechToTextEngine`, with branching for success/failure. A single method call like "list all meetings" is called directly from the Home ViewModel against `MeetingRepository` — wrapping that in a use case would be ceremony with nothing to test.

**Q: What state-management approach did you use and why?**
A: Riverpod. `Notifier`s hold ViewModel state as sealed classes (e.g. `RecordingUiState` with `RecordingIdle`/`RecordingInProgress`/`RecordingFinished`/`RecordingFailed` variants) so screens `switch` exhaustively instead of juggling loose booleans, and the compiler flags an unhandled state.

## Database

**Q: Why SQLite for most data but Hive for settings?**
A: Meetings/transcripts/summaries/action items/decisions have real relational structure and are queried with filters (search, date range) — a natural fit for SQL. Settings is a single row of simple preferences with no relational shape and no query needs — a key-value store is a better, lighter-weight fit; a sixth SQL table would add ceremony with no benefit.

**Q: What happens to a meeting's transcript/summary/action items/decisions when you delete the meeting?**
A: All four foreign keys are declared `ON DELETE CASCADE`, and `PRAGMA foreign_keys = ON` is set on every connection. Deleting the `meetings` row cascades automatically — `DeleteMeetingUseCase` only has to handle the on-disk audio file explicitly, since the database doesn't know about the filesystem.

**Q: Why are transcript segments and key topics stored as JSON text instead of normalized tables?**
A: They're always read and written as a whole alongside their parent row and never queried independently (you never ask "find all transcripts containing segment X" at the SQL level) — normalizing them would add join complexity with no real benefit.

## AI pipeline

**Q: Why does the app re-encode audio before transcription?**
A: The app records/imports audio as AAC (`.m4a`) for compactness and playability, but whisper.cpp's native loader only reads 16kHz mono PCM WAV. `WhisperSpeechToTextEngine` converts via ffmpeg to a throwaway WAV, transcribes, then deletes the WAV.

**Q: Is this really "fully offline"?**
A: Every runtime operation is offline. The one exception is a one-time download of each AI model (whisper ~140MB, Qwen2.5-1.5B ~1.1GB) from Hugging Face the first time each is used, after which both are cached on-device and no further network access occurs for transcription, summarization, Ask AI, or translation. That download is itself bounded by a hard timeout (see below) rather than being allowed to hang forever.

**Q: Why Qwen2.5-1.5B and not a bigger model?**
A: Deliberate size/quality trade-off, documented in `docs/architecture/ai-architecture.md`. It replaced an even smaller original choice (TinyLlama-1.1B) once the Conversation Translator needed better instruction-following and translation quality than TinyLlama could reliably give, while staying small enough to run on modest phones. A future iteration could make the model configurable (see Future Scope) to trade size for quality further.

**Q: Why strict JSON output instead of the line-marker format an earlier version used?**
A: The original TinyLlama-era prompt used a permissive line-marker format (`SUMMARY:`/`MINUTES:`/etc.) specifically because that weaker model followed strict formats unreliably. Qwen2.5-1.5B follows a JSON system prompt reliably enough that strict JSON became worth using — `_extractJsonObject()` still scans for the first balanced `{...}` rather than trusting the model to emit *only* JSON, since small models still sometimes wrap it in markdown fences or a sentence of commentary.

**Q: Why did you remove decisions and structured action items from what the AI extracts?**
A: An earlier version had the model extract those alongside the summary. Real testing showed that asking a 1.5B model for that much *nested* structured JSON on top of summarizing made the prompt bigger, generation slower, and the JSON more likely to come back malformed — a bad trade for an app whose whole point is being fast and reliable on modest hardware. Action items are now purely manual; decisions were dropped entirely and the Decisions tab was removed from the UI since nothing could populate it anymore. The `decisions` SQLite table was deliberately left in place rather than removed, since Export and Search still reference it harmlessly as a permanent no-op.

**Q: What happens if transcription or summarization fails, or the AI just hangs?**
A: Failure: the meeting's `status` column moves to `error`, caught explicitly in each use case's `try/catch`; screens (`AiPipelineFallback` widget) show a dedicated failure state rather than an infinite spinner or a crash. Hanging is handled separately and was a real bug found in testing — see the next question.

**Q: Tell me about the reliability/timeout bug you found and fixed.**
A: `llamadart`'s worker isolate serializes every LLM call against one shared engine instance — a new request waits for whatever's currently running rather than being rejected. Once the same engine started backing three features (summary, Ask AI, Translator), a single stuck generation call, left unbounded, could block *every* AI feature in the app. This wasn't hypothetical: real-device testing reported an 8-hour-plus hang on a 7-second recording that should have taken seconds. The fix is two independent timeouts in `llamadart_llm_engine.dart`: a 45-second stall timeout (per-event-gap, so slow-but-steady generation isn't punished) around every generation call, which calls `engine.cancelGeneration()` on expiry to genuinely free the engine rather than just giving up client-side; and a separate 90-second-stall/15-minute-absolute-cap pair around the one-time model download itself, since that has its own independent hang risk from a bad network connection that `llamadart`'s own internal recovery doesn't fully cover.

**Q: How is the Conversation Translator's data handled differently from meetings?**
A: Meetings are stored locally (SQLite/Hive) — private, but persistent. The Conversation Translator's session is held only in a Riverpod `Notifier`'s in-memory state, with no repository or table backing it at all; it's gone the moment the screen closes or "Clear Conversation" is tapped, and there was never a saved copy to delete in the first place. This is a stricter privacy posture, applied because a travel conversation is treated as more sensitive-by-default.

**Q: How does the Conversation Translator's text-to-speech work — does it download voice models too?**
A: No — `flutter_tts` uses whichever text-to-speech voices are already installed on the user's Android device (the same system service other apps use for accessibility/narration), so there's no additional model download for speech output. `isLanguageAvailable()` is checked before attempting playback, since common languages like Hindi are nearly always available but others (e.g. Punjabi) often aren't; if unavailable, the translated text still displays, just without audio, and TTS failures are always non-fatal to the turn.

## Engineering process

**Q: What was the hardest technical problem in this project, and how did you solve it?**
A: A cascade of native-toolchain incompatibilities: several plugins (`record`, `flutter_llama`, `ffmpeg_kit_flutter_new`) required a materially newer Android/Gradle toolchain than the project's initial Flutter SDK. Rather than downgrade functionality, a second, fully isolated Flutter SDK was installed specifically for this project (never touching the shared original install, which another unrelated project depended on), along with matching Android SDK/NDK/CMake components and a deliberately-pinned Android Gradle Plugin version (8.9.2, not 9+) to avoid a real conflict between plugins on either side of AGP 9's "Built-in Kotlin" migration. Full detail: `docs/guides/installation-guide.md`.

**Q: You mention a package (`flutter_llama`) that didn't work at all — what happened?**
A: Its pub.dev release didn't include the `llama.cpp` git submodule its own native build expected (pub.dev doesn't support git submodules), so the source directory its CMake config referenced simply didn't exist — a defect in the package, not something fixable by configuration. It was replaced with `llamadart`, a different, self-contained package, with no cost to application code since nothing yet depended on the old package's API.

**Q: How is business logic tested without a physical Android device?**
A: Repository tests run against a real (in-memory) SQLite database via `sqflite_common_ffi`. Use-case tests use hand-written fake implementations of `SpeechToTextEngine`/`LlmEngine` (`test/test_helpers/fake_ai_engines.dart`) that return canned results or throw on demand — this is exactly what the Clean Architecture interfaces were for. An on-device integration test exists but requires a real device to actually execute.

**Q: Why does the app request microphone permission the way it does?**
A: The `record` package's own `hasPermission()` method handles the OS-level runtime permission request internally; the app doesn't call `permission_handler` for microphone access specifically — it's only declared in the Android manifest (`RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`) so the OS allows requesting it at all.

## Privacy & scope

**Q: What's explicitly out of scope, and why?**
A: Cloud sync, login/accounts, Firebase, Teams/Zoom/Meet/WhatsApp integrations, an enterprise dashboard, and subscription billing — all deliberately excluded because they contradict the project's core premise (nothing leaves the device) or were explicitly named as belonging to a hypothetical commercial version, not this project.

**Q: What data does the app collect or transmit?**
A: None, other than the one-time AI model downloads described above. No analytics, no crash reporting to a third party, no account of any kind. See `docs/legal/privacy-policy.md`.

**Q: What's new since the original nine-phase build, in one sentence each?**
A: Ask AI (on-device Q&A scoped to the user's own meetings); the Conversation Translator (offline, bidirectional, ten-language speech/text translation with TTS, never persisted); notes and mid-recording bookmarks; device-native app lock and a data backup/export flow; and a reliability pass that bounds every AI call and the model download with hard timeouts after a real hang was reported in testing.
