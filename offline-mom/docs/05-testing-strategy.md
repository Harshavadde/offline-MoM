# Testing Strategy & Test Cases

## Strategy

Three levels, matching what's actually implemented in `test/` and `integration_test/`:

| Level | Tool | What it covers | Needs a device? |
|---|---|---|---|
| Unit | `flutter_test` + `sqflite_common_ffi` | Repositories (real in-memory SQLite) and use cases (fake AI engines) | No |
| Widget | `flutter_test` | Full route-graph smoke test: app boots, every screen renders without throwing | No |
| Integration | `integration_test` | Real app, real plugins, on a physical device/emulator | Yes |

**Why fakes for AI engines, not mocks of the whole app.** `SpeechToTextEngine` and `LlmEngine` are the only two dependencies that require native code (whisper.cpp/llama.cpp) and can't run in a plain `flutter test` process. Everything else — repositories, use-case orchestration, error handling, status transitions — is real code exercised against a real (if in-memory) database. This is precisely what the Clean Architecture abstraction in `lib/services/ai/` was for: `test/test_helpers/fake_ai_engines.dart` provides `FakeSpeechToTextEngine`/`FakeLlmEngine`/`FakeTextToSpeechService` that return canned results or throw on demand, so `TranscribeMeetingUseCase`, `GenerateMeetingSummaryUseCase`, `AskAboutMeetingsUseCase`, and `TranslateAndSpeakUseCase` — the four consumers of `LlmEngine` and/or `TextToSpeechService` — are all tested against their actual orchestration logic, not the AI models.

**A key testing gotcha this project ran into and fixed:** `flutter test` runs under `AutomatedTestWidgetsFlutterBinding`, which does not let genuinely-real async I/O (opening a database/Hive box, real `Timer`s) complete on its own inside a `testWidgets` body — only frame-pump-driven work progresses by default. `test/widget_test.dart` wraps its setup in `tester.runAsync()` for exactly this reason, and uses a bounded manual pump loop (`settle()`) instead of `pumpAndSettle()`, since `pumpAndSettle` only returns once no further frames are scheduled — which never reliably happens when a `FutureProvider` is resolving via real I/O on its own schedule rather than the fake animation clock `pumpAndSettle` expects.

## Test case catalog

### Repository tests (`test/repositories/`)

| File | Test case | Verifies |
|---|---|---|
| `meeting_repository_test.dart` | insert then getById returns the same meeting | Basic round-trip |
| | getById returns null for an unknown id | Not-found handling |
| | getAll orders by createdAt descending | Sort order Home/History rely on |
| | update persists changed fields | Rename/status-transition path |
| | delete removes the meeting | Basic delete |
| | findIdsByTitle matches case-insensitively on substrings | Search by name |
| | findIdsByDateRange only matches meetings within the range | Search by date |
| | getByIds returns matching meetings and ignores an empty set | Search result resolution |
| `transcript_repository_test.dart` | insert then getForMeeting round-trips segments | JSON segment (de)serialization |
| | getForMeeting returns null when no transcript exists | Pre-transcription state |
| | findMeetingIdsByText matches on transcript content | Search by transcript |
| | deleting the meeting cascades to its transcript | FK `ON DELETE CASCADE` |
| `action_item_repository_test.dart` | insertAll then getForMeeting returns items in creation order | Bulk insert + ordering |
| | setCompleted toggles only the targeted item | Checkbox behavior |
| | findMeetingIdsByDescription matches on action item text | Search by action item |
| | deleting the meeting cascades to its action items | FK `ON DELETE CASCADE` |
| `decision_repository_test.dart` | insertAll then getForMeeting returns decisions in creation order | Bulk insert + ordering |
| | findMeetingIdsByDescription matches on decision text | Search by decision |
| | deleting the meeting cascades to its decisions | FK `ON DELETE CASCADE` |

### Use-case tests (`test/use_cases/`)

| File | Test case | Verifies |
|---|---|---|
| `transcribe_meeting_use_case_test.dart` | transcribes successfully: persists transcript, advances to summarizing | Happy path |
| | engine failure marks the meeting as error and persists no transcript | Failure path |
| | does nothing when the meeting has no audio file yet | Precondition guard |
| | does nothing for an unknown meeting id | Precondition guard |
| `generate_meeting_summary_use_case_test.dart` | generates successfully: persists summary/action items/decisions, marks meeting ready | Happy path. Note: the use case's persistence logic for action items/decisions is still exercised here via `FakeLlmEngine` returning them — the real `LlamaDartLlmEngine` never does (see [`ai-architecture.md`](architecture/ai-architecture.md#why-decisions-and-structured-action-items-were-dropped)), so this proves the use case *would* still handle them correctly if an engine ever provided them again, not that production traffic exercises this path |
| | engine failure marks the meeting as error and persists nothing | Failure path (including `LlmTimeoutException`/`LlmModelDownloadTimeoutException`, which reach here the same way any other thrown error does) |
| | does nothing when no transcript exists yet | Precondition guard |
| | a meeting with genuinely no action items/decisions stays ready with empty lists | Distinguishes "AI found none" from "not generated yet" — this is the actual production path now |
| `search_meetings_use_case_test.dart` | empty query returns nothing | Caller falls back to full list |
| | matches by title / transcript / action item / decision / date | Each of the five search sources (the decision source can never actually match in production now, since nothing populates `decisions` — the test still passes because it inserts a fake decision row directly) |
| | matches by transcript text, without duplicating a meeting that also matches by title | Id-union de-duplication |
| | no matches returns an empty list | Empty-state path |
| `delete_meeting_use_case_test.dart` | deletes the meeting row and its audio file | Happy path, real file I/O |
| | deleting a meeting with no audio file does not throw | Precondition guard |
| | deleting a meeting whose audio file is already gone does not throw | Idempotency |
| | deleting an unknown meeting id does not throw | Precondition guard |
| `translate_and_speak_use_case_test.dart` | translates text and speaks the result in the target language | Happy path |
| | does not speak when the target language has no installed voice | `isLanguageAvailable` gate |
| | still returns the translated turn even when speaking fails | TTS is best-effort; a speak failure must never fail the turn |
| | propagates a translation failure instead of returning a turn | Failure path (LLM error, including a timeout) |

### Widget test (`test/widget_test.dart`)

| Test case | Verifies |
|---|---|
| boots to Splash, reaches Home, and every route renders | App boots; every route in [`navigation-flow.md`](architecture/navigation-flow.md) (including `/ask` and `/conversation`) renders without throwing |

### Integration test (`integration_test/app_test.dart`, requires a device)

| Test case | Verifies |
|---|---|
| boots to Home and navigates through the bottom tabs | Real plugins (sqflite/Hive) initialize correctly and bottom-nav works, on an actual device |

## Manual/User Acceptance Testing

Not automatable without a device (see [`docs/guides/installation-guide.md`](guides/installation-guide.md) for why this build environment has none). The following flows should be manually verified on a physical device before considering a release build final:

1. Record a short meeting → verify pause/resume/stop, then that a transcript and summary eventually appear.
2. Import a video file → verify audio is extracted and the same pipeline runs.
3. Search by a word that only appears in a transcript, not any title → verify it's found.
4. Export a meeting to PDF → verify the shared file opens correctly in another app.
5. Delete a meeting → verify it disappears from Home/History and its audio file is gone from storage.
6. Toggle dark mode → verify every screen renders correctly in both themes.
7. On a fresh install, trigger the first-ever AI summary and verify the "Downloading the AI model…" status appears, then generation completes normally.
8. Ask AI: ask a question answerable from an existing meeting, and one that isn't → verify a correct answer and a clear "couldn't find an answer" respectively.
9. Conversation Translator: pick a source/target language pair, do a full round trip (their turn via mic or import, your reply via mic or typed/romanized text), verify translated text and (if a voice is installed for that language) spoken audio on both sides; verify "Clear Conversation" empties the screen.
10. Force a slow/interrupted connection during the first-run model download → verify it fails with a clear, retryable error within the documented timeout window rather than hanging.
