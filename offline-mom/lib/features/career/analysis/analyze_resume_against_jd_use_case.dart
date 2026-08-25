import '../../../models/job_description.dart';
import '../../../models/resume_jd_analysis_result.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../services/career/resume_jd_analyzer.dart';
import '../../../services/resume/resume_compiler_service.dart';

/// Thrown when the selected resume can no longer be found (deleted between
/// selection and analysis) - the one genuine failure mode this use case
/// can hit that isn't already covered by `ResumeCompilerService`'s own
/// contract.
class ResumeNotFoundForAnalysisException implements Exception {
  ResumeNotFoundForAnalysisException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Orchestrates one Resume <-> JD analysis run: load the selected resume's
/// identity and live composition (the same two repositories
/// `ResumeEditorController.compileSnapshot` already reads), compile it into
/// a [ResumeSnapshot] via the *existing, unmodified* [ResumeCompilerService]
/// (never a second compiler), then run [ResumeJdAnalyzer] against it.
///
/// Reuses the existing Resume providers/repositories for resume loading
/// per Batch 8's own explicit instruction not to duplicate resume-loading
/// logic - this is the one place that logic needed a *use case* (crossing
/// two repositories plus a service, the same "earns a dedicated use case"
/// bar every other multi-collaborator orchestration in this codebase
/// already follows), not a new loading mechanism.
class AnalyzeResumeAgainstJdUseCase {
  AnalyzeResumeAgainstJdUseCase({
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required ResumeCompilerService compilerService,
    required ResumeJdAnalyzer analyzer,
  })  : _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _compilerService = compilerService,
        _analyzer = analyzer;

  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final ResumeCompilerService _compilerService;
  final ResumeJdAnalyzer _analyzer;

  Future<ResumeJdAnalysisResult> call(int resumeId, ParsedJobDescription jd) async {
    final resume = await _resumeRepository.getById(resumeId);
    if (resume == null) {
      throw ResumeNotFoundForAnalysisException(
        'This resume could not be found. It may have been deleted.',
      );
    }

    final blockRefs = await _resumeBlockRepository.getForResume(resumeId);
    final snapshot = await _compilerService.compile(resume, blockRefs);

    return _analyzer.analyze(snapshot, jd);
  }
}
