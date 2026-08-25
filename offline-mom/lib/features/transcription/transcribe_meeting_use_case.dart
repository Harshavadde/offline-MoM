import 'dart:async';
import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../models/meeting.dart';
import '../../models/transcript.dart';
import '../../repositories/meeting_repository.dart';
import '../../repositories/transcript_repository.dart';
import '../../services/ai/speech_to_text_engine.dart';

const _log = AppLogger('TranscribeMeetingUseCase');

/// Orchestrates turning a meeting's audio into a stored [Transcript]:
/// mark the meeting as transcribing, run the engine, persist the result,
/// and advance the meeting to its next pipeline stage (or mark it failed).
///
/// This crosses two repositories and a service, and has real branching
/// (success/failure) - exactly the kind of orchestration that earns a
/// dedicated use case rather than living inline in a ViewModel.
class TranscribeMeetingUseCase {
  TranscribeMeetingUseCase({
    required MeetingRepository meetingRepository,
    required TranscriptRepository transcriptRepository,
    required SpeechToTextEngine speechToTextEngine,
  })  : _meetingRepository = meetingRepository,
        _transcriptRepository = transcriptRepository,
        _speechToTextEngine = speechToTextEngine;

  final MeetingRepository _meetingRepository;
  final TranscriptRepository _transcriptRepository;
  final SpeechToTextEngine _speechToTextEngine;

  Future<void> call(int meetingId) async {
    final meeting = await _meetingRepository.getById(meetingId);
    if (meeting == null) return;

    // Real-device QA finding: a meeting can reach here with no audio path
    // at all (not merely a path whose file went missing, handled below) -
    // e.g. the app was killed mid-recording, before `stopRecording()` ever
    // wrote `audioFilePath` onto the row. Previously this silently
    // returned with no status change at all, leaving the meeting stuck at
    // `created`/`transcribing` forever with no diagnosable state and no
    // way for a Retry action to know anything was wrong. Reuses the same
    // `audioMissing` status the file-not-on-disk case below already uses -
    // both mean "there is no usable audio for this meeting" from the
    // pipeline's point of view.
    if (meeting.audioFilePath == null) {
      await _meetingRepository.update(
        meeting.copyWith(
          status: MeetingStatus.audioMissing,
          updatedAt: DateTime.now(),
          errorMessage: 'No audio was saved for this meeting - the app may '
              'have been closed before recording finished.',
        ),
      );
      return;
    }

    // R5 (V1's own disclosed risk, closed in Phase 0): the audio file this
    // meeting points at may have been deleted or moved outside the app
    // since the row was created. Checked once, up front - not something
    // ffmpeg/whisper.cpp would give a useful error message for, and
    // without this check the meeting would previously land in a generic
    // `error` state that gave no hint the audio itself was the problem.
    if (!await File(meeting.audioFilePath!).exists()) {
      await _meetingRepository.update(
        meeting.copyWith(
          status: MeetingStatus.audioMissing,
          updatedAt: DateTime.now(),
          errorMessage: 'The audio file for this meeting could not be '
              'found on this device - it may have been deleted or moved '
              'outside the app.',
        ),
      );
      return;
    }

    await _meetingRepository.update(
      meeting.clearError().copyWith(
            status: MeetingStatus.transcribing,
            updatedAt: DateTime.now(),
          ),
    );

    try {
      final result = await _speechToTextEngine.transcribe(
        meeting.audioFilePath!,
        onPreparingModel: () {
          // Fire-and-forget: this is a status update for the UI, not
          // something transcription needs to wait on.
          unawaited(
            _meetingRepository.update(
              meeting.copyWith(
                status: MeetingStatus.downloadingModel,
                updatedAt: DateTime.now(),
              ),
            ),
          );
        },
      );

      await _transcriptRepository.insert(
        Transcript(
          id: null,
          meetingId: meetingId,
          language: result.language,
          fullText: result.fullText,
          segments: result.segments,
          createdAt: DateTime.now(),
        ),
      );

      // Next pipeline stage is AI summarization (Phase 4) - the meeting
      // sits in `summarizing` until that phase picks it up.
      await _meetingRepository.update(
        meeting.clearError().copyWith(
              status: MeetingStatus.summarizing,
              updatedAt: DateTime.now(),
            ),
      );
    } catch (e, stackTrace) {
      await _meetingRepository.update(
        meeting.copyWith(
          status: MeetingStatus.error,
          updatedAt: DateTime.now(),
          errorMessage: 'Transcription failed: $e',
        ),
      );
      _log.error('Transcription failed for meeting $meetingId', error: e, stackTrace: stackTrace);
    }
  }
}
