import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/audio_paths.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../models/meeting.dart';
import '../../../../models/recording_mark.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/audio/recorder_service.dart';
import '../../../../services/background/recording_foreground_service.dart';
import '../../../ai_summary/presentation/providers/ai_summary_providers.dart';
import '../../../meetings/presentation/providers/meeting_providers.dart';
import '../../../transcription/presentation/providers/transcript_providers.dart';

/// A meeting's recording marks, oldest first - used by the Transcript tab's
/// playback bar to show tappable jump points. `autoDispose` (Phase 4B) -
/// see `meetingByIdProvider`'s doc comment
/// (lib/features/meetings/presentation/providers/meeting_providers.dart) for
/// why every per-id detail-screen provider in this app uses it.
final recordingMarksForMeetingProvider =
    FutureProvider.autoDispose.family<List<RecordingMark>, int>((ref, meetingId) {
  return ref.watch(recordingMarkRepositoryProvider).getForMeeting(meetingId);
});

/// UI state for the record/recording flow. A sealed hierarchy so screens can
/// `switch` over it exhaustively instead of juggling booleans.
sealed class RecordingUiState {
  const RecordingUiState();
}

class RecordingIdle extends RecordingUiState {
  const RecordingIdle();
}

class RecordingInProgress extends RecordingUiState {
  const RecordingInProgress({
    required this.meetingId,
    required this.elapsed,
    required this.isPaused,
    required this.amplitude,
    this.amplitudeHistory = const [],
  });

  final int meetingId;
  final Duration elapsed;
  final bool isPaused;

  /// Normalized 0.0-1.0 level for a simple UI indicator (dBFS remapped).
  final double amplitude;

  /// The last ~8 seconds of [amplitude] samples, oldest first - real
  /// samples (not synthesized), used to draw an actual waveform rather
  /// than a single pulsing shape.
  final List<double> amplitudeHistory;

  RecordingInProgress copyWith({
    Duration? elapsed,
    bool? isPaused,
    double? amplitude,
    List<double>? amplitudeHistory,
  }) {
    return RecordingInProgress(
      meetingId: meetingId,
      elapsed: elapsed ?? this.elapsed,
      isPaused: isPaused ?? this.isPaused,
      amplitude: amplitude ?? this.amplitude,
      amplitudeHistory: amplitudeHistory ?? this.amplitudeHistory,
    );
  }
}

class RecordingFinished extends RecordingUiState {
  const RecordingFinished(this.meetingId);
  final int meetingId;
}

class RecordingFailed extends RecordingUiState {
  const RecordingFailed(this.message);
  final String message;
}

/// Orchestrates the recording lifecycle: mic permission, creating the
/// [Meeting] row, driving [RecorderService], and finalizing the meeting once
/// stopped. This is exactly the kind of multi-step orchestration that earns
/// living outside a trivial CRUD call, per the use-case guidance in the
/// architecture notes.
class RecordingController extends Notifier<RecordingUiState> {
  static const _maxAmplitudeHistory = 40;

  Timer? _ticker;
  StreamSubscription<RecordingAmplitude>? _amplitudeSub;
  final _stopwatch = Stopwatch();

  @override
  RecordingUiState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _amplitudeSub?.cancel();
    });
    return const RecordingIdle();
  }

  RecorderService get _recorder => ref.read(recorderServiceProvider);

  Future<void> startRecording(String title) async {
    final hasPermission = await _recorder.hasMicrophonePermission();
    if (!hasPermission) {
      // Phase 8B.4, Priority 6: explains *why* (so it's clear this is for
      // the recording itself, not something else) and *what to do about
      // it* (check device settings) - previously just stated the
      // requirement with no next step.
      state = const RecordingFailed(
        'OfflineMoMAI needs microphone access to record and transcribe '
        'this meeting. Check the microphone permission for this app in '
        'your device settings, then try again.',
      );
      return;
    }

    final now = DateTime.now();
    final meetingRepository = ref.read(meetingRepositoryProvider);
    final meetingId = await meetingRepository.insert(
          Meeting(
            id: null,
            title: title,
            source: MeetingSource.recorded,
            status: MeetingStatus.created,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final filePath = await newAudioFilePath();
    // Real-device QA finding: `_recorder.start()` was previously unguarded -
    // if it throws (mic held by another app, or the native recorder fails
    // to open its output file, e.g. under low storage), the exception
    // propagated straight out of this method: `state` was never set (the
    // caller's own error handling never runs), and the meeting row just
    // inserted above was left orphaned at `created` with no audio file
    // ever produced for it. Deleting it here is correct (not merely
    // convenient): unlike a recording that starts and is later
    // interrupted, this row never captured a single frame of real audio,
    // so there is nothing for a future Retry to act on.
    try {
      await _recorder.start(filePath);
    } catch (e) {
      await meetingRepository.delete(meetingId);
      state = RecordingFailed('Could not start recording. ${friendlyErrorMessage(e)}');
      return;
    }

    // Best-effort (see RecordingForegroundService's own doc comment): a
    // foreground service is what lets Android keep the microphone active
    // once the screen turns off, the device locks, or the app is
    // otherwise backgrounded - without it, recording could previously be
    // silently interrupted by the OS the moment the app left the
    // foreground. Never awaited into the critical start path - a real
    // recording must never be blocked or delayed by this.
    unawaited(RecordingForegroundService.requestPermission());
    unawaited(RecordingForegroundService.start(title));

    _stopwatch
      ..reset()
      ..start();
    state = RecordingInProgress(
      meetingId: meetingId,
      elapsed: Duration.zero,
      isPaused: false,
      amplitude: 0,
    );

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state;
      if (current is RecordingInProgress) {
        state = current.copyWith(elapsed: _stopwatch.elapsed);
      }
    });

    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder.amplitudeStream.listen((amplitude) {
      final current = state;
      if (current is RecordingInProgress) {
        // dBFS is typically -160 (silence) to 0 (loudest); clamp to a
        // practical noise floor so the indicator has visible range.
        final normalized = ((amplitude.current + 50) / 50).clamp(0.0, 1.0);
        final history = [...current.amplitudeHistory, normalized];
        if (history.length > _maxAmplitudeHistory) {
          history.removeAt(0);
        }
        state = current.copyWith(amplitude: normalized, amplitudeHistory: history);
      }
    });

    ref.invalidate(meetingListProvider);
  }

  /// Bookmarks the current moment in the recording (the "Mark" button).
  /// Returns the offset marked, so the screen can show a confirmation like
  /// "Marked at 05:32" without a second read of the controller's state.
  Future<Duration?> addMark() async {
    final current = state;
    if (current is! RecordingInProgress) return null;

    final offset = _stopwatch.elapsed;
    await ref.read(recordingMarkRepositoryProvider).insert(
          RecordingMark(
            id: null,
            meetingId: current.meetingId,
            offsetMs: offset.inMilliseconds,
            createdAt: DateTime.now(),
          ),
        );
    return offset;
  }

  Future<void> pauseRecording() async {
    final current = state;
    if (current is! RecordingInProgress || current.isPaused) return;
    await _recorder.pause();
    _stopwatch.stop();
    state = current.copyWith(isPaused: true);
  }

  Future<void> resumeRecording() async {
    final current = state;
    if (current is! RecordingInProgress || !current.isPaused) return;
    await _recorder.resume();
    _stopwatch.start();
    state = current.copyWith(isPaused: false);
  }

  Future<void> stopRecording() async {
    final current = state;
    if (current is! RecordingInProgress) return;

    final filePath = await _recorder.stop();
    _stopwatch.stop();
    _ticker?.cancel();
    await _amplitudeSub?.cancel();
    // Stops the foreground service (if this feature started one) - never
    // left running past the recording session it exists to protect, so it
    // never becomes an orphaned notification.
    unawaited(RecordingForegroundService.stop());

    final meetingRepo = ref.read(meetingRepositoryProvider);
    final meeting = await meetingRepo.getById(current.meetingId);
    if (meeting != null) {
      await meetingRepo.update(
        meeting.copyWith(
          audioFilePath: filePath,
          durationSeconds: current.elapsed.inSeconds,
          updatedAt: DateTime.now(),
        ),
      );
    }

    ref.invalidate(meetingListProvider);
    state = RecordingFinished(current.meetingId);

    // The full offline pipeline (transcribe, then summarize) runs in the
    // background - not awaited, so the user isn't stuck waiting on the
    // Recording screen for it to finish.
    final meetingId = current.meetingId;
    unawaited(
      ref.read(processNewMeetingUseCaseProvider)(meetingId).then((_) {
        ref.invalidate(meetingByIdProvider(meetingId));
        ref.invalidate(meetingListProvider);
        ref.invalidate(transcriptForMeetingProvider(meetingId));
        ref.invalidate(summaryForMeetingProvider(meetingId));
        ref.invalidate(actionItemsForMeetingProvider(meetingId));
        ref.invalidate(decisionsForMeetingProvider(meetingId));
      }),
    );
  }

  void reset() {
    _ticker?.cancel();
    _amplitudeSub?.cancel();
    _stopwatch.reset();
    // A discarded/failed recording never got a proper stopRecording() call
    // to release the foreground service (if one was started) - stop it
    // here too, so it's never left running past whatever session it was
    // protecting.
    unawaited(RecordingForegroundService.stop());
    state = const RecordingIdle();
  }
}

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingUiState>(
  RecordingController.new,
);
