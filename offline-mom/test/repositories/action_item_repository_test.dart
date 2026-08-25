import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/action_item.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/action_item_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late ActionItemRepository actionItemRepository;
  late int meetingId;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    actionItemRepository = SqfliteActionItemRepository(db);

    final now = DateTime(2026, 1, 1);
    meetingId = await meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Planning',
        source: MeetingSource.imported,
        status: MeetingStatus.summarizing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() => db.close());

  ActionItem buildItem(String description, {bool isCompleted = false}) {
    return ActionItem(
      id: null,
      meetingId: meetingId,
      description: description,
      isCompleted: isCompleted,
      createdAt: DateTime(2026, 1, 1, 10),
    );
  }

  test('insertAll then getForMeeting returns items in creation order', () async {
    await actionItemRepository.insertAll([
      buildItem('Send follow-up email'),
      buildItem('Book the venue'),
    ]);

    final items = await actionItemRepository.getForMeeting(meetingId);

    expect(items.map((i) => i.description).toList(),
        ['Send follow-up email', 'Book the venue']);
    expect(items.every((i) => !i.isCompleted), isTrue);
  });

  test('setCompleted toggles only the targeted item', () async {
    await actionItemRepository.insertAll([
      buildItem('First task'),
      buildItem('Second task'),
    ]);
    final items = await actionItemRepository.getForMeeting(meetingId);

    await actionItemRepository.setCompleted(items.first.id!, true);
    final updated = await actionItemRepository.getForMeeting(meetingId);

    expect(updated.first.isCompleted, isTrue);
    expect(updated.last.isCompleted, isFalse);
  });

  test('findMeetingIdsByDescription matches on action item text', () async {
    await actionItemRepository.insertAll([buildItem('Renew the office lease')]);

    expect(
      await actionItemRepository.findMeetingIdsByDescription('lease'),
      [meetingId],
    );
    expect(
      await actionItemRepository.findMeetingIdsByDescription('unrelated'),
      isEmpty,
    );
  });

  test('deleting the meeting cascades to its action items', () async {
    await actionItemRepository.insertAll([buildItem('Task to be cascaded')]);
    await meetingRepository.delete(meetingId);

    expect(await actionItemRepository.getForMeeting(meetingId), isEmpty);
  });
}
