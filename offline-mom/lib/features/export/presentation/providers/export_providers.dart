import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/app_providers.dart';
import '../../../../services/export/pdf_export_service.dart';

/// Gathers everything a meeting's PDF report needs in one place, so the
/// PDF builder itself stays a pure function of data. `autoDispose`
/// (Phase 4B) - see `meetingByIdProvider`'s doc comment
/// (lib/features/meetings/presentation/providers/meeting_providers.dart) for
/// why every per-id detail-screen provider in this app uses it; this one in
/// particular is read exactly once per export and has no reason to stay
/// cached after `ExportScreen` closes.
final meetingReportDataProvider =
    FutureProvider.autoDispose.family<MeetingReportData, int>((ref, meetingId) async {
  final meeting = await ref.watch(meetingRepositoryProvider).getById(meetingId);
  if (meeting == null) {
    throw StateError('Meeting $meetingId not found');
  }

  final transcript =
      await ref.watch(transcriptRepositoryProvider).getForMeeting(meetingId);
  final summary =
      await ref.watch(summaryRepositoryProvider).getForMeeting(meetingId);
  final actionItems =
      await ref.watch(actionItemRepositoryProvider).getForMeeting(meetingId);
  final decisions =
      await ref.watch(decisionRepositoryProvider).getForMeeting(meetingId);

  return MeetingReportData(
    meeting: meeting,
    transcript: transcript,
    summary: summary,
    actionItems: actionItems,
    decisions: decisions,
  );
});
