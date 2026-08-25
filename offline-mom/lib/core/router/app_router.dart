import 'package:go_router/go_router.dart';

import '../../features/ask/presentation/screens/ask_screen.dart';
import '../../features/career/analysis/presentation/providers/resume_jd_analysis_providers.dart';
import '../../features/career/analysis/presentation/screens/resume_jd_analysis_screen.dart';
import '../../features/career/jd/presentation/screens/jd_import_screen.dart';
import '../../features/career/jd/presentation/screens/jd_to_resume_screen.dart';
import '../../features/career/resume/presentation/screens/beginner_resume_screen.dart';
import '../../features/career/resume/presentation/screens/jd_tailored_resume_screen.dart';
import '../../features/career/resume/presentation/screens/beginner_resume_template_screen.dart';
import '../../features/career/resume/presentation/screens/certification_block_editor_screen.dart';
import '../../features/career/resume/presentation/screens/education_block_editor_screen.dart';
import '../../features/career/resume/presentation/screens/experience_block_editor_screen.dart';
import '../../features/career/resume/presentation/screens/project_block_editor_screen.dart';
import '../../features/career/resume/presentation/screens/resume_editor_screen.dart';
import '../../features/career/resume/presentation/screens/resume_create_from_profile_screen.dart';
import '../../features/career/resume/presentation/screens/resume_import_screen.dart';
import '../../features/career/resume/presentation/screens/resume_list_screen.dart';
import '../../features/career/resume/presentation/screens/resume_preview_screen.dart';
import '../../features/career/resume/presentation/screens/resume_suggestion_review_screen.dart';
import '../../features/career/resume/presentation/screens/resume_template_detail_screen.dart';
import '../../features/career/resume/presentation/screens/resume_template_gallery_screen.dart';
import '../../features/career/resume/presentation/screens/resume_versions_screen.dart';
import '../../features/chat/presentation/providers/chat_providers.dart';
import '../../features/chat/presentation/screens/chat_history_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/documents/presentation/screens/document_details_screen.dart';
import '../../features/documents/presentation/screens/document_import_screen.dart';
import '../../features/documents/presentation/screens/documents_screen.dart';
import '../../features/export/presentation/screens/export_screen.dart';
import '../../features/export/presentation/screens/pdf_preview_screen.dart';
import '../../features/import/presentation/screens/import_screen.dart';
import '../../features/meetings/presentation/screens/history_screen.dart';
import '../../features/meetings/presentation/screens/home_screen.dart';
import '../../features/meetings/presentation/screens/meeting_details_screen.dart';
import '../../features/onboarding/presentation/screens/model_setup_screen.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/onboarding/presentation/screens/welcome_name_screen.dart';
import '../../features/onboarding/presentation/screens/why_offline_screen.dart';
import '../../features/recording/presentation/screens/record_screen.dart';
import '../../features/recording/presentation/screens/recording_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/ai_models/presentation/screens/ai_model_manager_screen.dart';
import '../../features/ai_models/presentation/screens/model_details_screen.dart';
import '../../features/ai_models/presentation/screens/model_storage_screen.dart';
import '../../features/ai_models/presentation/screens/profession_setup_screen.dart';
import '../../features/settings/presentation/screens/appearance_screen.dart';
import '../../features/settings/presentation/screens/backup_screen.dart';
import '../../features/settings/presentation/screens/help_screen.dart';
import '../../features/settings/presentation/screens/language_screen.dart';
import '../../features/settings/presentation/screens/offline_readiness_screen.dart';
import '../../features/settings/presentation/screens/privacy_screen.dart';
import '../../features/settings/presentation/screens/recording_preferences_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/storage_screen.dart';
import '../../features/student_toolkit/presentation/screens/image_compress_screen.dart';
import '../../features/student_toolkit/presentation/screens/image_resize_screen.dart';
import '../../features/student_toolkit/presentation/screens/images_to_pdf_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_compress_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_edit_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_merge_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_organize_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_redact_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_split_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_to_images_screen.dart';
import '../../features/student_toolkit/presentation/screens/scanner_screen.dart';
import '../../features/student_toolkit/presentation/screens/student_toolkit_screen.dart';
import '../../features/student_toolkit/presentation/screens/toolkit_files_screen.dart';
import '../../features/student_toolkit/presentation/screens/ocr_screen.dart';
import '../../features/student_toolkit/presentation/screens/pdf_protect_screen.dart';
import '../../features/student_toolkit/presentation/screens/view_pdf_screen.dart';
import '../../models/job_description.dart';
import '../../services/export/pdf_export_service.dart';
import '../../shared/widgets/app_shell.dart';
import 'route_paths.dart';

int _meetingIdFrom(GoRouterState state) =>
    int.parse(state.pathParameters['meetingId']!);

// V2 scaffolding (Epic 2, docs/v2/implementation/02-backlog.md).
int _documentIdFrom(GoRouterState state) =>
    int.parse(state.pathParameters['documentId']!);

// V3 Milestone 1 (Batch 5).
int _resumeIdFrom(GoRouterState state) =>
    int.parse(state.pathParameters['resumeId']!);
int _versionIdFrom(GoRouterState state) =>
    int.parse(state.pathParameters['versionId']!);
int _blockIdFrom(GoRouterState state) =>
    int.parse(state.pathParameters['blockId']!);
String _templateIdFrom(GoRouterState state) => state.pathParameters['templateId']!;

final appRouter = GoRouter(
  initialLocation: RoutePaths.splash,
  routes: [
    GoRoute(
      path: RoutePaths.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: RoutePaths.onboardingWhy,
      builder: (context, state) => const WhyOfflineScreen(),
    ),
    GoRoute(
      path: RoutePaths.onboardingName,
      builder: (context, state) => const WelcomeNameScreen(),
    ),
    GoRoute(
      path: RoutePaths.onboardingSetup,
      builder: (context, state) => const ModelSetupScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: RoutePaths.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: RoutePaths.history,
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: RoutePaths.search,
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: RoutePaths.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: RoutePaths.record,
      builder: (context, state) => const RecordScreen(),
    ),
    GoRoute(
      path: RoutePaths.recording,
      builder: (context, state) => const RecordingScreen(),
    ),
    GoRoute(
      path: RoutePaths.import_,
      builder: (context, state) => const ImportScreen(),
    ),
    GoRoute(
      path: RoutePaths.ask,
      builder: (context, state) => const AskScreen(),
    ),
    GoRoute(
      path: RoutePaths.meetingDetails,
      builder: (context, state) =>
          MeetingDetailsScreen(meetingId: _meetingIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.pdfPreview,
      builder: (context, state) => PdfPreviewScreen(
        meetingId: _meetingIdFrom(state),
        sections: state.extra is ReportSections
            ? state.extra as ReportSections
            : const ReportSections(),
      ),
    ),
    GoRoute(
      path: RoutePaths.export_,
      builder: (context, state) =>
          ExportScreen(meetingId: _meetingIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.about,
      builder: (context, state) => const AboutScreen(),
    ),
    GoRoute(
      path: RoutePaths.privacy,
      builder: (context, state) => const PrivacyScreen(),
    ),
    GoRoute(
      path: RoutePaths.help,
      builder: (context, state) => const HelpScreen(),
    ),
    GoRoute(
      path: RoutePaths.appearance,
      builder: (context, state) => const AppearanceScreen(),
    ),
    GoRoute(
      path: RoutePaths.aiModels,
      builder: (context, state) => const AiModelManagerScreen(),
    ),
    GoRoute(
      path: RoutePaths.offlineReadiness,
      builder: (context, state) => const OfflineReadinessScreen(),
    ),
    // Both registered before RoutePaths.aiModelDetails (":modelId") so
    // these static segments match first rather than being captured as a
    // modelId path parameter - same reasoning as documentImport/
    // documentDetails above (AI Model Manager, Phase 6A).
    GoRoute(
      path: RoutePaths.aiModelSetup,
      builder: (context, state) => const ProfessionSetupScreen(),
    ),
    GoRoute(
      path: RoutePaths.aiModelStorage,
      builder: (context, state) => const ModelStorageScreen(),
    ),
    GoRoute(
      path: RoutePaths.aiModelDetails,
      builder: (context, state) =>
          ModelDetailsScreen(modelId: state.pathParameters['modelId']!),
    ),
    GoRoute(
      path: RoutePaths.storage,
      builder: (context, state) => const StorageScreen(),
    ),
    GoRoute(
      path: RoutePaths.recordingPreferences,
      builder: (context, state) => const RecordingPreferencesScreen(),
    ),
    GoRoute(
      path: RoutePaths.language,
      builder: (context, state) => const LanguageScreen(),
    ),
    GoRoute(
      path: RoutePaths.backup,
      builder: (context, state) => const BackupScreen(),
    ),

    GoRoute(
      path: RoutePaths.documents,
      builder: (context, state) => const DocumentsScreen(),
    ),
    // Registered before RoutePaths.documentDetails (":documentId") so the
    // static "/documents/import" segment matches first rather than being
    // captured as a documentId path parameter.
    GoRoute(
      path: RoutePaths.documentImport,
      builder: (context, state) => const DocumentImportScreen(),
    ),
    GoRoute(
      path: RoutePaths.documentDetails,
      builder: (context, state) =>
          DocumentDetailsScreen(documentId: _documentIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.chat,
      builder: (context, state) => ChatScreen(
        launchArgs: state.extra is ChatLaunchArgs ? state.extra as ChatLaunchArgs : null,
      ),
    ),
    GoRoute(
      path: RoutePaths.chatHistory,
      builder: (context, state) => const ChatHistoryScreen(),
    ),

    GoRoute(
      path: RoutePaths.studentToolkit,
      builder: (context, state) => const StudentToolkitScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitCompressImage,
      builder: (context, state) => const ImageCompressScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitResizeImage,
      builder: (context, state) => const ImageResizeScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitRecentFiles,
      builder: (context, state) => const ToolkitFilesScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitScan,
      builder: (context, state) => const ScannerScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitCompressPdf,
      builder: (context, state) => const PdfCompressScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitMergePdf,
      builder: (context, state) => const PdfMergeScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitSplitPdf,
      builder: (context, state) => const PdfSplitScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitOrganizePdf,
      builder: (context, state) => const PdfOrganizeScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitEditPdf,
      builder: (context, state) => const PdfEditScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitRedactPdf,
      builder: (context, state) => const PdfRedactScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitImagesToPdf,
      builder: (context, state) => const ImagesToPdfScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitPdfToImages,
      builder: (context, state) => const PdfToImagesScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitViewPdf,
      builder: (context, state) => const ViewPdfScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitOcr,
      builder: (context, state) => const OcrScreen(),
    ),
    GoRoute(
      path: RoutePaths.toolkitPdfProtect,
      builder: (context, state) => const PdfProtectScreen(),
    ),

    // Career - Resume Builder (V3 Milestone 1, Batch 5).
    GoRoute(
      path: RoutePaths.resumeList,
      builder: (context, state) => const ResumeListScreen(),
    ),
    // Registered before resumeEditor (":resumeId") - see route_paths.dart's
    // own comment on RoutePaths.resumeImport for why.
    GoRoute(
      path: RoutePaths.resumeImport,
      builder: (context, state) => const ResumeImportScreen(),
    ),
    // Product Validation phase ("My Profile") - registered before
    // resumeEditor (":resumeId") for the same reason as resumeImport above.
    GoRoute(
      path: RoutePaths.resumeCreateFromProfile,
      builder: (context, state) => const ResumeCreateFromProfileScreen(),
    ),
    // R-10 (Beginner Resume flow) - registered before resumeEditor
    // (":resumeId") for the same reason as resumeImport/resumeCreateFromProfile.
    GoRoute(
      path: RoutePaths.resumeBeginner,
      builder: (context, state) => const BeginnerResumeScreen(),
    ),
    GoRoute(
      path: RoutePaths.resumeBeginnerTemplate,
      builder: (context, state) => BeginnerResumeTemplateScreen(resumeId: _resumeIdFrom(state)),
    ),
    // AI-Tailored Resume from Job Description - registered before
    // resumeEditor (":resumeId") for the same reason as
    // resumeImport/resumeCreateFromProfile/resumeBeginner.
    GoRoute(
      path: RoutePaths.resumeJdTailored,
      builder: (context, state) => const JdTailoredResumeScreen(),
    ),
    GoRoute(
      path: RoutePaths.resumeVersionPreview,
      builder: (context, state) => ResumePreviewScreen(
        resumeId: _resumeIdFrom(state),
        versionId: _versionIdFrom(state),
      ),
    ),
    GoRoute(
      path: RoutePaths.resumeVersions,
      builder: (context, state) => ResumeVersionsScreen(resumeId: _resumeIdFrom(state)),
    ),
    // V3 Milestone 3 (AI rewrite suggestions) - registered before
    // resumeEditor (":resumeId") for the same reason as every other
    // specific "/resume/..." route above.
    GoRoute(
      path: RoutePaths.resumeSuggestions,
      builder: (context, state) => ResumeSuggestionReviewScreen(resumeId: _resumeIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.resumePreview,
      builder: (context, state) => ResumePreviewScreen(resumeId: _resumeIdFrom(state)),
    ),
    // V3 Milestone 1 (Template Engine) - registered before resumeEditor
    // (":resumeId") for the same reason as every other specific "/resume/..."
    // route above.
    GoRoute(
      path: RoutePaths.resumeTemplates,
      builder: (context, state) => ResumeTemplateGalleryScreen(resumeId: _resumeIdFrom(state)),
    ),
    // Beta Product Validation phase - "tap a template -> larger real
    // preview -> Use This Template" confirm step, a child of
    // resumeTemplates so a specific ":templateId" segment is required
    // (never ambiguous with the gallery's own path above it).
    GoRoute(
      path: RoutePaths.resumeTemplateDetail,
      builder: (context, state) => ResumeTemplateDetailScreen(
        resumeId: _resumeIdFrom(state),
        templateId: _templateIdFrom(state),
      ),
    ),
    // Every "block/<type>/new" route is registered before its own
    // "block/<type>/:blockId" sibling so the static "new" segment matches
    // first rather than being captured as a blockId path parameter - same
    // reasoning as documentImport/documentDetails above.
    GoRoute(
      path: RoutePaths.resumeExperienceBlockNew,
      builder: (context, state) => ExperienceBlockEditorScreen(resumeId: _resumeIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.resumeExperienceBlockEdit,
      builder: (context, state) => ExperienceBlockEditorScreen(
        resumeId: _resumeIdFrom(state),
        blockId: _blockIdFrom(state),
      ),
    ),
    GoRoute(
      path: RoutePaths.resumeEducationBlockNew,
      builder: (context, state) => EducationBlockEditorScreen(resumeId: _resumeIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.resumeEducationBlockEdit,
      builder: (context, state) => EducationBlockEditorScreen(
        resumeId: _resumeIdFrom(state),
        blockId: _blockIdFrom(state),
      ),
    ),
    GoRoute(
      path: RoutePaths.resumeProjectBlockNew,
      builder: (context, state) => ProjectBlockEditorScreen(resumeId: _resumeIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.resumeProjectBlockEdit,
      builder: (context, state) => ProjectBlockEditorScreen(
        resumeId: _resumeIdFrom(state),
        blockId: _blockIdFrom(state),
      ),
    ),
    GoRoute(
      path: RoutePaths.resumeCertificationBlockNew,
      builder: (context, state) => CertificationBlockEditorScreen(resumeId: _resumeIdFrom(state)),
    ),
    GoRoute(
      path: RoutePaths.resumeCertificationBlockEdit,
      builder: (context, state) => CertificationBlockEditorScreen(
        resumeId: _resumeIdFrom(state),
        blockId: _blockIdFrom(state),
      ),
    ),
    // Registered last among "/resume/..." routes so the more specific
    // paths above (preview/versions/block/...) all match before this
    // catch-all ":resumeId" segment does.
    GoRoute(
      path: RoutePaths.resumeEditor,
      builder: (context, state) => ResumeEditorScreen(resumeId: _resumeIdFrom(state)),
    ),

    // Career - Offline JD Ingestion + Resume <-> JD Analysis (Batch 8).
    GoRoute(
      path: RoutePaths.jdImport,
      builder: (context, state) => const JdImportScreen(),
    ),
    GoRoute(
      path: RoutePaths.jdToResume,
      builder: (context, state) => const JdToResumeScreen(),
    ),
    GoRoute(
      path: RoutePaths.resumeJdAnalysis,
      // `JdImportScreen` (the existing "analyze an existing resume" flow)
      // keeps passing a bare `ParsedJobDescription` via `extra`, unchanged;
      // `JdToResumeScreen` (R-7 §3) passes the richer
      // `ResumeJdAnalysisLaunchArgs` when it already knows which resume to
      // analyze, so the picker step can be skipped.
      builder: (context, state) {
        final extra = state.extra;
        if (extra is ResumeJdAnalysisLaunchArgs) {
          return ResumeJdAnalysisScreen(jd: extra.jd, initialResumeId: extra.initialResumeId);
        }
        return ResumeJdAnalysisScreen(jd: extra as ParsedJobDescription);
      },
    ),
  ],
);
