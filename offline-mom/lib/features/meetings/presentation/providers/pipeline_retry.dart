import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/app_providers.dart';
import '../../../ai_summary/presentation/providers/ai_summary_providers.dart';
import '../../../transcription/presentation/providers/transcript_providers.dart';
import 'meeting_providers.dart';

/// Shared by every screen with a "Retry" action on [AiPipelineFallback]
/// (Transcript, Summary, MoM, Action Items, Decisions): re-runs the
/// pipeline from wherever it left off, then refreshes every provider a
/// screen might be watching so the result appears immediately.
///
/// Lives in its own file (rather than inside one feature's providers file)
/// specifically because it depends on providers from three different
/// features - putting it inside any one of them would create an import
/// cycle the other two would have to route around.
Future<void> retryMeetingProcessing(WidgetRef ref, int meetingId) async {
  await ref.read(retryMeetingProcessingUseCaseProvider)(meetingId);
  ref.invalidate(meetingByIdProvider(meetingId));
  ref.invalidate(meetingListProvider);
  ref.invalidate(transcriptForMeetingProvider(meetingId));
  ref.invalidate(summaryForMeetingProvider(meetingId));
  ref.invalidate(actionItemsForMeetingProvider(meetingId));
  ref.invalidate(decisionsForMeetingProvider(meetingId));
}
