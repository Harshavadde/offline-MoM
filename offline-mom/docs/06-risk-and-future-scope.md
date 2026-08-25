# Risk Analysis & Future Scope

## Risk analysis

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | The LLM produces a low-quality, malformed, or (for the Translator) garbled/hallucinated output | High | Medium | Strict-JSON parsing degrades gracefully for summaries (`LlmResponseFormatException` with retry, rather than crashing); documented trade-off in [`ai-architecture.md`](architecture/ai-architecture.md); a larger model is the known quality upgrade path (see Future Scope) — this is an acknowledged, inherent limitation of running a 1.5B model on-device, not something considered "fixed" |
| R2 | whisper.cpp/llama.cpp native inference is too slow or drains battery on a low-end device | Medium | Medium | `base`/Qwen2.5-1.5B chosen specifically as small-but-capable models; runs in the background, not blocking the UI |
| R3 | ~~First-run model download fails or is very slow on a poor connection~~ — **occurred in real testing** (reported hang of 45+ minutes with no feedback) | ~~Medium~~ Confirmed | Medium | **Mitigated**: a 90s stall detector + 15-minute absolute cap now bound the download (`LlmModelDownloadTimeoutException`), and a distinct "Downloading the AI model…" status replaces the ambiguous generic spinner — see [`ai-architecture.md`](architecture/ai-architecture.md#reliability-timeouts-and-cancellation). Still no byte-level progress percentage — see Future Scope |
| R3b | A stuck LLM *generation* call (not just the download) hangs indefinitely, and — because the engine is now shared across summary/Ask AI/Translator — blocks every AI feature app-wide | Medium | High | **Occurred and fixed**: reported as an 8-hour-plus hang on a 7-second recording. A 45s stall timeout now cancels and frees the shared engine (`LlmTimeoutException`) — see [`ai-architecture.md`](architecture/ai-architecture.md#reliability-timeouts-and-cancellation) |
| R4 | Native plugin/Android-toolchain incompatibility (encountered repeatedly during this build - see the installation guide) | High (already occurred) | High | Pinned, tested dependency versions in `pubspec.lock`; documented AGP/NDK/CMake versions in the installation guide so the build reproduces elsewhere |
| R5 | A meeting's audio file is lost/corrupted, orphaning a `Meeting` row with no source audio | Low | Medium | `Meeting.status` model doesn't currently have an explicit "audio missing" state; a future migration could add one |
| R6 | Device storage fills up (models + many long recordings) | Medium | Medium | Delete-meeting flow frees both DB rows and the audio file; the Storage settings screen shows model cache size and lets the user clear it independently of app data |
| R7 | A very long meeting's transcript is truncated for summarization (context-window cap, ~4000 chars) | Medium | Low-Medium | Documented in `ai-architecture.md`; chunk-and-reduce summarization noted as future work |
| R8 | Conversation Translator mistranslation in a real conversation (wrong meaning conveyed to a stranger, not just an inconvenience like a bad meeting summary) | Medium | Medium-High | Both bubbles always show the plain-text translation the TTS is reading, so a garbled result is at least visible/readable rather than only heard; no confidence indicator or back-translation check exists yet — see Future Scope |
| R9 | This is a college project built primarily via an AI coding assistant | N/A | N/A | Disclosed in project materials as appropriate to the institution's policy; not a technical risk to the software itself |

## Future scope

Explicitly deferred, in rough priority order:

1. **Configurable AI models.** Let the user pick a larger/smaller Whisper size and a different/larger LLM from Settings, trading download size/speed for quality, rather than hardcoding `base`/Qwen2.5-1.5B — the most direct lever on both summary quality (R1) and translation quality (R8).
2. **Bundle AI models inside the APK**, trading a much larger install (~1.7GB+) for zero network dependency ever, not even once — explicitly deferred as a product decision, not yet resolved either way.
3. **Chunked summarization for long meetings**, instead of truncating the transcript at ~4000 characters — map-reduce style: summarize chunks, then summarize the summaries.
4. **Byte-level download progress** (percentage/MB) for the first-run model downloads — currently there's a status message and a bounded timeout (see R3), but no numeric progress indicator.
5. **Speaker diarization** (who said what), which whisper.cpp does not provide out of the box.
6. **Back-translation or a confidence indicator for the Conversation Translator** (R8) — e.g. silently re-translating the output back to the source language so the user can sanity-check it before speaking.
7. **Re-introducing AI-extracted action items/decisions**, if a future larger model can do so reliably without the speed/malformed-JSON cost that got them removed this iteration (see [`ai-architecture.md`](architecture/ai-architecture.md#why-decisions-and-structured-action-items-were-dropped)) — the `owner`/`dueDate` fields already exist on `ActionItem` for exactly this, unused today since items are manually entered.
8. **iOS support** — whisper_flutter_new, llamadart, and flutter_tts all support iOS; this project targeted Android only per the original scope.

## What will never be added (by design, not oversight)

Cloud sync, login/accounts, Firebase, Teams/Zoom/Meet/WhatsApp integrations, an enterprise dashboard, subscription billing. See [`01-executive-summary.md`](01-executive-summary.md) for why.
