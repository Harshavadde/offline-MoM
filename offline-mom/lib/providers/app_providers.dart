import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import '../database/app_database.dart';
import '../models/ai_model_spec.dart' show RecommendedDeviceTier;
import '../models/app_settings.dart';
import '../repositories/action_item_repository.dart';
import '../repositories/content_search_repository.dart';
import '../repositories/decision_repository.dart';
import '../repositories/meeting_repository.dart';
import '../repositories/note_repository.dart';
import '../repositories/recording_mark_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/summary_repository.dart';
import '../repositories/toolkit_file_repository.dart';
import '../repositories/toolkit_folder_repository.dart';
import '../repositories/transcript_repository.dart';
import '../features/ai_summary/generate_meeting_summary_use_case.dart';
import '../features/ask/ask_about_meetings_use_case.dart';
import '../features/meetings/delete_meeting_use_case.dart';
import '../features/meetings/meeting_indexer.dart';
import '../features/meetings/process_new_meeting_use_case.dart';
import '../features/meetings/retry_meeting_processing_use_case.dart';
import '../features/search/search_workspace_use_case.dart';
import '../features/transcription/transcribe_meeting_use_case.dart';
import '../repositories/installed_model_repository.dart';
import '../services/ai/chunked_summarization_service.dart';
import '../services/ai/llamadart_llm_engine.dart';
import '../services/ai/llm_engine.dart';
import '../services/ai/model_catalog.dart';
import '../services/ai/model_download_service.dart';
import '../services/ai/model_lifecycle_manager.dart';
import '../services/ai/speech_to_text_engine.dart';
import '../services/ai/whisper_speech_to_text_engine.dart';
import '../services/audio/audio_import_service.dart';
import '../services/audio/audio_player_service.dart';
import '../services/audio/audioplayers_audio_player_service.dart';
import '../services/audio/file_picker_audio_import_service.dart';
import '../services/audio/record_package_recorder_service.dart';
import '../services/audio/recorder_service.dart';
import '../services/export/pdf_export_service.dart';
import '../services/export/pw_pdf_export_service.dart';
import '../services/security/app_lock_service.dart';
import '../services/security/local_auth_app_lock_service.dart';
import '../services/toolkit/pdf_compression_service.dart';
import '../services/toolkit/pdf_merge_service.dart';
import '../services/toolkit/pdf_organize_service.dart';
import '../services/toolkit/pdf_overlay_service.dart';
import '../services/toolkit/pdf_page_composer.dart';
import '../services/toolkit/pdf_page_rendering_service.dart';
import '../services/toolkit/pdf_redaction_service.dart';
import '../services/ocr/ocr_text_extraction_service.dart';
import '../services/ocr/searchable_pdf_builder_service.dart';
import '../services/pdf_security/pdf_security_service.dart';
import '../services/toolkit/pdf_searchable_text_preservation.dart';
import '../services/toolkit/pdf_text_search_service.dart';
import '../services/toolkit/pdf_split_service.dart';
import '../services/toolkit/scanner_pdf_service.dart';
import '../services/toolkit/toolkit_file_picker_service.dart';
import '../services/toolkit/toolkit_image_picker_service.dart';

// V2 scaffolding (docs/v2/implementation/02-backlog.md, Task 32 of the
// scaffolding pass this section belongs to) - see the block below, kept
// separate from the V1 registrations above for a clean diff.
import '../core/utils/career_paths.dart';
import '../features/career/analysis/analyze_resume_against_jd_use_case.dart';
import '../features/career/analysis/generate_resume_suggestions_use_case.dart';
import '../features/career/analysis/prioritize_resume_content_use_case.dart';
import '../features/career/jd/create_resume_from_jd_use_case.dart';
import '../features/career/jd/import_jd_use_case.dart';
import '../features/career/resume/accept_suggested_edit_use_case.dart';
import '../features/career/resume/create_beginner_resume_use_case.dart';
import '../features/career/resume/create_resume_from_profile_use_case.dart';
import '../features/career/resume/delete_library_block_use_case.dart';
import '../features/career/resume/delete_resume_use_case.dart';
import '../features/career/resume/generate_bullet_rewrite_use_case.dart';
import '../features/career/resume/generate_import_second_pass_use_case.dart';
import '../features/career/resume/import_resume_use_case.dart';
import '../features/career/resume/reject_suggested_edit_use_case.dart';
import '../features/career/resume/save_resume_version_use_case.dart';
import '../features/chat/delete_chat_session_use_case.dart';
import '../repositories/certification_block_repository.dart';
import '../repositories/custom_section_block_repository.dart';
import '../repositories/education_block_repository.dart';
import '../repositories/experience_block_repository.dart';
import '../repositories/project_block_repository.dart';
import '../repositories/resume_block_repository.dart';
import '../repositories/resume_repository.dart';
import '../repositories/resume_version_repository.dart';
import '../repositories/skill_entry_repository.dart';
import '../repositories/suggested_edit_repository.dart';
import '../services/career/jd_import_file_picker_service.dart';
import '../services/career/jd_parser.dart';
import '../services/career/resume_jd_analyzer.dart';
import '../services/career/resume_jd_semantic_matcher.dart';
import '../services/device/device_capability_service.dart';
import '../services/resume/resume_compiler_service.dart';
import '../services/resume/resume_import_file_picker_service.dart';
import '../services/resume/resume_import_parser.dart';
import '../services/resume/resume_import_second_pass_prompt_builder.dart';
import '../services/resume/resume_pdf_export_service.dart';
import '../services/resume/resume_suggestion_prompt_builder.dart';
import '../features/chat/general_chat_use_case.dart';
import '../features/chat/workspace_chat_use_case.dart';
import '../features/documents/delete_document_use_case.dart';
import '../features/documents/document_import_use_case.dart';
import '../features/documents/document_indexer.dart';
import '../features/documents/extract_document_text_use_case.dart';
import '../features/documents/process_new_document_use_case.dart';
import '../features/documents/retry_document_processing_use_case.dart';
import '../features/documents/summarize_document_use_case.dart';
import '../models/document.dart';
import '../repositories/chat_message_repository.dart';
import '../repositories/chat_session_repository.dart';
import '../repositories/document_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/knowledge_chunk_repository.dart';
import '../services/ai/default_llm_request_queue.dart';
import '../services/ai/embedding_engine.dart';
import '../services/ai/llamadart_embedding_engine.dart';
import '../services/ai/llm_request_queue.dart';
import '../services/documents/document_import_service.dart';
import '../services/documents/document_text_extraction_service.dart';
import '../services/retrieval/chunking_service.dart';
import '../services/retrieval/hybrid_retrieval_pipeline.dart';
import '../services/retrieval/indexing_service.dart';
import '../services/retrieval/keyword_search_service.dart';
import '../services/retrieval/retrieval_engine.dart';
import '../services/retrieval/vector_store.dart';
import '../services/documents/parsers/docx_parser.dart';
import '../services/documents/parsers/pdf_parser.dart';
import '../services/documents/parsers/text_markdown_parser.dart';

/// Composition root: wires concrete repository implementations behind their
/// abstract interfaces. Every provider below exposes the *interface* type
/// (e.g. `MeetingRepository`, not `SqfliteMeetingRepository`) so ViewModels
/// depend only on the contract, never the storage engine.
///
/// [appDatabaseProvider] and [settingsBoxProvider] are placeholders that get
/// overridden in `main.dart` once the async database/Hive box are opened —
/// everything downstream can then be built synchronously.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden in main()');
});

final settingsBoxProvider = Provider<Box>((ref) {
  throw UnimplementedError('settingsBoxProvider must be overridden in main()');
});

final meetingRepositoryProvider = Provider<MeetingRepository>((ref) {
  return SqfliteMeetingRepository(ref.watch(appDatabaseProvider).db);
});

final recordingMarkRepositoryProvider = Provider<RecordingMarkRepository>((ref) {
  return SqfliteRecordingMarkRepository(ref.watch(appDatabaseProvider).db);
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return SqfliteNoteRepository(ref.watch(appDatabaseProvider).db);
});

/// Student Toolkit (V2 Phase 5A) Recent Files.
final toolkitFileRepositoryProvider = Provider<ToolkitFileRepository>((ref) {
  return SqfliteToolkitFileRepository(ref.watch(appDatabaseProvider).db);
});

/// Student Toolkit folders (P0-9, File-Manager Parity) - a separate table
/// from Documents' own `folderRepositoryProvider`, see
/// `ToolkitFoldersTable`'s doc comment (database/tables.dart).
final toolkitFolderRepositoryProvider = Provider<FolderRepository>((ref) {
  return SqfliteToolkitFolderRepository(ref.watch(appDatabaseProvider).db);
});

/// AI Model Manager (V2 Phase 6A) installed-model records.
final installedModelRepositoryProvider = Provider<InstalledModelRepository>((ref) {
  return SqfliteInstalledModelRepository(ref.watch(appDatabaseProvider).db);
});

/// AI Model Manager (V2 Phase 6A) - the resumable download primitive used
/// for Whisper (and, once real, OCR/Vision/Translation) model downloads.
/// Not used for LLM/embedding downloads - see [ModelDownloadService]'s doc
/// comment for why those two kinds go through `llamadart`'s own
/// downloader instead.
final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return HttpModelDownloadService();
});

/// Student Toolkit (V2 Phase 5A) gallery pick / camera capture; extended
/// (V2 Phase 5B) with multi-select gallery import for Scanner.
final toolkitImagePickerServiceProvider = Provider<ToolkitImagePickerService>((ref) {
  return ImagePickerToolkitImagePickerService();
});

/// Scanner (V2 Phase 5B) - builds one PDF from an ordered list of page
/// images.
final scannerPdfServiceProvider = Provider<ScannerPdfService>((ref) {
  return PwScannerPdfService();
});

/// Shared PDF-page rasterization (V2 Phase 5B) - the foundation every PDF
/// Tool (Compress/Merge/Split/Organize) reads existing PDF pages through.
final pdfPageRenderingServiceProvider = Provider<PdfPageRenderingService>((ref) {
  return PdfiumPdfPageRenderingService();
});

/// Broader-Unicode-coverage fallback font for a rasterize-and-rebuild PDF
/// Tool's invisible search-text layer - see `PdfMergeService.merge`'s own
/// doc comment on `overlayTextFontFallback` for why this exists. Loaded
/// once (Riverpod caches a `FutureProvider`'s result) from this app's
/// already-bundled `assets/fonts/Inter-Regular.ttf` (the same font
/// `ResumeTemplateRenderer` already loads the same way) - no new asset.
/// `FutureProvider` on purpose, not a plain `Provider`: loading a real
/// asset is async (`rootBundle.load`), and every caller already awaits
/// this via `.future` and tolerates it failing (falls back to no fallback
/// font, not a crash) - see `pdfMergeControllerProvider`.
final overlayTextFallbackFontProvider = FutureProvider<pw.Font>((ref) async {
  final data = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
  return pw.Font.ttf(data);
});

/// Best-effort load of [overlayTextFallbackFontProvider], shared by every
/// rasterize-and-rebuild PDF Tool controller (Compress/Merge/Split/
/// Organize/Redact/Edit) instead of reimplementing the same try/catch six
/// times. A font-asset load failure (should never happen for a bundled
/// asset) degrades to no fallback font for this run - never blocks the
/// actual PDF operation.
Future<List<pw.Font>> loadOverlayTextFontFallback(Ref ref) async {
  try {
    final font = await ref.read(overlayTextFallbackFontProvider.future);
    return [font];
  } catch (_) {
    return const [];
  }
}

final pdfCompressionServiceProvider = Provider<PdfCompressionService>((ref) {
  return PdfCompressionService();
});

final pdfMergeServiceProvider = Provider<PdfMergeService>((ref) {
  return PdfMergeService();
});

final pdfSplitServiceProvider = Provider<PdfSplitService>((ref) {
  return PdfSplitService();
});

final pdfOrganizeServiceProvider = Provider<PdfOrganizeService>((ref) {
  return PdfOrganizeService();
});

/// Productivity Toolkit productization pass (P0-2/ADR-040) - the shared
/// overlay-and-rebuild step Add Text/Signatures/Annotations/Watermark
/// (P0-3) all reuse.
final pdfOverlayServiceProvider = Provider<PdfOverlayService>((ref) {
  return PdfOverlayService();
});

/// Productivity Toolkit productization pass (P0-4/ADR-042) - the
/// rasterize-then-permanently-overwrite-pixels-then-rebuild step behind
/// Redact PDF. Deliberately a separate provider/service from
/// [pdfOverlayServiceProvider], not a variant of it - see ADR-040/ADR-042
/// for why redaction must not reuse the overlay mechanism.
final pdfRedactionServiceProvider = Provider<PdfRedactionService>((ref) {
  return PdfRedactionService();
});

/// Page Management (P0-5/ADR-043) - the shared "rasterized pages -> real
/// PDF" builder behind Rotate/Delete/Extract/Insert/Duplicate/Replace/
/// Reorder. `PdfOrganizeService` also uses this internally (not a second,
/// independent implementation) for its own narrower single-source API.
final pdfPageComposerServiceProvider = Provider<PdfPageComposerService>((ref) {
  return PdfPageComposerService();
});

/// PDF Search (P0-6) - page-indexed text extraction for born-digital PDFs,
/// backed by `read_pdf_text`'s `getPDFtextPaginated` (already a pinned
/// dependency, used elsewhere by Documents' `PdfParser` for its own
/// whole-document extraction). Not OCR - a scanned/image-only PDF simply
/// yields empty pages, surfaced in-product as "No searchable text found."
final pdfTextSearchServiceProvider = Provider<PdfTextSearchService>((ref) {
  return ReadPdfTextSearchService();
});

/// Release blocker B3 (R-49) - restores approximate searchable text on
/// pages rebuilt by any rasterize-and-rebuild PDF Tool, reusing
/// [pdfTextSearchServiceProvider] (no OCR call, no new dependency) - see
/// `pdf_searchable_text_preservation.dart`'s own doc comment.
final pdfSearchableTextPreserverProvider = Provider<PdfSearchableTextPreserver>((ref) {
  return PdfSearchableTextPreserver(textSearchService: ref.watch(pdfTextSearchServiceProvider));
});

/// OCR / Searchable PDF (P0-7) - real offline OCR via `flutter_tesseract_ocr`
/// (native `TessBaseAPI`, wrapped so per-word bounding boxes come from real
/// hOCR output, not a flat-string approximation - see
/// `ocr_text_extraction_service.dart`).
final ocrTextExtractionServiceProvider = Provider<OcrTextExtractionService>((ref) {
  return TesseractOcrTextExtractionService();
});

/// The shared "page images -> searchable PDF" pipeline every P0-7 entry
/// point (Scan, Images to PDF, an existing PDF's Run OCR) builds its output
/// through.
final searchablePdfBuilderServiceProvider = Provider<SearchablePdfBuilderService>((ref) {
  return SearchablePdfBuilderService(ocrService: ref.watch(ocrTextExtractionServiceProvider));
});

/// PDF Security (P0-8) - real, on-device password protection/unlock via
/// `pdf_cos`/`pdf_document`'s genuine PDF Standard Security Handler. See
/// ADR-046, docs/v2/implementation/03-decisions.md.
final pdfSecurityServiceProvider = Provider<PdfSecurityService>((ref) {
  return const PdfSecurityService();
});

/// PDF Tools (V2 Phase 5B) file-system PDF/image picking.
final toolkitFilePickerServiceProvider = Provider<ToolkitFilePickerService>((ref) {
  return FilePickerToolkitFilePickerService();
});

final transcriptRepositoryProvider = Provider<TranscriptRepository>((ref) {
  return SqfliteTranscriptRepository(ref.watch(appDatabaseProvider).db);
});

final summaryRepositoryProvider = Provider<SummaryRepository>((ref) {
  return SqfliteSummaryRepository(ref.watch(appDatabaseProvider).db);
});

final actionItemRepositoryProvider = Provider<ActionItemRepository>((ref) {
  return SqfliteActionItemRepository(ref.watch(appDatabaseProvider).db);
});

final decisionRepositoryProvider = Provider<DecisionRepository>((ref) {
  return SqfliteDecisionRepository(ref.watch(appDatabaseProvider).db);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return HiveSettingsRepository(ref.watch(settingsBoxProvider));
});

final contentSearchRepositoryProvider = Provider<ContentSearchRepository>((ref) {
  return SqfliteContentSearchRepository(ref.watch(appDatabaseProvider).db);
});

final recorderServiceProvider = Provider<RecorderService>((ref) {
  final highQuality = ref.watch(settingsControllerProvider).recordingQualityHigh;
  final service = RecordPackageRecorderService(highQuality: highQuality);
  ref.onDispose(service.dispose);
  return service;
});

final audioImportServiceProvider = Provider<AudioImportService>((ref) {
  return FilePickerAudioImportService();
});

/// Auto-disposes once nothing watches it (i.e. when the Transcript tab
/// showing the playback bar is no longer on screen), so playback actually
/// stops instead of continuing in the background after navigating away.
final audioPlayerServiceProvider = Provider.autoDispose<AudioPlayerService>((ref) {
  final service = AudioplayersAudioPlayerService();
  ref.onDispose(service.dispose);
  return service;
});

/// Single shared instance for the app's whole lifetime (same "one instance,
/// not one per provider read" reasoning as [llmRequestQueueProvider]) -
/// Phase 3A's centralized model-lifecycle service
/// (services/ai/model_lifecycle_manager.dart, ADR-029,
/// docs/v2/implementation/03-decisions.md). Every model-backed engine
/// ([speechToTextEngineProvider]/[llmEngineProvider]/
/// [embeddingEngineProvider]) attaches itself to this one manager, so
/// idle-unload timers/reference counts are tracked in one place across the
/// whole app rather than duplicated per engine.
final modelLifecycleManagerProvider = Provider<ModelLifecycleManager>((ref) {
  final manager = ModelLifecycleManager();
  ref.onDispose(manager.dispose);
  return manager;
});

final speechToTextEngineProvider = Provider<SpeechToTextEngine>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  final model = WhisperModel.values.firstWhere(
    (m) => m.name == settings.whisperModelName,
    orElse: () => WhisperModel.small,
  );
  return WhisperSpeechToTextEngine(
    model: model,
    language: settings.transcriptionLanguage,
    translateToEnglish: settings.translateToEnglish,
    lifecycleManager: ref.watch(modelLifecycleManagerProvider),
  );
});

final transcribeMeetingUseCaseProvider = Provider<TranscribeMeetingUseCase>((ref) {
  return TranscribeMeetingUseCase(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    transcriptRepository: ref.watch(transcriptRepositoryProvider),
    speechToTextEngine: ref.watch(speechToTextEngineProvider),
  );
});

/// Watches `activeLlmModelId` (AI Model Manager, Phase 6A) the same way
/// [speechToTextEngineProvider] already watches `whisperModelName` -
/// changing the active model rebuilds a fresh engine pointed at the new
/// catalog entry's [AiModelSpec.downloadSource]. `null` (no explicit
/// choice made yet) resolves to [ModelCatalog.defaultFor], matching
/// [AppSettings.activeLlmModelId]'s documented default-value convention.
final llmEngineProvider = Provider<LlmEngine>((ref) {
  final activeId = ref.watch(settingsControllerProvider).activeLlmModelId;
  final spec = (activeId != null ? ModelCatalog.byId(activeId) : null) ??
      ModelCatalog.defaultFor(ModelKind.llm);
  return LlamaDartLlmEngine(
    lifecycleManager: ref.watch(modelLifecycleManagerProvider),
    modelSourceOverride: spec?.downloadSource,
  );
});

/// M2.4 (docs/v2/07-feature-roadmap.md Phase 2): chunked/hierarchical
/// map-reduce summarization, shared by both
/// [generateMeetingSummaryUseCaseProvider] and
/// [summarizeDocumentUseCaseProvider] - one implementation, not two,
/// mirroring how both use cases already share [llmEngineProvider]/
/// [llmRequestQueueProvider] directly before this provider existed.
final chunkedSummarizationServiceProvider =
    Provider<ChunkedSummarizationService>((ref) {
  return ChunkedSummarizationService(
    llmEngine: ref.watch(llmEngineProvider),
    llmRequestQueue: ref.watch(llmRequestQueueProvider),
  );
});

final generateMeetingSummaryUseCaseProvider =
    Provider<GenerateMeetingSummaryUseCase>((ref) {
  return GenerateMeetingSummaryUseCase(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    transcriptRepository: ref.watch(transcriptRepositoryProvider),
    summaryRepository: ref.watch(summaryRepositoryProvider),
    actionItemRepository: ref.watch(actionItemRepositoryProvider),
    decisionRepository: ref.watch(decisionRepositoryProvider),
    chunkedSummarizationService: ref.watch(chunkedSummarizationServiceProvider),
  );
});

final meetingIndexerProvider = Provider<MeetingIndexer>((ref) {
  return MeetingIndexer(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    transcriptRepository: ref.watch(transcriptRepositoryProvider),
    summaryRepository: ref.watch(summaryRepositoryProvider),
    indexingService: ref.watch(indexingServiceProvider),
  );
});

final processNewMeetingUseCaseProvider = Provider<ProcessNewMeetingUseCase>((ref) {
  return ProcessNewMeetingUseCase(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    transcribeMeetingUseCase: ref.watch(transcribeMeetingUseCaseProvider),
    generateMeetingSummaryUseCase: ref.watch(generateMeetingSummaryUseCaseProvider),
    meetingIndexer: ref.watch(meetingIndexerProvider),
  );
});

final deleteMeetingUseCaseProvider = Provider<DeleteMeetingUseCase>((ref) {
  return DeleteMeetingUseCase(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    vectorStore: ref.watch(vectorStoreProvider),
  );
});

final retryMeetingProcessingUseCaseProvider =
    Provider<RetryMeetingProcessingUseCase>((ref) {
  return RetryMeetingProcessingUseCase(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    transcriptRepository: ref.watch(transcriptRepositoryProvider),
    summaryRepository: ref.watch(summaryRepositoryProvider),
    transcribeMeetingUseCase: ref.watch(transcribeMeetingUseCaseProvider),
    generateMeetingSummaryUseCase:
        ref.watch(generateMeetingSummaryUseCaseProvider),
    meetingIndexer: ref.watch(meetingIndexerProvider),
  );
});

final pdfExportServiceProvider = Provider<PdfExportService>((ref) {
  return PwPdfExportService();
});

final searchWorkspaceUseCaseProvider = Provider<SearchWorkspaceUseCase>((ref) {
  return SearchWorkspaceUseCase(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    documentRepository: ref.watch(documentRepositoryProvider),
    contentSearchRepository: ref.watch(contentSearchRepositoryProvider),
    decisionRepository: ref.watch(decisionRepositoryProvider),
  );
});

final askAboutMeetingsUseCaseProvider = Provider<AskAboutMeetingsUseCase>((ref) {
  return AskAboutMeetingsUseCase(
    meetingRepository: ref.watch(meetingRepositoryProvider),
    summaryRepository: ref.watch(summaryRepositoryProvider),
    llmEngine: ref.watch(llmEngineProvider),
    llmRequestQueue: ref.watch(llmRequestQueueProvider),
  );
});

/// ViewModel for app-wide settings (currently: theme mode). Lives at the app
/// level, not inside `features/settings`, because the theme choice is
/// consumed by the root `MaterialApp`, not just the Settings screen.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.watch(settingsRepositoryProvider).getSettings();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final updated = state.copyWith(themeMode: mode);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    final updated = state.copyWith(isAppLockEnabled: enabled);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setAccentColor(Color color) async {
    final updated = state.copyWith(accentColorValue: color.toARGB32());
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setWhisperModelName(String modelName) async {
    final updated = state.copyWith(whisperModelName: modelName);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setRecordingQualityHigh(bool high) async {
    final updated = state.copyWith(recordingQualityHigh: high);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setTranscriptionLanguage(String languageCode) async {
    final updated = state.copyWith(transcriptionLanguage: languageCode);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setDisplayName(String name) async {
    final updated = state.copyWith(displayName: name.trim());
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> completeOnboarding() async {
    final updated = state.copyWith(hasCompletedOnboarding: true);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setAllowBackgroundDownloads(bool allow) async {
    final updated = state.copyWith(allowBackgroundDownloads: allow);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setTranslateToEnglish(bool translate) async {
    final updated = state.copyWith(translateToEnglish: translate);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  /// AI Model Manager (V2 Phase 6A) - see [AppSettings.activeLlmModelId].
  Future<void> setActiveLlmModelId(String modelId) async {
    final updated = state.copyWith(activeLlmModelId: modelId);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setActiveEmbeddingModelId(String modelId) async {
    final updated = state.copyWith(activeEmbeddingModelId: modelId);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  /// AI Model Manager OCR support (P0-7) - see [AppSettings.activeOcrModelId].
  Future<void> setActiveOcrModelId(String modelId) async {
    final updated = state.copyWith(activeOcrModelId: modelId);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  Future<void> setProfessionProfile(String profession) async {
    final updated = state.copyWith(professionProfile: profession);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }

  /// docs/v3/01-prd.md §13/FR3-15, Milestone 4 - marks the one-time
  /// model-upgrade prompt seen regardless of outcome (downloaded, declined,
  /// or dismissed), so it never shows again (FR3-16).
  Future<void> markResumeModelUpgradePromptSeen() async {
    final updated = state.copyWith(hasSeenResumeModelUpgradePrompt: true);
    state = updated;
    await ref.read(settingsRepositoryProvider).save(updated);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return LocalAuthAppLockService();
});

/// Whether the app is currently showing the lock screen. Deliberately
/// reads settings with `ref.read` (not `watch`) so an unrelated settings
/// change (e.g. toggling theme) never re-triggers this provider's `build`
/// and silently re-locks an already-unlocked session.
class AppLockController extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(settingsRepositoryProvider).getSettings().isAppLockEnabled;
  }

  Future<bool> tryUnlock() async {
    final success = await ref
        .read(appLockServiceProvider)
        .authenticate('Unlock OfflineMoMAI');
    if (success) state = false;
    return success;
  }

  /// Called when the app is backgrounded; locks again only if the setting
  /// is currently on.
  void lockIfEnabled() {
    if (ref.read(settingsRepositoryProvider).getSettings().isAppLockEnabled) {
      state = true;
    }
  }

  void forceUnlock() => state = false;
}

final appLockControllerProvider =
    NotifierProvider<AppLockController, bool>(AppLockController.new);

// ============================================================================
// V2 providers (docs/v2/implementation/02-backlog.md,
// docs/v2/implementation/11-gap-analysis.md sections 6-7). Documents (Phase
// 1A), the retrieval/indexing infrastructure (Phase 1B/1C),
// `ChatSessionRepository`/`ChatMessageRepository`/`WorkspaceChatUseCase`
// (Phase 2A), and `GeneralChatUseCase` (`ChatScope.general`, M2.1) below are
// all real, wired implementations.
// ============================================================================

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return SqfliteDocumentRepository(ref.watch(appDatabaseProvider).db);
});

/// Document folders (V2.2 Production Hardening, Priority 2).
final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  return SqfliteFolderRepository(ref.watch(appDatabaseProvider).db);
});

final knowledgeChunkRepositoryProvider =
    Provider<KnowledgeChunkRepository>((ref) {
  return SqfliteKnowledgeChunkRepository(ref.watch(appDatabaseProvider).db);
});

final chatSessionRepositoryProvider = Provider<ChatSessionRepository>((ref) {
  return SqfliteChatSessionRepository(ref.watch(appDatabaseProvider).db);
});

final chatMessageRepositoryProvider = Provider<ChatMessageRepository>((ref) {
  return SqfliteChatMessageRepository(ref.watch(appDatabaseProvider).db);
});

/// Single shared instance for the app's whole lifetime, matching the
/// shared [LlmEngine] instance it coordinates access to (ADR-008,
/// docs/v2/implementation/03-decisions.md) - every AI generation call in
/// the app must go through this one queue, not a fresh one per feature.
final llmRequestQueueProvider = Provider<LlmRequestQueue>((ref) {
  return DefaultLlmRequestQueue();
});

/// Single shared instance for the app's whole lifetime, same reasoning as
/// [llmRequestQueueProvider] - one embedding-model-backed `LlamaEngine`
/// instance, not a fresh one per indexing call. See
/// docs/v2/implementation/spikes/m1-0-embedding-spike.md (ADR-003: option
/// 1, the same `llamadart`/`llama.cpp` path the chat LLM already uses).
/// See [llmEngineProvider]'s identical doc comment - the embedding kind's
/// counterpart.
final embeddingEngineProvider = Provider<EmbeddingEngine>((ref) {
  final activeId = ref.watch(settingsControllerProvider).activeEmbeddingModelId;
  final spec = (activeId != null ? ModelCatalog.byId(activeId) : null) ??
      ModelCatalog.defaultFor(ModelKind.embedding);
  return LlamaDartEmbeddingEngine(
    lifecycleManager: ref.watch(modelLifecycleManagerProvider),
    modelSourceOverride: spec?.downloadSource,
  );
});

final vectorStoreProvider = Provider<VectorStore>((ref) {
  return BruteForceVectorStore(
    knowledgeChunkRepository: ref.watch(knowledgeChunkRepositoryProvider),
  );
});

final chunkingServiceProvider = Provider<ChunkingService>((ref) {
  return const DefaultChunkingService();
});

final indexingServiceProvider = Provider<IndexingService>((ref) {
  return DefaultIndexingService(
    chunkingService: ref.watch(chunkingServiceProvider),
    embeddingEngine: ref.watch(embeddingEngineProvider),
    vectorStore: ref.watch(vectorStoreProvider),
    knowledgeChunkRepository: ref.watch(knowledgeChunkRepositoryProvider),
  );
});

final retrievalEngineProvider = Provider<RetrievalEngine>((ref) {
  return DefaultRetrievalEngine(
    embeddingEngine: ref.watch(embeddingEngineProvider),
    vectorStore: ref.watch(vectorStoreProvider),
  );
});

/// Chunk-granularity BM25 keyword search (V2 Phase 6B, Hybrid Retrieval
/// Engine, ADR-037) - the lexical half of [hybridRetrievalPipelineProvider],
/// alongside [vectorStoreProvider]'s existing semantic half.
final keywordSearchServiceProvider = Provider<KeywordSearchService>((ref) {
  return SqfliteKeywordSearchService(ref.watch(appDatabaseProvider).db);
});

/// The Hybrid Retrieval Engine (V2 Phase 6B, ADR-037) - what
/// [workspaceChatUseCaseProvider] now retrieves through instead of
/// [retrievalEngineProvider] directly. Depends on [vectorStoreProvider]
/// (not [retrievalEngineProvider]) specifically to avoid a second,
/// redundant [EmbeddingEngine.embed] call for the same query - see
/// [HybridRetrievalPipeline]'s own doc comment. [retrievalEngineProvider]
/// itself is untouched and still available for any other future caller.
final hybridRetrievalPipelineProvider = Provider<HybridRetrievalPipeline>((ref) {
  return HybridRetrievalPipeline(
    embeddingEngine: ref.watch(embeddingEngineProvider),
    vectorStore: ref.watch(vectorStoreProvider),
    keywordSearchService: ref.watch(keywordSearchServiceProvider),
  );
});

final documentIndexerProvider = Provider<DocumentIndexer>((ref) {
  return DocumentIndexer(
    documentRepository: ref.watch(documentRepositoryProvider),
    indexingService: ref.watch(indexingServiceProvider),
  );
});

/// One parser instance per format, keyed by the [DocumentSourceType] it
/// handles - [ExtractDocumentTextUseCase] looks up the right one for a
/// given document rather than a single provider trying to be all formats
/// at once. `txt` and `markdown` share the same [TextMarkdownParser] class
/// (constructed twice, once per type) since both are plain text.
final documentTextExtractorsProvider =
    Provider<Map<DocumentSourceType, DocumentTextExtractionService>>((ref) {
  return {
    DocumentSourceType.pdf: PdfParser(),
    DocumentSourceType.docx: DocxParser(),
    DocumentSourceType.txt: TextMarkdownParser(DocumentSourceType.txt),
    DocumentSourceType.markdown: TextMarkdownParser(DocumentSourceType.markdown),
  };
});

final documentImportServiceProvider = Provider<DocumentImportService>((ref) {
  return FilePickerDocumentImportService();
});

final documentImportUseCaseProvider = Provider<DocumentImportUseCase>((ref) {
  return DocumentImportUseCase(
    documentRepository: ref.watch(documentRepositoryProvider),
    documentImportService: ref.watch(documentImportServiceProvider),
  );
});

final extractDocumentTextUseCaseProvider =
    Provider<ExtractDocumentTextUseCase>((ref) {
  return ExtractDocumentTextUseCase(
    documentRepository: ref.watch(documentRepositoryProvider),
    extractors: ref.watch(documentTextExtractorsProvider),
  );
});

final summarizeDocumentUseCaseProvider =
    Provider<SummarizeDocumentUseCase>((ref) {
  return SummarizeDocumentUseCase(
    documentRepository: ref.watch(documentRepositoryProvider),
    summaryRepository: ref.watch(summaryRepositoryProvider),
    chunkedSummarizationService: ref.watch(chunkedSummarizationServiceProvider),
  );
});

final processNewDocumentUseCaseProvider =
    Provider<ProcessNewDocumentUseCase>((ref) {
  return ProcessNewDocumentUseCase(
    documentRepository: ref.watch(documentRepositoryProvider),
    extractDocumentTextUseCase: ref.watch(extractDocumentTextUseCaseProvider),
    summarizeDocumentUseCase: ref.watch(summarizeDocumentUseCaseProvider),
    documentIndexer: ref.watch(documentIndexerProvider),
  );
});

final retryDocumentProcessingUseCaseProvider =
    Provider<RetryDocumentProcessingUseCase>((ref) {
  return RetryDocumentProcessingUseCase(
    documentRepository: ref.watch(documentRepositoryProvider),
    summaryRepository: ref.watch(summaryRepositoryProvider),
    extractDocumentTextUseCase: ref.watch(extractDocumentTextUseCaseProvider),
    summarizeDocumentUseCase: ref.watch(summarizeDocumentUseCaseProvider),
    documentIndexer: ref.watch(documentIndexerProvider),
  );
});

final deleteDocumentUseCaseProvider = Provider<DeleteDocumentUseCase>((ref) {
  return DeleteDocumentUseCase(
    documentRepository: ref.watch(documentRepositoryProvider),
    vectorStore: ref.watch(vectorStoreProvider),
  );
});

final workspaceChatUseCaseProvider = Provider<WorkspaceChatUseCase>((ref) {
  return WorkspaceChatUseCase(
    chatSessionRepository: ref.watch(chatSessionRepositoryProvider),
    chatMessageRepository: ref.watch(chatMessageRepositoryProvider),
    hybridRetrievalPipeline: ref.watch(hybridRetrievalPipelineProvider),
    meetingRepository: ref.watch(meetingRepositoryProvider),
    documentRepository: ref.watch(documentRepositoryProvider),
    llmEngine: ref.watch(llmEngineProvider),
    llmRequestQueue: ref.watch(llmRequestQueueProvider),
  );
});

final generalChatUseCaseProvider = Provider<GeneralChatUseCase>((ref) {
  return GeneralChatUseCase(
    chatSessionRepository: ref.watch(chatSessionRepositoryProvider),
    chatMessageRepository: ref.watch(chatMessageRepositoryProvider),
    llmEngine: ref.watch(llmEngineProvider),
    llmRequestQueue: ref.watch(llmRequestQueueProvider),
  );
});

final deleteChatSessionUseCaseProvider =
    Provider<DeleteChatSessionUseCase>((ref) {
  return DeleteChatSessionUseCase(
    chatSessionRepository: ref.watch(chatSessionRepositoryProvider),
  );
});

// ============================================================================
// V3 Milestone 1 - Resume module repositories (Batch 1/2/3). Registered here
// so the Resume feature's own `presentation/providers/*.dart` files (Batch
// 4) and, later, its controllers (Batch 5) can `ref.watch` them the same way
// every provider above does - never opening the database directly.
// ============================================================================

final resumeRepositoryProvider = Provider<ResumeRepository>((ref) {
  return SqfliteResumeRepository(ref.watch(appDatabaseProvider).db);
});

final resumeBlockRepositoryProvider = Provider<ResumeBlockRepository>((ref) {
  return SqfliteResumeBlockRepository(ref.watch(appDatabaseProvider).db);
});

final experienceBlockRepositoryProvider =
    Provider<ExperienceBlockRepository>((ref) {
  return SqfliteExperienceBlockRepository(ref.watch(appDatabaseProvider).db);
});

final educationBlockRepositoryProvider =
    Provider<EducationBlockRepository>((ref) {
  return SqfliteEducationBlockRepository(ref.watch(appDatabaseProvider).db);
});

final projectBlockRepositoryProvider = Provider<ProjectBlockRepository>((ref) {
  return SqfliteProjectBlockRepository(ref.watch(appDatabaseProvider).db);
});

final certificationBlockRepositoryProvider =
    Provider<CertificationBlockRepository>((ref) {
  return SqfliteCertificationBlockRepository(ref.watch(appDatabaseProvider).db);
});

final skillEntryRepositoryProvider = Provider<SkillEntryRepository>((ref) {
  return SqfliteSkillEntryRepository(ref.watch(appDatabaseProvider).db);
});

final customSectionBlockRepositoryProvider =
    Provider<CustomSectionBlockRepository>((ref) {
  return SqfliteCustomSectionBlockRepository(ref.watch(appDatabaseProvider).db);
});

final resumeVersionRepositoryProvider =
    Provider<ResumeVersionRepository>((ref) {
  return SqfliteResumeVersionRepository(ref.watch(appDatabaseProvider).db);
});

// V3 Milestone 0 - Data Model & Device Foundation (docs/v3/01-prd.md §25).
// suggestedEditRepositoryProvider is schema/CRUD-only here - nothing in
// this milestone generates a real suggestion yet; Milestone 3's tailoring
// pipeline is the first real writer. deviceCapabilityServiceProvider is
// used only to *recommend*, never require, a stronger optional AI model
// (docs/v3/01-prd.md §13) - it has no other consumer today.

final suggestedEditRepositoryProvider =
    Provider<SuggestedEditRepository>((ref) {
  return SqfliteSuggestedEditRepository(ref.watch(appDatabaseProvider).db);
});

final deviceCapabilityServiceProvider =
    Provider<DeviceCapabilityService>((ref) {
  return DeviceInfoDeviceCapabilityService();
});

final resumeCompilerServiceProvider = Provider<ResumeCompilerService>((ref) {
  return ResumeCompilerService(
    experienceBlockRepository: ref.watch(experienceBlockRepositoryProvider),
    educationBlockRepository: ref.watch(educationBlockRepositoryProvider),
    projectBlockRepository: ref.watch(projectBlockRepositoryProvider),
    certificationBlockRepository:
        ref.watch(certificationBlockRepositoryProvider),
    skillEntryRepository: ref.watch(skillEntryRepositoryProvider),
    customSectionBlockRepository: ref.watch(customSectionBlockRepositoryProvider),
  );
});

final resumePdfExportServiceProvider =
    Provider<ResumePdfExportService>((ref) {
  return const PwResumePdfExportService();
});

final deleteResumeUseCaseProvider = Provider<DeleteResumeUseCase>((ref) {
  return DeleteResumeUseCase(
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    resumeVersionRepository: ref.watch(resumeVersionRepositoryProvider),
  );
});

final createResumeFromProfileUseCaseProvider = Provider<CreateResumeFromProfileUseCase>((ref) {
  return CreateResumeFromProfileUseCase(
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
  );
});

// R-10: Beginner Resume flow - reuses every block repository the standard
// Editor already does, no parallel persistence path.
final createBeginnerResumeUseCaseProvider = Provider<CreateBeginnerResumeUseCase>((ref) {
  return CreateBeginnerResumeUseCase(
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    educationBlockRepository: ref.watch(educationBlockRepositoryProvider),
    experienceBlockRepository: ref.watch(experienceBlockRepositoryProvider),
    certificationBlockRepository: ref.watch(certificationBlockRepositoryProvider),
    skillEntryRepository: ref.watch(skillEntryRepositoryProvider),
    customSectionBlockRepository: ref.watch(customSectionBlockRepositoryProvider),
  );
});

final deleteLibraryBlockUseCaseProvider =
    Provider<DeleteLibraryBlockUseCase>((ref) {
  return DeleteLibraryBlockUseCase(
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    resumeRepository: ref.watch(resumeRepositoryProvider),
    experienceBlockRepository: ref.watch(experienceBlockRepositoryProvider),
    educationBlockRepository: ref.watch(educationBlockRepositoryProvider),
    projectBlockRepository: ref.watch(projectBlockRepositoryProvider),
    certificationBlockRepository:
        ref.watch(certificationBlockRepositoryProvider),
    skillEntryRepository: ref.watch(skillEntryRepositoryProvider),
    customSectionBlockRepository: ref.watch(customSectionBlockRepositoryProvider),
  );
});

final saveResumeVersionUseCaseProvider =
    Provider<SaveResumeVersionUseCase>((ref) {
  return SaveResumeVersionUseCase(
    compilerService: ref.watch(resumeCompilerServiceProvider),
    resumeVersionRepository: ref.watch(resumeVersionRepositoryProvider),
    pdfExportService: ref.watch(resumePdfExportServiceProvider),
    outputPathProvider: newCareerOutputPath,
  );
});

// Batch 7 - Offline Resume Import.

final resumeImportFilePickerServiceProvider =
    Provider<ResumeImportFilePickerService>((ref) {
  return FilePickerResumeImportFilePickerService();
});

final resumeImportParserProvider = Provider<ResumeImportParser>((ref) {
  return const ResumeImportParser();
});

final importResumeUseCaseProvider = Provider<ImportResumeUseCase>((ref) {
  return ImportResumeUseCase(
    extractors: ref.watch(documentTextExtractorsProvider),
    parser: ref.watch(resumeImportParserProvider),
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    experienceBlockRepository: ref.watch(experienceBlockRepositoryProvider),
    educationBlockRepository: ref.watch(educationBlockRepositoryProvider),
    projectBlockRepository: ref.watch(projectBlockRepositoryProvider),
    certificationBlockRepository:
        ref.watch(certificationBlockRepositoryProvider),
    skillEntryRepository: ref.watch(skillEntryRepositoryProvider),
    customSectionBlockRepository: ref.watch(customSectionBlockRepositoryProvider),
  );
});

// docs/v3/01-prd.md §10/§25 Milestone 4 - optional LLM-assisted import
// second pass.
final resumeImportSecondPassPromptBuilderProvider =
    Provider<ResumeImportSecondPassPromptBuilder>((ref) {
  return const ResumeImportSecondPassPromptBuilder();
});

final generateImportSecondPassUseCaseProvider = Provider<GenerateImportSecondPassUseCase>((ref) {
  return GenerateImportSecondPassUseCase(
    llmEngine: ref.watch(llmEngineProvider),
    llmRequestQueue: ref.watch(llmRequestQueueProvider),
    parser: ref.watch(resumeImportParserProvider),
    promptBuilder: ref.watch(resumeImportSecondPassPromptBuilderProvider),
  );
});

// Batch 8 - Offline Job Description Ingestion + Resume <-> JD Analysis.

final jdImportFilePickerServiceProvider =
    Provider<JdImportFilePickerService>((ref) {
  return FilePickerJdImportFilePickerService();
});

final jdParserProvider = Provider<JdParser>((ref) {
  return const JdParser();
});

final importJdUseCaseProvider = Provider<ImportJdUseCase>((ref) {
  return ImportJdUseCase(
    extractors: ref.watch(documentTextExtractorsProvider),
    parser: ref.watch(jdParserProvider),
  );
});

final createResumeFromJdUseCaseProvider = Provider<CreateResumeFromJdUseCase>((ref) {
  return CreateResumeFromJdUseCase(
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    createResumeFromProfileUseCase: ref.watch(createResumeFromProfileUseCaseProvider),
  );
});

/// docs/v3/01-prd.md §25 Milestone 2: [ResumeJdSemanticMatcher] wraps the
/// same [embeddingEngineProvider] every other embedding-backed feature
/// already shares (indexing/retrieval) - no second embedding engine
/// instance, no separate model. If the embedding model is unavailable or
/// fails *while actually matching*, [ResumeJdSemanticMatcher] itself
/// swallows the error and returns null matches (hard requirement 4).
///
/// The `try`/`catch` here covers the other half of that same requirement:
/// unlike every other [embeddingEngineProvider] consumer, deterministic
/// keyword/alias matching is [ResumeJdAnalyzer]'s trust anchor and must
/// keep working even if *constructing* the embedding engine itself fails
/// (e.g. settings/model-catalog state isn't available yet) - a failure
/// here degrades to `null`, which [resumeJdAnalyzerProvider] already
/// treats as "no semantic tier" via its optional `semanticMatcher` param,
/// exactly like the fully offline/AI-disabled case.
final resumeJdSemanticMatcherProvider = Provider<ResumeJdSemanticMatcher?>((ref) {
  try {
    return ResumeJdSemanticMatcher(embeddingEngine: ref.watch(embeddingEngineProvider));
  } catch (_) {
    return null;
  }
});

final resumeJdAnalyzerProvider = Provider<ResumeJdAnalyzer>((ref) {
  return ResumeJdAnalyzer(semanticMatcher: ref.watch(resumeJdSemanticMatcherProvider));
});

final prioritizeResumeContentUseCaseProvider = Provider<PrioritizeResumeContentUseCase>((ref) {
  return const PrioritizeResumeContentUseCase();
});

final analyzeResumeAgainstJdUseCaseProvider =
    Provider<AnalyzeResumeAgainstJdUseCase>((ref) {
  return AnalyzeResumeAgainstJdUseCase(
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    compilerService: ref.watch(resumeCompilerServiceProvider),
    analyzer: ref.watch(resumeJdAnalyzerProvider),
  );
});

// docs/v3/01-prd.md §25 Milestone 3 - AI rewrite suggestions.
final resumeSuggestionPromptBuilderProvider = Provider<ResumeSuggestionPromptBuilder>((ref) {
  return const ResumeSuggestionPromptBuilder();
});

final generateResumeSuggestionsUseCaseProvider =
    Provider<GenerateResumeSuggestionsUseCase>((ref) {
  return GenerateResumeSuggestionsUseCase(
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    compilerService: ref.watch(resumeCompilerServiceProvider),
    analyzer: ref.watch(resumeJdAnalyzerProvider),
    llmEngine: ref.watch(llmEngineProvider),
    llmRequestQueue: ref.watch(llmRequestQueueProvider),
    suggestedEditRepository: ref.watch(suggestedEditRepositoryProvider),
    // docs/v3/01-prd.md §13 (D-11, RV3-04) - low-RAM-tier sequencing.
    deviceCapabilityService: ref.watch(deviceCapabilityServiceProvider),
    modelLifecycleManager: ref.watch(modelLifecycleManagerProvider),
    promptBuilder: ref.watch(resumeSuggestionPromptBuilderProvider),
  );
});

final acceptSuggestedEditUseCaseProvider = Provider<AcceptSuggestedEditUseCase>((ref) {
  return AcceptSuggestedEditUseCase(
    suggestedEditRepository: ref.watch(suggestedEditRepositoryProvider),
    resumeRepository: ref.watch(resumeRepositoryProvider),
    resumeBlockRepository: ref.watch(resumeBlockRepositoryProvider),
    compilerService: ref.watch(resumeCompilerServiceProvider),
  );
});

final rejectSuggestedEditUseCaseProvider = Provider<RejectSuggestedEditUseCase>((ref) {
  return RejectSuggestedEditUseCase(suggestedEditRepository: ref.watch(suggestedEditRepositoryProvider));
});

// docs/v3/01-prd.md §25 Milestone 4 - Tier 2 writing suggestions
// (BulletSuggestionField). Deliberately no SuggestedEditRepository
// dependency - see GenerateBulletRewriteUseCase's own doc comment.
final generateBulletRewriteUseCaseProvider = Provider<GenerateBulletRewriteUseCase>((ref) {
  return GenerateBulletRewriteUseCase(
    llmEngine: ref.watch(llmEngineProvider),
    llmRequestQueue: ref.watch(llmRequestQueueProvider),
    promptBuilder: ref.watch(resumeSuggestionPromptBuilderProvider),
  );
});

/// docs/v3/01-prd.md §13 - the model-upgrade prompt's own device-RAM hint.
/// [deviceCapabilityServiceProvider] otherwise has no consumer yet (see its
/// own doc comment) - this is that first real use, purely informational
/// (never blocks the feature - a read failure/unknown RAM degrades to
/// [RecommendedDeviceTier.anyModernPhone] via [recommendedTierForRamMb]
/// itself, not a thrown error here).
final resumeRecommendedDeviceTierProvider = FutureProvider<RecommendedDeviceTier>((ref) async {
  final ramMb = await ref.watch(deviceCapabilityServiceProvider).totalRamMb();
  return recommendedTierForRamMb(ramMb);
});
