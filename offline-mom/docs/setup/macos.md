# Environment Setup — macOS

Everything below sets up a Mac from scratch to build and run OfflineMoMAI (an Android app — you're building *for* Android *on* macOS; no Xcode/iOS setup is needed since this project doesn't target iOS).

All commands are for the default **zsh** shell (macOS's default since Catalina). If you're still on bash, they work the same way.

## System requirements

| | Minimum |
|---|---|
| OS | macOS 12 (Monterey) or newer |
| Chip | Apple Silicon (M1+) or Intel — both work; Android Studio and Flutter are universal |
| RAM | 8 GB (16 GB strongly recommended — Android builds and an emulator together are heavy) |
| Disk space | ~15 GB free (Flutter SDK ~1 GB, Android Studio + SDK/NDK ~8 GB, Gradle caches ~2–3 GB, this repo + build output ~1 GB, plus the app's own ~1.25 GB one-time AI model download if you run it) |

## 1. Install Homebrew (skip if `brew --version` already works)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the printed instructions to add `brew` to your PATH if it's a fresh install (Homebrew's installer tells you the exact lines to add to `~/.zprofile`).

## 2. Install Git and a JDK (Java 17)

```bash
brew install git
brew install openjdk@17
```

Link the JDK so `java`/`javac` resolve to it (Homebrew installs it "keg-only" by default):

```bash
sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk
```

> On an Intel Mac, Homebrew's prefix is `/usr/local` instead of `/opt/homebrew` — adjust the path above accordingly (`brew --prefix` tells you which one you're on).

Verify:

```bash
java -version
```

## 3. Install Android Studio (gives you the Android SDK, NDK, and an emulator manager)

```bash
brew install --cask android-studio
```

Launch Android Studio once from Spotlight/Applications and complete the setup wizard (accept the default SDK install location, `~/Library/Android/sdk`). Then install this project's specific version requirements via **Android Studio → Settings → Languages & Frameworks → Android SDK** ("Show Package Details" checkbox to see individual versions):

- **SDK Platform**: Android 36 (API 36)
- **Build-Tools**: 28.0.3 **and** 36.0.0 (both — different plugins in this project pin different minimums)
- **NDK (Side by side)**: 27.0.12077973
- **CMake**: 3.18.1 **and** 3.22.1 (both)

If you skip pre-installing these, `flutter build apk` will generally still work — Gradle will prompt/auto-download what it needs the first time — but pre-installing avoids a build failing partway through on a slow connection.

## 4. Download and install the Flutter SDK

Don't install Flutter via Homebrew for this project — clone it to its own folder you control, so it can't collide with a different Flutter project's version requirements on the same machine (see the note at the bottom of this file). Cloning the `stable` branch always gets you the current stable release, satisfying this project's **Flutter 3.44+ / Dart 3.12+** requirement:

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter_stable
```

Add it to your PATH (append to `~/.zprofile` so it's permanent):

```bash
echo 'export PATH="$HOME/flutter_stable/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

Verify:

```bash
flutter --version
```

## 5. Run Flutter's doctor and accept Android licenses

```bash
flutter doctor
flutter doctor --android-licenses
```

Keep re-running `flutter doctor` until the Android toolchain line shows a checkmark. It's fine if the "Xcode" or "Chrome" lines show warnings — this project doesn't target iOS or web.

## 6. Clone the repo and get dependencies

```bash
git clone https://github.com/kala-techies/offline-mom.git
cd offline-mom/offline_mom
flutter pub get
```

## 7. Verify the build

```bash
flutter analyze
flutter test
flutter build apk --debug
```

If `flutter analyze` reports issues or `flutter test` fails, something in the toolchain setup above is off — see [`../guides/installation-guide.md`](../guides/installation-guide.md) for known, previously-hit toolchain problems (AGP version conflicts, a dead-end package, memory limits on shared machines) and how they were resolved on this exact project.

## Running the app

You need either a physical Android device (USB debugging enabled, connected and trusted) or an emulator (create one via Android Studio's **Device Manager** — on Apple Silicon, pick an **arm64** system image).

```bash
flutter devices          # confirms a device/emulator is detected
flutter run               # debug build, hot reload
# or, for a release build:
flutter build apk --release
```

The release APK lands at `build/app/outputs/apk/release/offlinemomai-<N>-release.apk` (see [`../guides/installation-guide.md`](../guides/installation-guide.md#build-artifacts-and-naming) for why there's also a fixed-name copy under `build/app/outputs/flutter-apk/`).

**First run of the app** downloads two AI models (~1.25 GB total) the first time you record/transcribe — this needs an internet connection once (Wi-Fi recommended); everything after that runs fully offline. See [`../guides/user-guide.md`](../guides/user-guide.md).

## If you already have Flutter installed for another project

Don't upgrade that install in place if this project's version requirement differs from what the other project needs — clone this project's Flutter SDK to its own folder (e.g. `~/flutter_stable`, as above) and invoke it by its **full path** for this project (`~/flutter_stable/bin/flutter ...`) rather than relying on whichever `flutter` your `PATH` resolves to. This project was itself originally built this way, alongside another project's SDK that couldn't be touched — see [`../guides/installation-guide.md`](../guides/installation-guide.md) for the full reasoning.
