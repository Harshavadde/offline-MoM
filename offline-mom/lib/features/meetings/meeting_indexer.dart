import '../../core/knowledge/content_type.dart';
import '../../core/logging/app_logger.dart';
import '../../models/meeting.dart';
import '../../repositories/meeting_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../repositories/transcript_repository.dart';
import '../../services/retrieval/indexing_service.dart';

const _log = AppLogger('MeetingIndexer');

/// Drives a meeting through [MeetingStatus.indexing] - the background step
/// that chunks and embeds a meeting's transcript and summary via
/// [IndexingService] (services/retrieval/indexing_service.dart), per FR-40
/// and Milestone M1.2/1C (docs/v2/implementation/01-master-roadmap.md).
/// The direct meeting-side counterpart to `DocumentIndexer`
/// (features/documents/document_indexer.dart) - same shape, same
/// reasoning for why it runs as an explicit extra pipeline step rather
/// than being folded into [GenerateMeetingSummaryUseCase] (whose
/// already-shipped, already-tested contract stays untouched).
///
/// Indexes the transcript and the summary as two independent sources
/// (`ContentType.transcript`/`ContentType.summary`, each keyed by its own
/// row id as `sourceId` - see [IndexingService.indexContent]'s doc
/// comment, ADR-021), not one combined blob - so a future re-index of
/// just the summary (e.g. after `RetryMeetingProcessingUseCase`
/// regenerates it) never has to touch the transcript's chunks, and vice
/// versa. Notes are deliberately **not** indexed here - unlike the
/// transcript/summary, notes are added/edited/deleted interactively after
/// the pipeline finishes, not produced once by it; they're indexed
/// individually at the point they're mutated (see
/// `NotesController`, features/meetings/presentation/providers/notes_providers.dart).
class MeetingIndexer {
  MeetingIndexer({
    required MeetingRepository meetingRepository,
    required TranscriptRepository transcriptRepository,
    required SummaryRepository summaryRepository,
    required IndexingService indexingService,
  })  : _meetingRepository = meetingRepository,
        _transcriptRepository = transcriptRepository,
        _summaryRepository = summaryRepository,
        _indexingService = indexingService;

  final MeetingRepository _meetingRepository;
  final TranscriptRepository _transcriptRepository;
  final SummaryRepository _summaryRepository;
  final IndexingService _indexingService;

  Future<void> call(int meetingId) async {
    final meeting = await _meetingRepository.getById(meetingId);
    if (meeting == null) return;

    final transcript = await _transcriptRepository.getForMeeting(meetingId);
    final summary = await _summaryRepository.getForMeeting(meetingId);
    if (transcript == null && summary == null) return;

    await _meetingRepository.update(
      meeting.copyWith(status: MeetingStatus.indexing, updatedAt: DateTime.now()),
    );

    try {
      if (transcript != null && transcript.fullText.trim().isNotEmpty) {
        await _indexingService.indexContent(
          contentType: ContentType.transcript,
          sourceId: transcript.id!,
          meetingId: meetingId,
          text: transcript.fullText,
        );
      }

      if (summary != null) {
        await _indexingService.indexContent(
          contentType: ContentType.summary,
          sourceId: summary.id!,
          meetingId: meetingId,
          // Same three fields content_fts's summaries_fts_ai trigger
          // combines (migration v4) - keeps "what's searchable" and
          // "what's retrievable" consistent for the same source.
          text: '${summary.summaryText} ${summary.minutesOfMeeting} '
              '${summary.keyTopics.join(' ')}',
        );
      }

      await _meetingRepository.update(
        meeting.clearError().copyWith(
              status: MeetingStatus.ready,
              updatedAt: DateTime.now(),
            ),
      );
    } catch (e, stackTrace) {
      await _meetingRepository.update(
        meeting.copyWith(
          status: MeetingStatus.error,
          updatedAt: DateTime.now(),
          errorMessage: 'Indexing failed: $e',
        ),
      );
      _log.error('Indexing failed for meeting $meetingId', error: e, stackTrace: stackTrace);
    }
  }
}
