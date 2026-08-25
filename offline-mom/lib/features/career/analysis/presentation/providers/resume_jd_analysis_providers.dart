import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../models/job_description.dart';
import '../../../../../models/resume_jd_analysis_result.dart';
import '../../../../../providers/app_providers.dart';
import '../../analyze_resume_against_jd_use_case.dart';

/// One analysis session's state, keyed by the [ParsedJobDescription]
/// instance the JD Import screen handed off - `family` + `autoDispose`,
/// mirroring `ResumeEditorController`'s exact reasoning
/// (lib/features/career/resume/presentation/providers/resume_editor_providers.dart):
/// every screen instance gets its own fresh controller, with zero
/// cross-session state leakage. The family key relies on
/// [ParsedJobDescription]'s default identity equality (it has no `==`
/// override, matching this codebase's plain-model convention) - safe
/// here because exactly one screen instance ever watches this provider
/// for one specific draft, the same draft object the JD Import screen
/// passed through `context.push(..., extra: draft)`.
/// Navigation payload for `RoutePaths.resumeJdAnalysis` when the caller
/// already knows which resume to analyze (R-7 §3's "Create resume from a
/// Job Description" flow, which creates the resume itself before landing
/// here) - mirrors `ChatLaunchArgs`'s exact reasoning
/// (lib/features/chat/presentation/providers/chat_providers.dart). The
/// existing "Analyze against a job description" entry point
/// (`JdImportScreen`) keeps passing a bare [ParsedJobDescription] via
/// `extra`, completely unchanged - the router only wraps it in this class
/// for the one new caller that needs to skip resume selection.
class ResumeJdAnalysisLaunchArgs {
  const ResumeJdAnalysisLaunchArgs({required this.jd, required this.initialResumeId});

  final ParsedJobDescription jd;
  final int initialResumeId;
}

sealed class ResumeJdAnalysisUiState {
  const ResumeJdAnalysisUiState();

  ParsedJobDescription get jd;
}

class ResumeJdAnalysisSelectingResume extends ResumeJdAnalysisUiState {
  const ResumeJdAnalysisSelectingResume({required this.jd});

  @override
  final ParsedJobDescription jd;
}

class ResumeJdAnalysisRunning extends ResumeJdAnalysisUiState {
  const ResumeJdAnalysisRunning({required this.jd, required this.resumeId});

  @override
  final ParsedJobDescription jd;
  final int resumeId;
}

class ResumeJdAnalysisSucceeded extends ResumeJdAnalysisUiState {
  const ResumeJdAnalysisSucceeded({required this.jd, required this.resumeId, required this.result});

  @override
  final ParsedJobDescription jd;
  final int resumeId;
  final ResumeJdAnalysisResult result;
}

class ResumeJdAnalysisFailed extends ResumeJdAnalysisUiState {
  const ResumeJdAnalysisFailed({required this.jd, required this.message});

  @override
  final ParsedJobDescription jd;
  final String message;
}

/// Orchestrates one Resume <-> JD analysis session: the user picks which
/// existing resume to analyze (reusing `resumeListProvider` - no resume
/// loading logic is duplicated here), then [AnalyzeResumeAgainstJdUseCase]
/// runs entirely locally.
class ResumeJdAnalysisController
    extends AutoDisposeFamilyNotifier<ResumeJdAnalysisUiState, ParsedJobDescription> {
  @override
  ResumeJdAnalysisUiState build(ParsedJobDescription jd) {
    return ResumeJdAnalysisSelectingResume(jd: jd);
  }

  Future<void> analyze(int resumeId) async {
    final jd = state.jd;
    state = ResumeJdAnalysisRunning(jd: jd, resumeId: resumeId);

    try {
      final result = await ref.read(analyzeResumeAgainstJdUseCaseProvider)(resumeId, jd);
      state = ResumeJdAnalysisSucceeded(jd: jd, resumeId: resumeId, result: result);
    } on ResumeNotFoundForAnalysisException catch (e) {
      state = ResumeJdAnalysisFailed(jd: jd, message: e.message);
    } catch (e) {
      state = ResumeJdAnalysisFailed(jd: jd, message: friendlyErrorMessage(e));
    }
  }

  /// Returns to resume selection with the same JD, for a retry or to
  /// analyze against a different resume.
  void reset() {
    state = ResumeJdAnalysisSelectingResume(jd: state.jd);
  }
}

final resumeJdAnalysisControllerProvider = NotifierProvider.autoDispose
    .family<ResumeJdAnalysisController, ResumeJdAnalysisUiState, ParsedJobDescription>(
  ResumeJdAnalysisController.new,
);
