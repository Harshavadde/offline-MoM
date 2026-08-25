# OfflineMoMAI: A Fully On-Device Meeting Transcription, Summarization, and Translation System for Android

*Final-year engineering project report, IEEE conference-paper structure*

## Abstract

Cloud-based meeting assistants transcribe and summarize audio by uploading it to a third-party server, which raises confidentiality concerns for sensitive discussions and imposes recurring per-minute or per-token costs. This paper presents OfflineMoMAI, an Android application that performs an entire meeting-processing pipeline — audio capture, speech-to-text, and AI summarization — on-device, using whisper.cpp for transcription and a quantized Qwen2.5-1.5B-Instruct model via llama.cpp for summarization, question answering, and bidirectional speech/text translation across ten languages. We describe the system's Clean Architecture design, the specific native-toolchain and model-integration challenges encountered building it, the reliability engineering required once a single on-device model began serving three independent features concurrently, and the trade-offs made to keep the AI models small enough to run on commodity Android hardware. The result is a working application with no backend, no user accounts, and no network dependency beyond a one-time model download that is itself bounded by an explicit timeout.

**Index Terms** — on-device machine learning, speech-to-text, large language models, machine translation, mobile computing, privacy-preserving systems, Flutter, whisper.cpp, llama.cpp

## I. Introduction

Commercial meeting-assistant products (Otter.ai, Fireflies, cloud transcription features built into Zoom/Teams) share a common architecture: audio is streamed or uploaded to a vendor's server for processing. For many users — students discussing coursework, researchers handling unpublished data, small teams discussing business terms — this is an unacceptable trust requirement, independent of any specific vendor's stated policies. Separately, these services are metered, making them impractical for occasional, non-commercial use. A related but distinct problem — communicating across a language barrier while traveling with no internet access — shares the same root constraint: existing translation tools assume connectivity.

Advances in model quantization and mobile-optimized inference engines (whisper.cpp [1], llama.cpp [2]) have made it practical to run both automatic speech recognition and small instruction-tuned language models directly on a phone. This project investigates whether that is sufficient to build a genuinely useful meeting assistant — and, using the same on-device model, a bidirectional conversation translator — without any server component at all, and what it takes to make a single shared on-device model reliable once several independent features depend on it simultaneously.

## II. Related Work

Whisper [3] (OpenAI) established transformer-based ASR as competitive with commercial cloud transcription; whisper.cpp [1] is a widely-used C/C++ reimplementation optimized for CPU inference on resource-constrained devices, including mobile ARM CPUs. Qwen2.5 [4] is a family of instruction-tuned language models; this project uses the 1.5B-parameter variant, which is large enough to follow a strict-JSON system prompt and perform passable translation while remaining practical to run entirely on a phone's RAM alongside an Android app process. llama.cpp [2] provides quantized (4-bit and below) inference for GGUF-format models across these constrained environments. This project combines both engines behind a single mobile application, using one shared LLM instance across three distinct features (summarization, retrieval-scoped question answering, and translation), rather than treating any of them as standalone research artifacts.

## III. System Design

### A. Architecture

The application follows Clean Architecture, layered as presentation (MVVM via Riverpod ViewModels) → domain (abstract repository/service interfaces) → data (SQLite/Hive repositories, native AI service implementations), with a Repository pattern isolating storage and AI engines behind interfaces the rest of the app depends on. Dependency injection is handled by Riverpod's provider graph, with a single composition root wiring concrete implementations to their interfaces. Full detail: [`docs/architecture/hld.md`](architecture/hld.md), [`docs/architecture/lld.md`](architecture/lld.md).

### B. Data model

Seven relational entities (meetings, transcripts, summaries, action items, decisions, recording marks, notes) are stored in SQLite with foreign-key cascade deletes; a settings concern uses a key-value store (Hive) rather than a table, since it has no relational structure. The Conversation Translator's session data is deliberately excluded from both: it exists only in memory for the lifetime of the screen and is never written to disk, a stricter privacy posture than the rest of the app, which is local-only but still persistent. Full detail: [`docs/architecture/database-design.md`](architecture/database-design.md).

### C. AI pipeline and shared model

Recording or importing a meeting produces an AAC audio file. A background pipeline (not blocking the UI) re-encodes this to 16kHz mono WAV via ffmpeg (whisper.cpp's native format requirement), transcribes it, then feeds the resulting text to the LLM with a prompt requiring a strict JSON output (summary, minutes of meeting, key topics), which is parsed permissively (extracting the first balanced JSON object from the response) to tolerate a small model occasionally wrapping its output in commentary or markdown fences. An earlier iteration also asked the model for decisions and structured action items in the same call; this was removed after testing showed it made the prompt larger, generation slower, and the JSON more likely to be malformed, for a feature whose value proposition is speed — action items are now entered manually instead.

The same LLM instance additionally backs two other features added after the original meeting pipeline: a retrieval-scoped question-answering feature ("Ask AI," answering only from the user's own meeting transcripts) and a bidirectional Conversation Translator (transcribes or accepts typed/romanized text in a source language, translates via the LLM, and optionally speaks the result aloud via the device's own installed text-to-speech voice). All three features share one `LlamaEngine` instance rather than loading the model multiple times. Full detail: [`docs/architecture/ai-architecture.md`](architecture/ai-architecture.md).

### D. Reliability: bounding a shared, serializing model

`llamadart`'s worker isolate serializes every generation request against one `LlamaEngine` — a new call waits for whatever is currently running rather than being rejected. Once three independent features shared that engine, an unbounded generation call in any one of them could block every AI feature in the application. This was not a theoretical concern: real-device testing surfaced a single stuck summarization call blocking the pipeline for over eight hours on a seven-second recording. The fix applies two independent, purpose-built timeouts: a per-event-gap stall timeout (45 seconds without a new token) around every generation call, which cancels the underlying native generation on expiry so the engine is actually freed rather than merely abandoned by the caller; and a separate pair of timeouts (a 90-second stall detector and a 15-minute absolute cap) around the one-time model download itself, which has its own, independent hang risk from a slow or throttled network connection. Both failure modes now surface as a specific, retryable exception type through the application's existing error-handling UI, rather than an indefinite spinner.

## IV. Implementation

The application is built in Flutter/Dart, targeting Android. Native AI functionality is accessed via FFI-based Flutter plugin wrappers (`whisper_flutter_new`, `llamadart`) rather than hand-written platform channels, trading some control for substantially less native-code maintenance burden appropriate to a project of this scope.

A significant portion of implementation effort went into resolving native-toolchain incompatibilities rather than application logic: several required plugins targeted a materially newer Android Gradle Plugin generation than the project's initial Flutter SDK supported, one candidate package (`flutter_llama`) proved to have a structurally broken native build (a missing vendored dependency, not fixable by configuration), and Android Gradle Plugin 9's "Built-in Kotlin" transition created a real conflict between plugins that had and hadn't yet migrated to it. These are documented in detail in [`docs/guides/installation-guide.md`](guides/installation-guide.md) as a record of concrete, reproducible engineering problems and their resolutions, since they consumed substantial effort and are likely to recur for any project combining several actively-developed native AI plugins.

## V. Evaluation

Automated testing covers repository CRUD and search logic against a real (in-memory) SQLite database, and use-case orchestration (transcription, summary generation, question answering, translation-plus-speech, search, deletion) against fake implementations of the native AI/TTS engines — chosen specifically so business logic is verified deterministically without requiring a physical device. A route-graph smoke test confirms every screen in the application renders without error. An on-device integration test is included but could not be executed in this project's build environment, which had no Android emulator or connected device available (see [`docs/guides/installation-guide.md`](guides/installation-guide.md)); it is intended to be run by whoever has physical hardware available. Full detail and rationale: [`docs/05-testing-strategy.md`](05-testing-strategy.md).

Real-device testing, once performed, surfaced two defects that automated testing alone had not: an 8-hour-plus hang in the summarization pipeline (traced to the shared, serializing LLM engine having no bound on a stuck generation call — Section III-D), and a first-run model download that could take 45 minutes with no feedback on whether it was progressing or stuck. Both were root-caused and fixed with explicit timeouts; both fixes are covered by the automated suite where the logic is deterministic (timeout-triggering behavior), though the underlying model/network conditions that caused them are inherently better validated on-device than in a fake-engine unit test.

Manual, on-device validation of transcription/summarization/translation *quality* (as opposed to reliability), battery/thermal impact of local inference, and end-to-end latency across a wider range of devices remain outstanding and are the most important next steps before considering this production-ready — see Future Scope.

## VI. Conclusion

OfflineMoMAI demonstrates that a complete meeting-transcription-and-summarization pipeline, plus retrieval-scoped question answering and bidirectional speech translation, can run entirely on an Android device using presently-available open-source models and inference engines, without a backend of any kind. The primary engineering cost was not application logic but two distinct classes of problem: native-toolchain integration across several independently-evolving AI plugin projects, and — once a single on-device model came to serve three separate features — reliability engineering to ensure no combination of a slow network or a stuck generation call could hang the application indefinitely. The primary quality trade-off remains model size: a small, quantized model was chosen deliberately, at a documented cost to summary and translation quality, to keep the system usable on modest hardware. Future work (Section [`06-risk-and-future-scope.md`](06-risk-and-future-scope.md)) focuses on configurable/larger model quality and validating the current design under real on-device conditions at scale.

## References

[1] G. Gerganov, "whisper.cpp," GitHub repository, https://github.com/ggerganov/whisper.cpp
[2] G. Gerganov, "llama.cpp," GitHub repository, https://github.com/ggerganov/llama.cpp
[3] A. Radford et al., "Robust Speech Recognition via Large-Scale Weak Supervision," OpenAI, 2022.
[4] A. Yang et al., "Qwen2.5 Technical Report," arXiv:2412.15115, 2024.
