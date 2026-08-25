import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../models/action_item.dart';
import '../../models/decision.dart';
import '../../models/meeting.dart';
import '../../models/summary.dart';
import '../../repositories/action_item_repository.dart';
import '../../repositories/decision_repository.dart';
import '../../repositories/meeting_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../repositories/transcript_repository.dart';
import '../../services/ai/chunked_summarization_service.dart';

const _log = AppLogger('GenerateMeetingSummaryUseCase');

/// Orchestrates generating a meeting's AI summary: read the transcript, run
/// the on-device LLM, persist the summary/action items/decisions, and mark
/// the meeting `ready` (or `error` on failure). Crosses four repositories
/// and a service, so - per the architecture notes - it earns living here
/// rather than as inline calls from a ViewModel.
///
/// The actual generation runs through [ChunkedSummarizationService] (M2.4)
/// rather than calling [LlmEngine].generateSummary directly - long
/// transcripts are chunked and hierarchically reduced instead of flatly
/// truncated, while every underlying call still goes through the same
/// shared [LlmRequestQueue] a direct call already did (ADR-008,
/// docs/v2/implementation/03-decisions.md): the shared engine can only run
/// one generation at a time, and the queue is what keeps a concurrent Ask
/// AI/chat question from failing outright while a summary is in flight (or
/// vice versa) instead of both being served correctly, one after the
/// other.
class GenerateMeetingSummaryUseCase {
  GenerateMeetingSummaryUseCase({
    required MeetingRepository meetingRepository,
    required TranscriptRepository transcriptRepository,
    required SummaryRepository summaryRepository,
    required ActionItemRepository actionItemRepository,
    required DecisionRepository decisionRepository,
    required ChunkedSummarizationService chunkedSummarizationService,
  })  : _meetingRepository = meetingRepository,
        _transcriptRepository = transcriptRepository,
        _summaryRepository = summaryRepository,
        _actionItemRepository = actionItemRepository,
        _decisionRepository = decisionRepository,
        _chunkedSummarizationService = chunkedSummarizationService;

  final MeetingRepository _meetingRepository;
  final TranscriptRepository _transcriptRepository;
  final SummaryRepository _summaryRepository;
  final ActionItemRepository _actionItemRepository;
  final DecisionRepository _decisionRepository;
  final ChunkedSummarizationService _chunkedSummarizationService;

  Future<void> call(int meetingId) async {
    final meeting = await _meetingRepository.getById(meetingId);
    if (meeting == null) return;

    final transcript = await _transcriptRepository.getForMeeting(meetingId);
    if (transcript == null || transcript.fullText.trim().isEmpty) return;

    try {
      final result = await _chunkedSummarizationService.summarize(
        transcript.fullText,
        onPreparingModel: () {
          // Fire-and-forget: this is a status update for the UI,
          // not something summary generation needs to wait on.
          unawaited(
            _meetingRepository.update(
              meeting.copyWith(
                status: MeetingStatus.downloadingSummaryModel,
                updatedAt: DateTime.now(),
              ),
            ),
          );
        },
      );
      final now = DateTime.now();

      await _summaryRepository.insert(
        Summary(
          id: null,
          meetingId: meetingId,
          summaryText: result.summaryText,
          minutesOfMeeting: result.minutesOfMeeting,
          keyTopics: result.keyTopics,
          modelUsed: result.modelUsed,
          generatedAt: now,
        ),
      );

      if (result.actionItems.isNotEmpty) {
        await _actionItemRepository.insertAll(
          result.actionItems
              .map(
                (item) => ActionItem(
                  id: null,
                  meetingId: meetingId,
                  description: item.task,
                  owner: item.owner,
                  dueDate: item.deadline,
                  isCompleted: false,
                  createdAt: now,
                ),
              )
              .toList(),
        );
      }

      if (result.decisions.isNotEmpty) {
        await _decisionRepository.insertAll(
          result.decisions
              .map(
                (description) => Decision(
                  id: null,
                  meetingId: meetingId,
                  description: description,
                  createdAt: now,
                ),
              )
              .toList(),
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
          errorMessage: 'AI summary failed: $e',
        ),
      );
      _log.error('Summary failed for meeting $meetingId', error: e, stackTrace: stackTrace);
    }
  }
}
