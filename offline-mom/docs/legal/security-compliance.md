# Security Compliance Statement

## Threat model

OfflineMoMAI has an unusually small attack surface because it has no server and no network protocol of its own: the only network access is a one-time, unauthenticated HTTPS download of public AI model files from Hugging Face. The realistic threats are therefore local, not remote:

| Threat | Applicable? | Mitigation |
|---|---|---|
| Network interception of meeting data | No | Meeting data is never transmitted |
| Server-side data breach | No | No server exists |
| Malicious/compromised backend | No | No backend exists |
| Another app on the same device reading meeting data | Yes (in principle) | Data lives in Android's app-private storage (`getApplicationDocumentsDirectory()`/`getApplicationSupportDirectory()`), which the OS sandboxes from other apps without root/a compromised OS |
| Physical device access (lost/stolen phone, unlocked) | Yes | See "Known gap" below — not currently mitigated at the data layer; App lock (Settings) gates access to the app itself via the device's own biometric/PIN check |
| Malicious file import (crafted audio/video) | Yes (in principle) | Handled by ffmpeg/whisper.cpp's own input parsing; the app does not parse untrusted file formats itself |
| Dependency supply-chain risk | Yes (in principle) | See "Dependency hygiene" below |

## Known gap: no at-rest encryption

The SQLite database and Hive box are **not** encrypted independently of Android's own device/file-system-level encryption (which is enabled by default on modern Android but is a device-level setting, not something this app adds). A stolen, unlocked device would expose meeting content to anyone with file-system access. Adding SQLCipher or Hive's built-in AES encryption (`Hive.openBox(..., encryptionCipher: ...)`) is a reasonable hardening step for a future iteration; it wasn't implemented in this build to keep scope focused on the core offline pipeline (see [`docs/06-risk-and-future-scope.md`](../06-risk-and-future-scope.md)).

## Dependency hygiene

- All dependency versions are pinned in `pubspec.yaml`/`pubspec.lock` — no floating version ranges resolved arbitrarily at build time.
- One dependency (`flutter_llama`) was evaluated and rejected after discovering its published package was structurally broken (missing a vendored native dependency) — see [`docs/architecture/ai-architecture.md`](../architecture/ai-architecture.md). This is documented as evidence that dependencies were reviewed, not blindly trusted.
- No dependency was patched in place inside the local package cache — every fix is a version pin or package substitution recorded in `pubspec.yaml`, so the build reproduces identically on another machine.
- Every plugin with native Kotlin/Java glue code (as opposed to pure `dart:ffi` plugins like `whisper_flutter_new`/`llamadart`, which need none) has an explicit ProGuard `-keep` rule for release-build minification, added and verified against the plugin's real package name rather than guessed — most recently `flutter_foreground_task` (`com.pravera.flutter_foreground_task`) for the opt-in background-download service.

## Permissions

The app requests exactly two runtime-sensitive permissions, both scoped to the feature that needs them (see [`docs/03-srs.md`](../03-srs.md)):
- `RECORD_AUDIO` / `MODIFY_AUDIO_SETTINGS` — requested only when the user taps "Start recording."
- File access for import/export — handled via the system file picker (`file_picker`) and share sheet (`printing`), which don't require broad storage permissions on modern Android.

## Input validation

Audio/video file format is constrained to an explicit allow-list at the file-picker level (MP3, WAV, M4A, AAC, MP4, MKV, MOV); anything else is not selectable. ffmpeg and whisper.cpp handle the actual file parsing and are the responsibility of their upstream projects for malformed-input robustness.

## Compliance scope

OfflineMoMAI does not currently claim formal certification against any specific regulatory framework (GDPR, HIPAA, SOC 2, etc.). Its zero-data-transmission design would make several of those frameworks' core obligations (data transfer restrictions, breach notification for transmitted data) trivially satisfied by construction, since there is no transmission of personal/meeting data for a breach to expose in the first place — but that is not the same as a formal compliance certification, which has not been sought and would require independent audit to claim.
