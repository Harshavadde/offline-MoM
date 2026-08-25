import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/action_item.dart';
import '../../../../models/decision.dart';
import '../../../../models/summary.dart';
import '../../../../providers/app_providers.dart';

/// `autoDispose` (Phase 4B) on every provider in this file - see
/// `meetingByIdProvider`'s doc comment
/// (lib/features/meetings/presentation/providers/meeting_providers.dart) for
/// why every per-id detail-screen provider in this app uses it.
final summaryForMeetingProvider =
    FutureProvider.autoDispose.family<Summary?, int>((ref, meetingId) {
  return ref.watch(summaryRepositoryProvider).getForMeeting(meetingId);
});

final actionItemsForMeetingProvider =
    FutureProvider.autoDispose.family<List<ActionItem>, int>((ref, meetingId) {
  return ref.watch(actionItemRepositoryProvider).getForMeeting(meetingId);
});

final decisionsForMeetingProvider =
    FutureProvider.autoDispose.family<List<Decision>, int>((ref, meetingId) {
  return ref.watch(decisionRepositoryProvider).getForMeeting(meetingId);
});

final summaryForDocumentProvider =
    FutureProvider.autoDispose.family<Summary?, int>((ref, documentId) {
  return ref.watch(summaryRepositoryProvider).getForDocument(documentId);
});
