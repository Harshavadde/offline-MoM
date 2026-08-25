import '../../../models/job_description.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../resume/create_resume_from_profile_use_case.dart';

/// R-7 §3 ("Create resume from a Job Description"): builds a brand-new,
/// job-specific resume straight from a parsed JD, with no existing resume
/// picked first - the counterpart to the already-existing "pick an
/// existing resume, then analyze it against a JD" flow
/// ([AnalyzeResumeAgainstJdUseCase]/`ResumeJdAnalysisScreen`).
///
/// Deliberately just a composition of two already-built, already-tested
/// pieces rather than new resume-creation logic:
/// [CreateResumeFromProfileUseCase] (seeds the new resume from "My
/// Profile" - the same "MASTER PROFILE -> CREATE RESUME" rule every other
/// resume-creation path already follows, which is also what guarantees
/// nothing here can ever fabricate experience/skills/education: every
/// block attached already exists in the user's own profile, none is
/// invented) does the actual creation, with every one of the profile's
/// blocks included (matching [ResumeCreateFromProfileScreen]'s own
/// "everything selected by default" rule - the caller only ever *removes*
/// what it doesn't want, this use case never guesses a subset for it).
///
/// Content is not reordered by JD relevance here - [PrioritizeResumeContentUseCase]
/// needs a [ResumeJdAnalysisResult] (match evidence) as input, which does
/// not exist yet for a resume that was just created; the caller is
/// expected to run [AnalyzeResumeAgainstJdUseCase] against the returned
/// resume id next (`ResumeJdAnalysisScreen` already does this automatically
/// when given an `initialResumeId`), which is exactly where a user sees
/// job requirements vs. their own experience vs. AI-suggested tailoring,
/// same as the existing-resume flow.
class CreateResumeFromJdUseCase {
  CreateResumeFromJdUseCase({
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required CreateResumeFromProfileUseCase createResumeFromProfileUseCase,
  })  : _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _createResumeFromProfileUseCase = createResumeFromProfileUseCase;

  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final CreateResumeFromProfileUseCase _createResumeFromProfileUseCase;

  /// Throws [NoProfileException] (defined alongside
  /// [CreateResumeFromProfileUseCase]) if "My Profile" hasn't been set up
  /// yet - there is nothing to build a tailored resume from.
  Future<int> call(ParsedJobDescription jd) async {
    final profile = await _resumeRepository.getProfile();
    if (profile == null) {
      throw NoProfileException(
        'Set up My Profile first - there is nothing to create a tailored resume from yet.',
      );
    }

    final allRefs = await _resumeBlockRepository.getForResume(profile.id!);
    return _createResumeFromProfileUseCase(title: _titleFor(jd), selectedRefs: allRefs);
  }

  String _titleFor(ParsedJobDescription jd) {
    final title = jd.title?.trim();
    final company = jd.company?.trim();
    if (title != null && title.isNotEmpty && company != null && company.isNotEmpty) {
      return '$title at $company';
    }
    if (title != null && title.isNotEmpty) return title;
    if (company != null && company.isNotEmpty) return 'Resume for $company';
    return 'Tailored Resume';
  }
}
