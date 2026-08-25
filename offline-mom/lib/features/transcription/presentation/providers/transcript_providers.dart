import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/transcript.dart';
import '../../../../providers/app_providers.dart';

/// `autoDispose` (Phase 4B) - see `meetingByIdProvider`'s doc comment
/// (lib/features/meetings/presentation/providers/meeting_providers.dart) for
/// why every per-id detail-screen provider in this app uses it.
final transcriptForMeetingProvider =
    FutureProvider.autoDispose.family<Transcript?, int>((ref, meetingId) {
  return ref.watch(transcriptRepositoryProvider).getForMeeting(meetingId);
});
