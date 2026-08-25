import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../models/meeting.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/audio/audio_import_service.dart';
import '../../../ai_summary/presentation/providers/ai_summary_providers.dart';
import '../../../meetings/presentation/providers/meeting_providers.dart';
import '../../../transcription/presentation/providers/transcript_providers.dart';

sealed class ImportUiState {
  const ImportUiState();
}

class ImportIdle extends ImportUiState {
  const ImportIdle();
}

/// Covers both "waiting on the file picker" and "extracting/copying audio" -
/// the screen doesn't need to distinguish them, both just show a spinner.
class ImportProcessing extends ImportUiState {
  const ImportProcessing();
}

class ImportSucceeded extends ImportUiState {
  const ImportSucceeded(this.meetingId);
  final int meetingId;
}

class ImportFailed extends ImportUiState {
  const ImportFailed(this.message);
  final String message;
}

/// Orchestrates importing a meeting: pick a file, extract/copy its audio,
/// create the Meeting row. Real multi-step orchestration, so - per the
/// architecture notes - it earns living here rather than as inline
/// repository calls from the screen.
class ImportController extends Notifier<ImportUiState> {
  @override
  ImportUiState build() => const ImportIdle();

  Future<void> importFile() async {
    // Phase 8C production-hardening finding: unlike `RecordingController
    // .startRecording`/`ChatController.sendMessage`/`ModelDownloadController
    // .start` (all guarded against a rapid double-tap re-entering an
    // in-flight async operation), this had no such guard - only the
    // screen's `isProcessing`-derived `onTap: null` disabling it, which has
    // a real (if narrow) staleness window: a second tap dispatched before
    // the widget rebuilds reflecting the new state still invokes this
    // stale closure. Without this guard, that could open the system file
    // picker twice concurrently for one tap sequence.
    if (state is ImportProcessing) return;
    state = const ImportProcessing();
    final importService = ref.read(audioImportServiceProvider);

    final pickedPath = await importService.pickFile();
    if (pickedPath == null) {
      state = const ImportIdle();
      return;
    }

    try {
      final audioPath = await importService.prepareAudioFile(pickedPath);
      final now = DateTime.now();
      final meetingId = await ref.read(meetingRepositoryProvider).insert(
            Meeting(
              id: null,
              title: p.basenameWithoutExtension(pickedPath),
              source: MeetingSource.imported,
              status: MeetingStatus.created,
              createdAt: now,
              updatedAt: now,
              audioFilePath: audioPath,
            ),
          );
      ref.invalidate(meetingListProvider);
      state = ImportSucceeded(meetingId);

      // The full offline pipeline (transcribe, then summarize) runs in the
      // background - not awaited, so the user isn't stuck waiting on the
      // Import screen for it to finish.
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
    } on AudioImportException catch (e) {
      state = ImportFailed(e.message);
    }
  }

  void reset() => state = const ImportIdle();
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportUiState>(ImportController.new);
