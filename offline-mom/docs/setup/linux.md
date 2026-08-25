# Environment Setup — Linux

Everything below sets up a Linux machine from scratch to build and run OfflineMoMAI (an Android app; no desktop/web target on this project, so you only need the Android toolchain, not any Linux-desktop Flutter dependencies).

Commands below target **Debian/Ubuntu** (`apt`) as the primary path, since it's the most common Linux desktop/dev setup. If you're on Fedora, Arch, or another distro, substitute the equivalent package-manager commands for steps 1–2 (`dnf`/`pacman`/etc.) — everything from step 3 onward (Android Studio, Flutter, the repo) is distro-agnostic.

## System requirements

| | Minimum |
|---|---|
| OS | A recent 64-bit Linux distro (Ubuntu 20.04+ or equivalent) |
| RAM | 8 GB (16 GB strongly recommended — Android builds and an emulator together are heavy) |
| Disk space | ~15 GB free (Flutter SDK ~1 GB, Android Studio + SDK/NDK ~8 GB, Gradle caches ~2–3 GB, this repo + build output ~1 GB, plus the app's own ~1.25 GB one-time AI model download if you run it) |
| Other | `curl`, `unzip`, `git`, and 64-bit `libc`/`libstdc++` (already present on almost any desktop distro) |

## 1. Install prerequisites

```bash
sudo apt update
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev
```

`clang`/`cmake`/`ninja-build` are required by Flutter's own tooling even though this project only builds for Android (Flutter's build system uses them internally); `libgtk-3-dev`/`libglu1-mesa` satisfy `flutter doctor`'s Linux toolchain check.

## 2. Install a JDK (Java 17)

```bash
sudo apt install -y openjdk-17-jdk
```

Verify:

```bash
java -version
```

If multiple JDKs are installed and the wrong one is default, run `sudo update-alternatives --config java` and pick the 17 entry.

## 3. Install Android Studio (gives you the Android SDK, NDK, and an emulator manager)

Download and extract (check [developer.android.com/studio](https://developer.android.com/studio) for the current download link, or use your distro's package if it has one, e.g. `sudo snap install android-studio --classic` on Ubuntu):

```bash
sudo snap install android-studio --classic
```

Launch it (`android-studio` from a terminal, or your app launcher) and complete the setup wizard (accept the default SDK install location, `~/Android/Sdk`). Then install this project's specific version requirements via **Settings → Languages & Frameworks → Android SDK** ("Show Package Details" checkbox to see individual versions):

- **SDK Platform**: Android 36 (API 36)
- **Build-Tools**: 28.0.3 **and** 36.0.0 (both — different plugins in this project pin different minimums)
- **NDK (Side by side)**: 27.0.12077973
- **CMake**: 3.18.1 **and** 3.22.1 (both)

If you skip pre-installing these, `flutter build apk` will generally still work — Gradle will prompt/auto-download what it needs the first time — but pre-installing avoids a build failing partway through on a slow connection.

## 4. Download and install the Flutter SDK

Clone it to its own folder you control, rather than relying on a distro package, so it can't collide with a different Flutter project's version requirements on the same machine (see the note at the bottom of this file). Cloning the `stable` branch always gets you the current stable release, satisfying this project's **Flutter 3.44+ / Dart 3.12+** requirement:

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter_stable
```

Add it to your PATH (append to `~/.bashrc`, or `~/.zshrc` if you use zsh):

```bash
echo 'export PATH="$HOME/flutter_stable/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
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

Keep re-running `flutter doctor` until the Android toolchain line shows a checkmark. It's fine if the "Linux desktop" or "Chrome" lines show warnings/missing — this project doesn't target Linux desktop or web.

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

You need either a physical Android device (USB debugging enabled — on Linux you may also need a `udev` rule for your device, which `flutter doctor` will point out if missing) or an emulator (create one via Android Studio's **Device Manager**; enable KVM first for acceptable emulator speed: `sudo apt install -y qemu-kvm` and add your user to the `kvm` group with `sudo usermod -aG kvm $USER`, then log out/in).

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
