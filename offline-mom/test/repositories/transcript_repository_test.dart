import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late TranscriptRepository transcriptRepository;
  late int meetingId;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);

    final now = DateTime(2026, 1, 1);
    meetingId = await meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Weekly sync',
        source: MeetingSource.recorded,
        status: MeetingStatus.transcribing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() => db.close());

  Transcript buildTranscript(String fullText) {
    return Transcript(
      id: null,
      meetingId: meetingId,
      language: 'en',
      fullText: fullText,
      segments: [
        TranscriptSegment(startMs: 0, endMs: 1000, text: fullText),
      ],
      createdAt: DateTime(2026, 1, 1, 10),
    );
  }

  test('insert then getForMeeting round-trips segments', () async {
    await transcriptRepository.insert(
      buildTranscript('We discussed the Q1 roadmap.'),
    );

    final fetched = await transcriptRepository.getForMeeting(meetingId);

    expect(fetched, isNotNull);
    expect(fetched!.fullText, 'We discussed the Q1 roadmap.');
    expect(fetched.segments, hasLength(1));
    expect(fetched.segments.first.startMs, 0);
    expect(fetched.segments.first.endMs, 1000);
  });

  test('getForMeeting returns null when no transcript exists', () async {
    expect(await transcriptRepository.getForMeeting(meetingId), isNull);
  });

  test('findMeetingIdsByText matches on transcript content', () async {
    await transcriptRepository.insert(
      buildTranscript('The budget was approved for next quarter.'),
    );

    expect(
      await transcriptRepository.findMeetingIdsByText('budget'),
      [meetingId],
    );
    expect(
      await transcriptRepository.findMeetingIdsByText('nonexistent phrase'),
      isEmpty,
    );
  });

  test('deleting the meeting cascades to its transcript', () async {
    await transcriptRepository.insert(buildTranscript('Some content.'));
    await meetingRepository.delete(meetingId);

    expect(await transcriptRepository.getForMeeting(meetingId), isNull);
  });
}
