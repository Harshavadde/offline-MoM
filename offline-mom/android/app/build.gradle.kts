import com.android.build.api.variant.FilterConfiguration
import com.android.build.api.variant.impl.VariantOutputImpl
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real release signing, read from android/key.properties (gitignored - never
// commit this file or the keystore it points to). Falls back to the debug
// keystore when key.properties doesn't exist, so `flutter build apk --release`
// still works for local testing without a real keystore on hand.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.offlinemomai.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.offlinemomai.app"
        // Pinned to 24, not Flutter's default/21: two bundled plugins declare
        // a higher floor in their own android/build.gradle - ffmpeg_kit_flutter_new
        // requires minSdk 24 and record_android requires minSdk 23. AGP fails
        // the build outright if the app's minSdk is lower than any dependency's,
        // so 21 (or even 23) will not compile with the current plugin set.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Uses the real release keystore once android/key.properties exists;
            // otherwise falls back to the debug keystore (fine for local
            // sideloading only, not for public distribution).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Product validation phase (real-device release prep): measured that a
    // single unsplit release APK bundled native libraries for x86_64
    // (170.8MB), arm64-v8a (164.8MB), AND armeabi-v7a (101.4MB)
    // simultaneously (offline AI inference-engine libraries - llama.cpp's
    // multiple GPU backends plus Google's LiteRT-LM runtime plus FFmpeg -
    // not bundled model weights, which this app downloads separately post
    // -install; see docs/v3/implementation/03-decisions.md). x86_64 is a
    // desktop/emulator architecture that never appears on a real phone,
    // and armeabi-v7a is the obsolete 32-bit ABI virtually no device sold
    // since ~2017 needs. Splitting per-ABI, rather than removing any
    // inference-engine capability, is the safe, official, zero-functional
    // -risk optimization for physical-device testing: the installed
    // arm64-v8a APK loses nothing, it simply stops carrying two other
    // architectures' copies of the same native libraries.
    //
    // Release-readiness audit fix (B2): `isEnable` must stay conditional on
    // the same `split-per-abi` Gradle project property the Flutter Gradle
    // Plugin itself checks (`FlutterPluginUtils.shouldProjectSplitPerAbi`,
    // packages/flutter_tools/gradle/src/main/kotlin/FlutterPluginUtils.kt) -
    // confirmed by reading that plugin's own source. When `--split-per-abi`
    // is NOT passed (every ordinary `flutter build apk`/`flutter run`), the
    // plugin instead populates `defaultConfig.ndk.abiFilters` itself (so
    // Google Play doesn't list architectures this app can't actually run
    // on) - AGP rejects having both `splits.abi` enabled and a differing
    // `ndk.abiFilters` set at once ("Conflicting configuration"). Previously
    // `isEnable` was hardcoded `true` unconditionally, so it collided with
    // the plugin's own abiFilters on every non-split build. Gating it on
    // the identical property the plugin already keys off of means the two
    // mechanisms never disagree about whether a build is being split,
    // restoring plain debug builds without weakening
    // `flutter build apk --release --split-per-abi ...`, which still sets
    // this property and still gets real per-ABI splitting.
    splits {
        abi {
            isEnable = project.findProperty("split-per-abi")?.toString()?.toBoolean() ?: false
            reset()
            include("arm64-v8a", "armeabi-v7a")
            isUniversalApk = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Names every built APK "offlinemomai-<versionCode>-<abi>-<buildType>.apk"
// (e.g. offlinemomai-22-arm64-v8a-release.apk) instead of Gradle/Flutter's
// default "app-release.apk" - so successive builds are distinguishable by
// filename alone, and so the two ABI-split outputs (Product validation
// phase, above) never collide on the same filename - without the `<abi>`
// segment, both split APKs would resolve to the identical output name and
// one would silently overwrite the other on disk. versionCode comes from
// pubspec.yaml's `version: x.y.z+N` (the `+N` part) - bump that each time
// a new build is cut.
androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { output ->
            if (output is VariantOutputImpl) {
                val abi = output.filters
                    .find { it.filterType == FilterConfiguration.FilterType.ABI }
                    ?.identifier
                    ?: "universal"
                output.outputFileName.set(
                    "offlinemomai-${flutter.versionCode}-${abi}-${variant.buildType}.apk"
                )
            }
        }
    }
}

flutter {
    source = "../.."
}
