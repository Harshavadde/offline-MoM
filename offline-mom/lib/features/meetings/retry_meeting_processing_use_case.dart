import '../../models/meeting.dart';
import '../../repositories/meeting_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../repositories/transcript_repository.dart';
import '../ai_summary/generate_meeting_summary_use_case.dart';
import '../transcription/transcribe_meeting_use_case.dart';
import 'meeting_indexer.dart';

/// Retries a failed meeting from wherever the pipeline actually left off,
/// rather than always restarting from scratch: each stage is skipped if
/// its own output already exists, so a retry never redoes already
/// -successful work - mirrors `RetryDocumentProcessingUseCase`'s exact
/// reasoning (lib/features/documents/retry_document_processing_use_case.dart),
/// including its fix for the same latent bug: a meeting can now reach
/// `error` from a failed *indexing* step with a summary already
/// persisted, so this checks [SummaryRepository.getForMeeting] explicitly
/// before regenerating rather than always calling
/// [GenerateMeetingSummaryUseCase] unconditionally (which has no
/// existing-summary guard of its own, and would otherwise insert a
/// second, orphaned summary row on every indexing-only retry).
class RetryMeetingProcessingUseCase {
  RetryMeetingProcessingUseCase({
    required MeetingRepository meetingRepository,
    required TranscriptRepository transcriptRepository,
    required SummaryRepository summaryRepository,
    required TranscribeMeetingUseCase transcribeMeetingUseCase,
    required GenerateMeetingSummaryUseCase generateMeetingSummaryUseCase,
    required MeetingIndexer meetingIndexer,
  })  : _meetingRepository = meetingRepository,
        _transcriptRepository = transcriptRepository,
        _summaryRepository = summaryRepository,
        _transcribeMeetingUseCase = transcribeMeetingUseCase,
        _generateMeetingSummaryUseCase = generateMeetingSummaryUseCase,
        _meetingIndexer = meetingIndexer;

  final MeetingRepository _meetingRepository;
  final TranscriptRepository _transcriptRepository;
  final SummaryRepository _summaryRepository;
  final TranscribeMeetingUseCase _transcribeMeetingUseCase;
  final GenerateMeetingSummaryUseCase _generateMeetingSummaryUseCase;
  final MeetingIndexer _meetingIndexer;

  Future<void> call(int meetingId) async {
    final existingTranscript =
        await _transcriptRepository.getForMeeting(meetingId);

    if (existingTranscript == null) {
      await _transcribeMeetingUseCase(meetingId);
      final meeting = await _meetingRepository.getById(meetingId);
      if (meeting?.status != MeetingStatus.summarizing) return;
    }

    if (await _summaryRepository.getForMeeting(meetingId) == null) {
      await _generateMeetingSummaryUseCase(meetingId);
      final summarized = await _meetingRepository.getById(meetingId);
      if (summarized?.status != MeetingStatus.ready) return;
    }

    await _meetingIndexer(meetingId);
  }
}
