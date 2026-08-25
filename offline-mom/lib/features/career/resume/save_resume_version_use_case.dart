import '../../../models/resume.dart';
import '../../../models/resume_block_ref.dart';
import '../../../models/resume_version.dart';
import '../../../repositories/resume_version_repository.dart';
import '../../../services/resume/resume_compiler_service.dart';
import '../../../services/resume/resume_pdf_export_service.dart';
import '../../../services/resume/template/resume_template_catalog.dart';

/// Turns a Resume's live block composition into a new, permanent
/// [ResumeVersion]: compile -> persist -> optional PDF export, in that
/// order. Mirrors [ProcessNewMeetingUseCase]'s "orchestrate a service plus
/// a repository" shape, one level narrower.
///
/// **Template threading (docs/v3/01-prd.md §16, Milestone 1):** the
/// version is rendered and persisted with whichever template [resume]
/// .templateId already names, resolved via
/// [ResumeTemplateCatalog.specById] - which itself falls back to
/// [ResumeTemplateCatalog.defaultSpec] (Classic Single-Column) for `null`
/// or an unrecognized id, so a resume that has never had a template
/// explicitly chosen (every resume that existed before this milestone)
/// keeps rendering exactly as it always did. No new parameter was added
/// to [call] for this - `resume` was already passed in full, so its own
/// `templateId` field (added in Milestone 0) is read directly rather than
/// threading a second, redundant argument alongside it.
///
/// [outputPathProvider] generates the export destination (in practice,
/// `newCareerOutputPath` from `core/utils/career_paths.dart`) - injected
/// rather than called directly, matching this codebase's own convention
/// of calling its `newXOutputPath` helpers from the presentation layer
/// (every existing `newToolkitOutputPath`/`newAudioFilePath` call site is
/// a provider, never a use case). Keeping it injected here means this use
/// case has no `path_provider` platform-channel dependency of its own and
/// can be exercised with a plain in-memory function in tests.
///
/// The error boundary here is the one property this whole flow exists to
/// guarantee: once the version row is persisted, nothing in this method
/// can undo that. If [ResumePdfExportService.exportToFile] throws, that
/// exception propagates to the caller exactly as thrown - deliberately
/// not caught here - but the version this method already inserted stays
/// in the database with `exportedPdfPath` left null, not rolled back.
/// [ResumeVersionRepository.setExportedPdfPath] is only ever called after
/// export has already succeeded, so a failed export simply never reaches
/// it, rather than needing to be undone.
class SaveResumeVersionUseCase {
  SaveResumeVersionUseCase({
    required ResumeCompilerService compilerService,
    required ResumeVersionRepository resumeVersionRepository,
    required ResumePdfExportService pdfExportService,
    required Future<String> Function(String extension) outputPathProvider,
  })  : _compilerService = compilerService,
        _resumeVersionRepository = resumeVersionRepository,
        _pdfExportService = pdfExportService,
        _outputPathProvider = outputPathProvider;

  final ResumeCompilerService _compilerService;
  final ResumeVersionRepository _resumeVersionRepository;
  final ResumePdfExportService _pdfExportService;
  final Future<String> Function(String extension) _outputPathProvider;

  Future<ResumeVersion> call(
    Resume resume,
    List<ResumeBlockRef> blockRefs, {
    required String versionLabel,
  }) async {
    final snapshot = await _compilerService.compile(resume, blockRefs);
    final templateSpec = ResumeTemplateCatalog.specById(resume.templateId);

    final versionId = await _resumeVersionRepository.insert(ResumeVersion(
      id: null,
      resumeId: resume.id!,
      versionLabel: versionLabel,
      compiledSnapshot: snapshot,
      exportedPdfPath: null,
      templateId: templateSpec.id,
      createdAt: DateTime.now(),
    ));

    // From this point on, the version is persisted. Nothing below may
    // delete or otherwise undo it - a PDF export failure only ever means
    // exportedPdfPath stays null, propagated to the caller as a thrown
    // exception, never as a lost version.
    final destinationPath = await _outputPathProvider('pdf');
    final finalPath =
        await _pdfExportService.exportToFile(snapshot, destinationPath, templateSpec: templateSpec);
    await _resumeVersionRepository.setExportedPdfPath(versionId, finalPath);

    return (await _resumeVersionRepository.getById(versionId))!;
  }
}
