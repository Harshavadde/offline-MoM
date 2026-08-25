// Tests MeetingListTile's status label (R-6) - previously rendered as
// "Transcribing 45%" for the entire, potentially many-minute duration of
// the transcribing stage (a fixed stage-position marker misrepresented as
// a real, moving completion percentage - Whisper's own native transcribe
// call has no fine-grained progress callback at all). A regression test
// for the specific label text, not the underlying pipeline (already
// covered by transcribe_meeting_use_case_test.dart/retry_meeting_
// processing_use_case_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/meetings/presentation/widgets/meeting_list_tile.dart';
import 'package:offline_mom/models/meeting.dart';

Meeting _meeting(MeetingStatus status) {
  final now = DateTime(2026, 1, 1);
  return Meeting(
    id: 1,
    title: 'Standup',
    source: MeetingSource.recorded,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Future<void> pump(WidgetTester tester, Meeting meeting) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MeetingListTile(meeting: meeting)),
      ),
    );
  }

  testWidgets('transcribing status never shows a percentage - no fixed number that could look stuck', (tester) async {
    await pump(tester, _meeting(MeetingStatus.transcribing));

    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Transcribing…'), findsOneWidget);
  });

  testWidgets('every in-progress pipeline stage shows an honest label with no percentage', (tester) async {
    for (final status in [
      MeetingStatus.created,
      MeetingStatus.downloadingModel,
      MeetingStatus.transcribing,
      MeetingStatus.downloadingSummaryModel,
      MeetingStatus.summarizing,
      MeetingStatus.indexing,
    ]) {
      await pump(tester, _meeting(status));
      expect(find.textContaining('%'), findsNothing, reason: status.name);
    }
  });

  testWidgets('a ready meeting shows a plain "Ready" label, still no percentage', (tester) async {
    await pump(tester, _meeting(MeetingStatus.ready));

    expect(find.text('Ready'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
