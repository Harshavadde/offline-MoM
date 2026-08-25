# Environment Setup — Windows

Everything below sets up a laptop from scratch to build and run OfflineMoMAI (an Android app; you don't need a physical Android device to build it, but you do need one, or an emulator, to actually run it — see [Running the app](#running-the-app)).

All commands are **PowerShell** (not Command Prompt / cmd.exe). Open PowerShell, then paste each block in order. Restart PowerShell after any step that sets an environment variable, so the new value takes effect.

## System requirements

| | Minimum |
|---|---|
| OS | Windows 10 64-bit (2004+) or Windows 11 |
| RAM | 8 GB (16 GB strongly recommended — Android builds and an emulator together are heavy) |
| Disk space | ~15 GB free (Flutter SDK ~1 GB, Android Studio + SDK/NDK ~8 GB, Gradle caches ~2–3 GB, this repo + build output ~1 GB, plus the app's own ~1.25 GB one-time AI model download if you run it) |
| Git | Any recent version |

## 1. Install Git (skip if `git --version` already works)

```powershell
winget install --id Git.Git -e --source winget
```

## 2. Install a JDK (Java 17)

Android's Gradle build needs a JDK. Android Studio can install one for you (next step), but installing it explicitly is more reliable:

```powershell
winget install --id Microsoft.OpenJDK.17 -e
```

Verify:

```powershell
java -version
```

## 3. Install Android Studio (gives you the Android SDK, NDK, and an emulator manager)

```powershell
winget install --id Google.AndroidStudio -e
```

Launch Android Studio once from the Start menu and complete the setup wizard (accept the default SDK install location). This installs the Android SDK to `%LOCALAPPDATA%\Android\Sdk` and lets you install exact platform/tool versions via **Tools → SDK Manager**.

This project has specific version requirements — install these through the SDK Manager (SDK Platforms tab + SDK Tools tab, "Show Package Details" checkbox to see individual versions):

- **SDK Platform**: Android 36 (API 36)
- **Build-Tools**: 28.0.3 **and** 36.0.0 (both — different plugins in this project pin different minimums)
- **NDK (Side by side)**: 27.0.12077973
- **CMake**: 3.18.1 **and** 3.22.1 (both)

If you skip pre-installing these, `flutter build apk` will generally still work — Gradle will prompt/auto-download what it needs the first time — but pre-installing avoids a build failing partway through on a slow connection.

## 4. Download and install the Flutter SDK

Do **not** install Flutter via `winget`/`choco` for this project — you want a specific, isolated folder you control, in case you ever work on another Flutter project on the same machine with different version requirements (see the note at the bottom of this file). Cloning the `stable` branch (rather than downloading a specific zip) always gets you the current stable release, which satisfies this project's **Flutter 3.44+ / Dart 3.12+** requirement:

```powershell
git clone https://github.com/flutter/flutter.git -b stable C:\flutter_stable
```

Add it to your PATH for the current session and permanently:

```powershell
$env:Path = "C:\flutter_stable\bin;$env:Path"
[Environment]::SetEnvironmentVariable("Path", "C:\flutter_stable\bin;" + [Environment]::GetEnvironmentVariable("Path", "User"), "User")
```

Close and reopen PowerShell, then verify:

```powershell
flutter --version
```

## 5. Run Flutter's doctor and accept Android licenses

```powershell
flutter doctor
flutter doctor --android-licenses
```

Keep re-running `flutter doctor` until the Android toolchain line shows a checkmark. It's fine if the "Chrome" or "Visual Studio" lines show warnings — this project doesn't target web or Windows desktop.

## 6. Clone the repo and get dependencies

```powershell
git clone https://github.com/kala-techies/offline-mom.git
cd offline-mom\offline_mom
flutter pub get
```

## 7. Verify the build

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

If `flutter analyze` reports issues or `flutter test` fails, something in the toolchain setup above is off — see [`../guides/installation-guide.md`](../guides/installation-guide.md) for known, previously-hit toolchain problems (AGP version conflicts, a dead-end package, memory limits on shared machines) and how they were resolved on this exact project.

## Running the app

You need either a physical Android device (USB debugging enabled) or an emulator (create one via Android Studio's **Device Manager**).

```powershell
flutter devices          # confirms a device/emulator is detected
flutter run               # debug build, hot reload
# or, for a release build:
flutter build apk --release
```

The release APK lands at `build\app\outputs\apk\release\offlinemomai-<N>-release.apk` (see [`../guides/installation-guide.md`](../guides/installation-guide.md#build-artifacts-and-naming) for why there's also a fixed-name copy under `build\app\outputs\flutter-apk\`).

**First run of the app** downloads two AI models (~1.25 GB total) the first time you record/transcribe — this needs an internet connection once (Wi-Fi recommended); everything after that runs fully offline. See [`../guides/user-guide.md`](../guides/user-guide.md).

## If you already have Flutter installed for another project

Don't upgrade that install in place if this project's version requirement differs from what the other project needs — install this project's Flutter SDK to its own folder (e.g. `C:\flutter_stable`, as above) and invoke it by its **full path** for this project (`C:\flutter_stable\bin\flutter.bat ...`) rather than relying on whichever `flutter` your `PATH` resolves to. This project was itself originally built this way, alongside another project's SDK that couldn't be touched — see [`../guides/installation-guide.md`](../guides/installation-guide.md) for the full reasoning.
