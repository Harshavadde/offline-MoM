/// App-wide constant values that don't belong to any single feature.
class AppConstants {
  AppConstants._();

  static const String appName = 'OfflineMoMAI';

  /// Shown on the splash screen and About (Phase 8B.5: broadened from "Your
  /// Meetings..." to "Your Work..." - the splash/About tagline was still
  /// meetings-only branding, inconsistent with this app's own repositioning
  /// across Phases 8B.1-8B.3 from a meeting recorder into a workspace that's
  /// equally about documents and AI chat).
  static const String appTagline = 'Your Work. Your Device. Your Privacy.';
  static const String appVersion = '1.0.0';

  static const String sqliteDbName = 'offline_mom.db';
  static const int sqliteDbVersion = 21;

  static const String hiveSettingsBoxName = 'settings_box';

  /// How long a model-backed AI engine (chat LLM, embedding model) may sit
  /// idle - no in-flight caller - before [ModelLifecycleManager]
  /// (services/ai/model_lifecycle_manager.dart, Phase 3A) unloads it to
  /// free its native memory. Five minutes: long enough that a user
  /// reading a just-generated summary or thinking about their next chat
  /// question doesn't trigger a reload on their very next action, short
  /// enough that leaving the app idle in the background doesn't keep a
  /// ~1GB+ model resident indefinitely.
  static const Duration modelIdleUnloadTimeout = Duration(minutes: 5);

  /// The minimum bound on [WhisperSpeechToTextEngine]'s transcription
  /// timeout (V2.1 Production Hardening - see ai-architecture.md),
  /// regardless of how short the audio is - covers the fixed model-load
  /// and inference-startup overhead a very short recording wouldn't
  /// otherwise budget for.
  static const Duration whisperTranscriptionTimeoutFloor = Duration(minutes: 5);

  /// How many times an audio recording's own duration
  /// [WhisperSpeechToTextEngine]'s transcription timeout allows before
  /// treating the native whisper.cpp call as hung rather than genuinely
  /// still working. whisper.cpp typically transcribes several times
  /// faster than real-time on modest phone hardware even for larger
  /// models, so this is a deliberately generous, disclosed heuristic -
  /// not measured against real-device throughput data, the same standing
  /// limitation as every other AI-adjacent numeric choice in this project
  /// (see ADR-011's chunk-size estimate) - chosen to make a genuine hang
  /// eventually recoverable without risking cutting off a legitimately
  /// slow-but-progressing transcription on real hardware.
  static const int whisperTranscriptionTimeoutMultiplier = 15;
}
