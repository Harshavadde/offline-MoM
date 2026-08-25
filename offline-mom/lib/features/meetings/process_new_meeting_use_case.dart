import '../../models/meeting.dart';
import '../../repositories/meeting_repository.dart';
import '../ai_summary/generate_meeting_summary_use_case.dart';
import '../transcription/transcribe_meeting_use_case.dart';
import 'meeting_indexer.dart';

/// Runs the full offline pipeline for a newly recorded/imported meeting:
/// transcribe, summarize (only if transcription actually succeeded), then
/// index for retrieval (only if summarization actually succeeded) - the
/// same three-stage "run stage N, check the resulting status before
/// running stage N+1" shape `ProcessNewDocumentUseCase` uses
/// (lib/features/documents/process_new_document_use_case.dart), now
/// mirrored on the meeting side (M1.2/1C,
/// docs/v2/implementation/01-master-roadmap.md).
///
/// Recording and Import both need this exact same chain, so it's
/// centralized here instead of being duplicated in both controllers.
class ProcessNewMeetingUseCase {
  ProcessNewMeetingUseCase({
    required MeetingRepository meetingRepository,
    required TranscribeMeetingUseCase transcribeMeetingUseCase,
    required GenerateMeetingSummaryUseCase generateMeetingSummaryUseCase,
    required MeetingIndexer meetingIndexer,
  })  : _meetingRepository = meetingRepository,
        _transcribeMeetingUseCase = transcribeMeetingUseCase,
        _generateMeetingSummaryUseCase = generateMeetingSummaryUseCase,
        _meetingIndexer = meetingIndexer;

  final MeetingRepository _meetingRepository;
  final TranscribeMeetingUseCase _transcribeMeetingUseCase;
  final GenerateMeetingSummaryUseCase _generateMeetingSummaryUseCase;
  final MeetingIndexer _meetingIndexer;

  Future<void> call(int meetingId) async {
    await _transcribeMeetingUseCase(meetingId);

    final transcribed = await _meetingRepository.getById(meetingId);
    if (transcribed?.status != MeetingStatus.summarizing) return;

    await _generateMeetingSummaryUseCase(meetingId);

    final summarized = await _meetingRepository.getById(meetingId);
    if (summarized?.status != MeetingStatus.ready) return;

    await _meetingIndexer(meetingId);
  }
}
