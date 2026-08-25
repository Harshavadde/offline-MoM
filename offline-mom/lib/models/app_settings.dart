import 'package:flutter/material.dart';

import '../core/theme/accent_colors.dart';

/// User-configurable app preferences, persisted in Hive (a lightweight
/// key-value store is a better fit than a relational table for a single
/// settings row with no query/filter needs).
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.isAppLockEnabled = false,
    this.accentColorValue = AccentColors.defaultAccentValue,
    this.whisperModelName = 'small',
    this.recordingQualityHigh = false,
    this.transcriptionLanguage = 'auto',
    this.displayName = '',
    this.hasCompletedOnboarding = false,
    this.allowBackgroundDownloads = false,
    this.translateToEnglish = false,
    this.activeLlmModelId,
    this.activeEmbeddingModelId,
    this.activeOcrModelId,
    this.professionProfile,
    this.hasSeenResumeModelUpgradePrompt = false,
  });

  final ThemeMode themeMode;

  /// Whether opening or resuming the app requires the device's own PIN/
  /// pattern/password/biometric - not an app-specific account or password.
  /// Off by default so a fresh install (or a grader's device) isn't gated
  /// by a lock the user never set up.
  final bool isAppLockEnabled;

  /// ARGB int for the Material 3 seed color (stored as an int since Hive's
  /// type adapters don't cover [Color] directly).
  final int accentColorValue;

  /// Which whisper.cpp model to transcribe with - `WhisperModel.name`
  /// ('tiny'/'base'/'small'/...). Kept as a plain string here so this model
  /// layer never needs to import the whisper package.
  final String whisperModelName;

  /// Off (false) records 16kHz mono - smaller files, and already what
  /// transcription re-encodes down to anyway. On (true) records 44.1kHz
  /// stereo for better standalone playback quality, at a larger file size.
  final bool recordingQualityHigh;

  /// Whisper language hint ('auto' or an ISO-639-1 code like 'en'). 'auto'
  /// lets whisper.cpp detect the spoken language itself.
  final String transcriptionLanguage;

  /// A local, purely cosmetic display name for the Home greeting - not an
  /// account or profile of any kind (the app has no login/accounts by
  /// design). Empty by default; nothing else in the app depends on it.
  final String displayName;

  /// Whether the user has been through the first-run flow (name entry +
  /// required AI model download) at least once. False on a fresh install -
  /// `SplashScreen` routes to onboarding instead of Home until this is true.
  final bool hasCompletedOnboarding;

  /// Whether the user has opted in to letting AI model downloads keep
  /// running when the app is backgrounded. Off by default: Android can
  /// only do this via a foreground service, which requires showing a
  /// persistent notification while active - a real, visible trade-off the
  /// user should choose explicitly, not something turned on silently.
  final bool allowBackgroundDownloads;

  /// When true, the speech-to-text engine translates recognized speech
  /// directly to English rather than transcribing it in its original
  /// language - see [WhisperSpeechToTextEngine]. Off by default: this is a
  /// real trade-off (the original-language transcript is lost), not
  /// something to force on everyone silently.
  final bool translateToEnglish;

  /// The active `AiModelSpec.id` for [ModelKind.llm]/[ModelKind.embedding]
  /// (AI Model Manager, Phase 6A) - `null` means "use `ModelCatalog
  /// .defaultFor(kind)`", mirroring [whisperModelName]'s existing
  /// default-value convention but nullable rather than hardcoded, since
  /// the default itself now lives in [ModelCatalog], not here. Kept as
  /// plain strings (not `AiModelSpec`) for the same reason
  /// [whisperModelName] is a string, not a `WhisperModel` - this model
  /// layer stays free of any AI-package dependency.
  final String? activeLlmModelId;
  final String? activeEmbeddingModelId;

  /// The active `AiModelSpec.id` for `ModelKind.ocr` (P0-7) - `null` means
  /// no OCR language has been downloaded/activated yet. Same nullable
  /// "defer to the catalog" convention as [activeLlmModelId]/
  /// [activeEmbeddingModelId].
  final String? activeOcrModelId;

  /// `ProfessionProfile.name`, or `null` if the user has never gone
  /// through the Profession Setup screen (AI Model Manager, Phase 6A) -
  /// used only to pre-select a profession the next time that screen opens
  /// and to label the "Recommended for you" banner; never required to use
  /// the app.
  final String? professionProfile;

  /// Whether the one-time "get better resume results" model-upgrade prompt
  /// (docs/v3/01-prd.md §13, FR3-15, Milestone 4) has already been shown -
  /// `false` on a fresh install, mirroring [hasCompletedOnboarding]'s
  /// exact "shown at most once" convention. Set the first time the prompt
  /// is dismissed *or* acted on, regardless of outcome - declining must
  /// never re-prompt on a later entry into the Resume feature (FR3-16).
  final bool hasSeenResumeModelUpgradePrompt;

  Color get accentColor => Color(accentColorValue);

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? isAppLockEnabled,
    int? accentColorValue,
    String? whisperModelName,
    bool? recordingQualityHigh,
    String? transcriptionLanguage,
    String? displayName,
    bool? hasCompletedOnboarding,
    bool? allowBackgroundDownloads,
    bool? translateToEnglish,
    String? activeLlmModelId,
    String? activeEmbeddingModelId,
    String? activeOcrModelId,
    String? professionProfile,
    bool? hasSeenResumeModelUpgradePrompt,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      isAppLockEnabled: isAppLockEnabled ?? this.isAppLockEnabled,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      whisperModelName: whisperModelName ?? this.whisperModelName,
      recordingQualityHigh: recordingQualityHigh ?? this.recordingQualityHigh,
      transcriptionLanguage: transcriptionLanguage ?? this.transcriptionLanguage,
      displayName: displayName ?? this.displayName,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      allowBackgroundDownloads:
          allowBackgroundDownloads ?? this.allowBackgroundDownloads,
      translateToEnglish: translateToEnglish ?? this.translateToEnglish,
      activeLlmModelId: activeLlmModelId ?? this.activeLlmModelId,
      activeEmbeddingModelId: activeEmbeddingModelId ?? this.activeEmbeddingModelId,
      activeOcrModelId: activeOcrModelId ?? this.activeOcrModelId,
      professionProfile: professionProfile ?? this.professionProfile,
      hasSeenResumeModelUpgradePrompt:
          hasSeenResumeModelUpgradePrompt ?? this.hasSeenResumeModelUpgradePrompt,
    );
  }

  Map<String, Object?> toMap() => {
        'theme_mode': themeMode.name,
        'is_app_lock_enabled': isAppLockEnabled,
        'accent_color_value': accentColorValue,
        'whisper_model_name': whisperModelName,
        'recording_quality_high': recordingQualityHigh,
        'transcription_language': transcriptionLanguage,
        'display_name': displayName,
        'has_completed_onboarding': hasCompletedOnboarding,
        'allow_background_downloads': allowBackgroundDownloads,
        'translate_to_english': translateToEnglish,
        'active_llm_model_id': activeLlmModelId,
        'active_embedding_model_id': activeEmbeddingModelId,
        'active_ocr_model_id': activeOcrModelId,
        'profession_profile': professionProfile,
        'has_seen_resume_model_upgrade_prompt': hasSeenResumeModelUpgradePrompt,
      };

  factory AppSettings.fromMap(Map<Object?, Object?> map) {
    final rawThemeMode = map['theme_mode'] as String?;
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == rawThemeMode,
        orElse: () => ThemeMode.system,
      ),
      isAppLockEnabled: map['is_app_lock_enabled'] as bool? ?? false,
      accentColorValue: map['accent_color_value'] as int? ??
          AccentColors.defaultAccentValue,
      whisperModelName: map['whisper_model_name'] as String? ?? 'small',
      recordingQualityHigh: map['recording_quality_high'] as bool? ?? false,
      transcriptionLanguage: map['transcription_language'] as String? ?? 'auto',
      displayName: map['display_name'] as String? ?? '',
      hasCompletedOnboarding: map['has_completed_onboarding'] as bool? ?? false,
      allowBackgroundDownloads: map['allow_background_downloads'] as bool? ?? false,
      translateToEnglish: map['translate_to_english'] as bool? ?? false,
      activeLlmModelId: map['active_llm_model_id'] as String?,
      activeEmbeddingModelId: map['active_embedding_model_id'] as String?,
      activeOcrModelId: map['active_ocr_model_id'] as String?,
      professionProfile: map['profession_profile'] as String?,
      hasSeenResumeModelUpgradePrompt:
          map['has_seen_resume_model_upgrade_prompt'] as bool? ?? false,
    );
  }
}
