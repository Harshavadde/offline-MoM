/// All route paths/names in one place so screens never hand-type a string
/// that could silently drift from the router config.
class RoutePaths {
  RoutePaths._();

  static const splash = '/';
  static const onboardingWhy = '/onboarding/why';
  static const onboardingName = '/onboarding/name';
  static const onboardingSetup = '/onboarding/setup';
  static const home = '/home';
  static const history = '/history';
  static const search = '/search';
  static const settings = '/settings';

  static const record = '/record';
  static const recording = '/record/session';
  static const import_ = '/import';
  static const ask = '/ask';

  // Transcript/Summary/MoM/Action Items/Notes are tabs within the single
  // Meeting Details screen, not separate routes.
  static const meetingDetails = '/meetings/:meetingId';
  static const pdfPreview = '/meetings/:meetingId/export/preview';
  static const export_ = '/meetings/:meetingId/export';

  static const about = '/settings/about';
  static const privacy = '/settings/privacy';
  static const help = '/settings/help';
  static const appearance = '/settings/appearance';
  static const aiModels = '/settings/ai-models';
  static const aiModelSetup = '/settings/ai-models/setup';
  static const aiModelStorage = '/settings/ai-models/storage';
  static const aiModelDetails = '/settings/ai-models/:modelId';
  static String aiModelDetailsPath(String modelId) => '/settings/ai-models/$modelId';
  static const storage = '/settings/storage';
  static const offlineReadiness = '/settings/offline-readiness';
  static const recordingPreferences = '/settings/recording';
  static const language = '/settings/language';
  static const backup = '/settings/backup';

  static String meetingDetailsPath(int id) => '/meetings/$id';
  static String pdfPreviewPath(int id) => '/meetings/$id/export/preview';
  static String exportPath(int id) => '/meetings/$id/export';

  static const documents = '/documents';
  static const documentImport = '/documents/import';
  static const documentDetails = '/documents/:documentId';

  // Single chat screen with an in-chat scope selector (ADR-013,
  // docs/v2/implementation/03-decisions.md) - reachable from Home and from
  // "Chat about this" actions on meeting/document details (V2 Phase 2A).
  // `state.extra` carries an optional `ChatLaunchArgs` (see
  // lib/features/chat/presentation/providers/chat_providers.dart) to
  // pre-scope a new conversation or resume a specific past one.
  static const chat = '/chat';
  static const chatHistory = '/chat/history';

  static String documentDetailsPath(int id) => '/documents/$id';

  // Student Toolkit - Image Tools (V2 Phase 5A, ADR-033); Scanner + PDF
  // Tools (V2 Phase 5B, ADR-034). docs/v2/implementation/03-decisions.md.
  static const studentToolkit = '/toolkit';
  static const toolkitCompressImage = '/toolkit/compress-image';
  static const toolkitResizeImage = '/toolkit/resize-image';
  static const toolkitRecentFiles = '/toolkit/recent';
  static const toolkitScan = '/toolkit/scan';
  static const toolkitCompressPdf = '/toolkit/compress-pdf';
  static const toolkitMergePdf = '/toolkit/merge-pdf';
  static const toolkitSplitPdf = '/toolkit/split-pdf';
  static const toolkitOrganizePdf = '/toolkit/organize-pdf';
  static const toolkitEditPdf = '/toolkit/edit-pdf';
  static const toolkitRedactPdf = '/toolkit/redact-pdf';
  static const toolkitImagesToPdf = '/toolkit/images-to-pdf';
  static const toolkitPdfToImages = '/toolkit/pdf-to-images';
  static const toolkitViewPdf = '/toolkit/view-pdf';
  static const toolkitOcr = '/toolkit/ocr';
  static const toolkitPdfProtect = '/toolkit/pdf-protect';

  // Career - Resume Builder (V3 Milestone 1, Batch 5).
  static const resumeList = '/resume';
  // Registered before resumeEditor (":resumeId") so this static segment
  // matches first rather than being captured as a resumeId path parameter -
  // same reasoning as documentImport/documentDetails (Batch 7).
  static const resumeImport = '/resume/import';
  // Product Validation phase ("My Profile") - also a static segment,
  // registered before resumeEditor for the same reason as resumeImport.
  static const resumeCreateFromProfile = '/resume/create-from-profile';
  // R-10 (Beginner Resume flow) - also a static segment, registered before
  // resumeEditor for the same reason as resumeImport/resumeCreateFromProfile.
  static const resumeBeginner = '/resume/beginner';
  // AI-Tailored Resume from Job Description - also a static segment,
  // registered before resumeEditor for the same reason as
  // resumeImport/resumeCreateFromProfile/resumeBeginner.
  static const resumeJdTailored = '/resume/jd-tailored';
  static const resumeBeginnerTemplate = '/resume/:resumeId/beginner-template';
  static const resumeEditor = '/resume/:resumeId';
  static const resumePreview = '/resume/:resumeId/preview';
  // V3 Milestone 1 (Template Engine).
  static const resumeTemplates = '/resume/:resumeId/templates';
  // Beta Product Validation phase - the "tap a template -> larger real
  // preview -> Use This Template" confirm step (registered as a distinct
  // child of resumeTemplates, not a query param, matching every other
  // detail route's own convention in this file).
  static const resumeTemplateDetail = '/resume/:resumeId/templates/:templateId';
  static const resumeVersions = '/resume/:resumeId/versions';
  // V3 Milestone 3 (AI rewrite suggestions).
  static const resumeSuggestions = '/resume/:resumeId/suggestions';
  static const resumeVersionPreview =
      '/resume/:resumeId/versions/:versionId/preview';
  static const resumeExperienceBlockNew = '/resume/:resumeId/block/experience/new';
  static const resumeExperienceBlockEdit =
      '/resume/:resumeId/block/experience/:blockId';
  static const resumeEducationBlockNew = '/resume/:resumeId/block/education/new';
  static const resumeEducationBlockEdit =
      '/resume/:resumeId/block/education/:blockId';
  static const resumeProjectBlockNew = '/resume/:resumeId/block/project/new';
  static const resumeProjectBlockEdit = '/resume/:resumeId/block/project/:blockId';
  static const resumeCertificationBlockNew =
      '/resume/:resumeId/block/certification/new';
  static const resumeCertificationBlockEdit =
      '/resume/:resumeId/block/certification/:blockId';

  static String resumeBeginnerTemplatePath(int resumeId) => '/resume/$resumeId/beginner-template';
  static String resumeEditorPath(int resumeId) => '/resume/$resumeId';
  static String resumePreviewPath(int resumeId) => '/resume/$resumeId/preview';
  static String resumeTemplatesPath(int resumeId) => '/resume/$resumeId/templates';
  static String resumeTemplateDetailPath(int resumeId, String templateId) =>
      '/resume/$resumeId/templates/$templateId';
  static String resumeVersionsPath(int resumeId) => '/resume/$resumeId/versions';
  static String resumeSuggestionsPath(int resumeId) => '/resume/$resumeId/suggestions';
  static String resumeVersionPreviewPath(int resumeId, int versionId) =>
      '/resume/$resumeId/versions/$versionId/preview';
  static String resumeExperienceBlockNewPath(int resumeId) =>
      '/resume/$resumeId/block/experience/new';
  static String resumeExperienceBlockEditPath(int resumeId, int blockId) =>
      '/resume/$resumeId/block/experience/$blockId';
  static String resumeEducationBlockNewPath(int resumeId) =>
      '/resume/$resumeId/block/education/new';
  static String resumeEducationBlockEditPath(int resumeId, int blockId) =>
      '/resume/$resumeId/block/education/$blockId';
  static String resumeProjectBlockNewPath(int resumeId) =>
      '/resume/$resumeId/block/project/new';
  static String resumeProjectBlockEditPath(int resumeId, int blockId) =>
      '/resume/$resumeId/block/project/$blockId';
  static String resumeCertificationBlockNewPath(int resumeId) =>
      '/resume/$resumeId/block/certification/new';
  static String resumeCertificationBlockEditPath(int resumeId, int blockId) =>
      '/resume/$resumeId/block/certification/$blockId';

  // Career - Offline JD Ingestion + Resume <-> JD Analysis (Batch 8). Both
  // receive their data (a picked file, or a confirmed `ParsedJobDescription`)
  // via the route's `extra`/user interaction rather than a path parameter -
  // there is no persisted JD id to encode in the URL.
  static const jdImport = '/jd/import';
  static const resumeJdAnalysis = '/jd/analysis';

  // R-7 §3: "Create resume from a Job Description" - paste/import a JD with
  // no existing resume picked first, distinct from `jdImport` (which always
  // leads to picking an existing resume to analyze).
  static const jdToResume = '/jd/create-resume';
}
