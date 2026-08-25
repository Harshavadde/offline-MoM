import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/decision.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/decision_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late DecisionRepository decisionRepository;
  late int meetingId;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    decisionRepository = SqfliteDecisionRepository(db);

    final now = DateTime(2026, 1, 1);
    meetingId = await meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Board meeting',
        source: MeetingSource.recorded,
        status: MeetingStatus.summarizing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() => db.close());

  Decision buildDecision(String description) {
    return Decision(
      id: null,
      meetingId: meetingId,
      description: description,
      createdAt: DateTime(2026, 1, 1, 10),
    );
  }

  test('insertAll then getForMeeting returns decisions in creation order', () async {
    await decisionRepository.insertAll([
      buildDecision('Approved the new budget'),
      buildDecision('Postponed the launch to Q3'),
    ]);

    final decisions = await decisionRepository.getForMeeting(meetingId);

    expect(decisions.map((d) => d.description).toList(),
        ['Approved the new budget', 'Postponed the launch to Q3']);
  });

  test('findMeetingIdsByDescription matches on decision text', () async {
    await decisionRepository.insertAll([buildDecision('Approved the merger')]);

    expect(
      await decisionRepository.findMeetingIdsByDescription('merger'),
      [meetingId],
    );
    expect(
      await decisionRepository.findMeetingIdsByDescription('unrelated'),
      isEmpty,
    );
  });

  test('deleting the meeting cascades to its decisions', () async {
    await decisionRepository.insertAll([buildDecision('Some decision')]);
    await meetingRepository.delete(meetingId);

    expect(await decisionRepository.getForMeeting(meetingId), isEmpty);
  });
}
