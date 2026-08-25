# Installation Guide

## Prerequisites

- Flutter **3.44+** / Dart **3.12+** (see "Why a specific Flutter version matters" below — this project needed a newer SDK than a generic `flutter --version` check might suggest)
- Android SDK with **platform 36**, **build-tools 28.0.3 and 36.0.0**
- Android **NDK 27.0.12077973**
- **CMake 3.18.1 and 3.22.1** (both — different native plugins pin different minimums)
- JDK 17

## Setup

```bash
flutter pub get
flutter doctor --android-licenses   # accept licenses if not already done
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK lands at `build/app/outputs/flutter-apk/app-debug.apk`. Install it on a device with `adb install` or by transferring the file directly.

## First run

> **Sync note (documentation synchronization pass):** the Conversation Translator mentioned in an earlier version of this section has been removed from the app; it is not one of the features that can trigger a first-run model download any more.

Mandatory onboarding walks the user through downloading the AI models the app needs before unlocking the rest of the app: Whisper (a user-selectable tier, `tiny` through `large-v2`, ~75MB-~3GB), the chat/summarization LLM (Qwen2.5-1.5B-Instruct Q4_K_M, ~1.1GB), and the embedding model that powers chat retrieval (embeddinggemma-300M, ~300MB) — all from Hugging Face, cached in app-private storage. This requires an internet connection **once per model** — Wi-Fi is strongly recommended for the larger downloads; every subsequent transcription/summarization/chat is fully offline. Make sure the test device has enough free storage for whichever model tiers are installed, plus room for recordings and imported documents. Both the download and every LLM/embedding call are bounded by hard timeouts (see [`ai-architecture.md`](../architecture/ai-architecture.md#the-llm-request-queue-and-reliability)), so a bad connection fails cleanly with a retry option instead of hanging. Individual models can also be downloaded, switched, or deleted later from Settings → AI Models.

## Build artifacts and naming

`android/app/build.gradle.kts` customizes the release/debug APK's output filename via AGP's Variant API to `offlinemom-<build-number>-<buildType>.apk` (the build number is `pubspec.yaml`'s `version: 1.0.0+N`), landing at `build/app/outputs/apk/<buildType>/`. Flutter's own tooling *additionally* always copies a fixed-name `app-<buildType>.apk` to `build/app/outputs/flutter-apk/` regardless of this customization — that's unavoidable, hardcoded Flutter SDK behavior, not a build misconfiguration; use the custom-named file under `apk/<buildType>/` as the authoritative, versioned artifact.

`minSdk` is pinned at **24**, not a lower value — `ffmpeg_kit_flutter_new` requires 24 and `record_android` requires 23 in their own `build.gradle`; AGP fails the build outright if the app's `minSdk` is lower than any dependency's.

Release builds enable ProGuard/R8 minification (`isMinifyEnabled = true`), which requires an explicit `-keep` rule (`android/app/proguard-rules.pro`) for every plugin with native Kotlin/Java glue code — currently `audioplayers`, `record`, `ffmpeg_kit_flutter_new`, `local_auth`, `permission_handler`, `sqflite`, `file_picker`, and `flutter_tts`. Purely `dart:ffi`-based plugins (`whisper_flutter_new`, `llamadart`) need no keep rules, since they have no Kotlin/Java glue layer at all. Debug/profile builds get `android.permission.INTERNET` auto-injected by Flutter's own manifest overlays; **release builds do not** — it's declared explicitly in the main `AndroidManifest.xml` for exactly this reason, after a release build shipped without network access for the model download and failed with a DNS-lookup error. `flutter_tts` additionally needs a `<queries>` entry for `android.intent.action.TTS_SERVICE` (Android 11+ package visibility), also in the main manifest, or voice discovery can silently fail even with a voice installed.

## Why a specific Flutter version matters (and other toolchain notes)

This project's native AI dependencies (`record`, `ffmpeg_kit_flutter_new`, and originally `flutter_llama`) required a materially newer Android/Gradle toolchain generation than an older Flutter SDK ships by default. If you hit build errors referencing a plugin's `compileSdk`/`flutter` extension, a missing Kotlin plugin, or CMake version mismatches, it is almost certainly this class of issue rather than a mistake in this project's own code.

**A second, fully isolated Flutter SDK was installed specifically for this project** (on the machine this was developed on, at `C:\flutter_stable`) rather than upgrading the shared, pre-existing Flutter install (`C:\flutter`) in place — that shared install is a hard dependency of an unrelated project on the same machine, and upgrading it in place would have risked breaking that project's build for no benefit to this one. If you're setting this up on a similar shared machine, install a second SDK the same way rather than mutating whatever `flutter` already resolves to on `PATH`; invoke the isolated SDK's binary by its full path (e.g. `C:\flutter_stable\bin\flutter`) for every command in this project rather than relying on `PATH`, which may still point at the older shared install.

Concretely, this project pins:

- **Android Gradle Plugin 8.9.2**, not the newer 9.x line. AGP 9 introduces a "Built-in Kotlin" compilation mode; some plugins in this project's dependency tree have migrated to expect it (`file_picker` 11+) while others (`ffmpeg_kit_flutter_new`, `record_android`, `share_plus`) have not, and the two groups want opposite `android.builtInKotlin` settings under AGP 9. Staying on AGP 8.9.2 keeps every plugin on the same (older) Kotlin-application mechanism, avoiding the conflict entirely.
- **Gradle 9.1.0** (the wrapper version), compatible with AGP 8.9.2 in this configuration.
- NDK **27.0.12077973** and two CMake versions as listed above — different plugins' native builds pin different exact minimums; both were installed side-by-side (additively; installing a version doesn't remove another).

If you're setting this up on a shared or resource-constrained machine, also budget for Gradle's memory use: a full build with all three native AI plugins compiling from scratch briefly needs a few GB of heap. `android/gradle.properties` in this project caps `org.gradle.jvmargs` deliberately (rather than leaving Gradle's default, much larger, heap) and disables the persistent Gradle daemon (`org.gradle.daemon=false`), because the machine this project was originally built on was shared with other workloads and a default-configured Gradle daemon caused system-wide memory exhaustion during development. If you have a dedicated, resourced build machine, you can likely raise these limits for faster builds — see the comments in that file.

### A dead-end package worth knowing about

`flutter_llama` (an early candidate for llama.cpp bindings) is not usable as published on pub.dev: its native CMake build references a `llama.cpp` git submodule that the published package doesn't include (pub.dev doesn't support git submodules), so the referenced source directory doesn't exist on a normal `pub get`. This project uses `llamadart` instead — see [`docs/architecture/ai-architecture.md`](../architecture/ai-architecture.md) for the full story.

## Running on a device without an emulator

If you don't have an Android emulator available, build the debug or release APK as above and sideload it onto a physical device with USB debugging enabled (`adb install build/app/outputs/flutter-apk/app-debug.apk`), or transfer the file another way (e.g. via a messaging app) and install it directly from the device's file manager (enable "install from unknown sources" for that one install if prompted).

## Running the test suites

```bash
flutter analyze                       # static analysis
flutter test                          # unit + widget tests (no device needed)
flutter test integration_test/app_test.dart -d <device-id>   # needs a connected device/emulator
```
