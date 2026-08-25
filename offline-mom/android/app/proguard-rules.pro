# Flutter's own engine/embedding and generated plugin registration.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# dart:ffi-based plugins (whisper_flutter_new, llamadart) have no Kotlin/
# Java glue code at all - Dart calls straight into their bundled .so via
# DynamicLibrary/lookup, not JNI/reflection - so they aren't at risk from
# R8 and need no keep rule here. The plugins below *do* have an Android-
# side Kotlin/Java layer using JNI `native` methods and/or reflection-based
# service discovery, which R8 can strip if nothing else visibly references
# it; keep each plugin's real package (verified against its source, not
# guessed) wholesale rather than individual members.
-keep class xyz.luan.audioplayers.** { *; }
-keep class com.llfbandit.record.** { *; }
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.pravera.flutter_foreground_task.** { *; }

# JNI native method signatures generally, wherever they end up.
-keepclasseswithmembernames class * {
    native <methods>;
}

# sqflite and file_picker's own native-side glue.
-keep class com.tekartik.sqflite.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Keep enum valueOf/values() - Dart<->platform-channel argument codecs and
# a couple of native bindings pass enum names as strings.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Standard Android/Kotlin metadata noise that's safe to drop, but keeping
# it from erroring out the build if referenced.
-dontwarn kotlin.**
-dontwarn org.jetbrains.annotations.**

# The Flutter engine's deferred-components manager references Google Play
# Core's split-install classes unconditionally, even though this app never
# uses dynamic feature modules / deferred components. Without the play-core
# library on the classpath (which we deliberately don't add - it's dead
# weight for an app with no dynamic features), R8 in full mode hard-fails
# on these as "missing classes" rather than just warning. Confirmed safe to
# suppress: PlayStoreDeferredComponentManager is never invoked anywhere in
# this app's code paths.
-dontwarn com.google.android.play.core.**

# read_pdf_text bundles PdfBox-Android (Phase 1A, ADR-016), whose
# JPXFilter.readJPX references com.gemalto.jp2.JP2Decoder - an *optional*,
# separately-licensed third-party JPEG2000 codec PdfBox-Android supports
# but does not bundle, for decoding JPX-encoded images embedded in a PDF.
# This app only ever calls PdfBox-Android's text-extraction API
# (DocumentTextExtractionService/pdf_parser.dart never renders or decodes
# embedded images), so this path is never reached at runtime - confirmed a
# genuine release-build blocker (Product Validation Phase), not fixed by
# adding the jp2 dependency itself (a real, separate license this app has
# no need to take on for a feature it never uses). R8's own generated
# missing_rules.txt suggested exactly this line.
-dontwarn com.gemalto.jp2.JP2Decoder
