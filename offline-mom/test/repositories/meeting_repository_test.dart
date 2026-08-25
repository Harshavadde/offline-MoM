import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteMeetingRepository(db);
  });

  tearDown(() => db.close());

  Meeting buildMeeting({
    String title = 'Sprint planning',
    MeetingSource source = MeetingSource.recorded,
    MeetingStatus status = MeetingStatus.created,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime(2026, 1, 1, 10);
    return Meeting(
      id: null,
      title: title,
      source: source,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('insert then getById returns the same meeting', () async {
    final id = await repository.insert(buildMeeting(title: 'Standup'));
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.title, 'Standup');
    expect(fetched.source, MeetingSource.recorded);
    expect(fetched.status, MeetingStatus.created);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(999), isNull);
  });

  test('getAll orders by createdAt descending', () async {
    await repository.insert(
      buildMeeting(title: 'Oldest', createdAt: DateTime(2026, 1, 1)),
    );
    await repository.insert(
      buildMeeting(title: 'Newest', createdAt: DateTime(2026, 1, 3)),
    );
    await repository.insert(
      buildMeeting(title: 'Middle', createdAt: DateTime(2026, 1, 2)),
    );

    final all = await repository.getAll();

    expect(all.map((m) => m.title).toList(), ['Newest', 'Middle', 'Oldest']);
  });

  test('update persists changed fields', () async {
    final id = await repository.insert(buildMeeting(title: 'Draft title'));
    final original = (await repository.getById(id))!;

    await repository.update(
      original.copyWith(title: 'Final title', status: MeetingStatus.ready),
    );
    final updated = await repository.getById(id);

    expect(updated!.title, 'Final title');
    expect(updated.status, MeetingStatus.ready);
  });

  test('delete removes the meeting', () async {
    final id = await repository.insert(buildMeeting());
    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('findIdsByTitle matches case-insensitively on substrings', () async {
    final matchId =
        await repository.insert(buildMeeting(title: 'Quarterly Budget Review'));
    await repository.insert(buildMeeting(title: 'Design sync'));

    final ids = await repository.findIdsByTitle('budget');

    expect(ids, [matchId]);
  });

  test('findIdsByDateRange only matches meetings within the range', () async {
    final inRangeId = await repository.insert(
      buildMeeting(createdAt: DateTime(2026, 3, 10, 9)),
    );
    await repository.insert(buildMeeting(createdAt: DateTime(2026, 3, 12)));

    final ids = await repository.findIdsByDateRange(
      DateTime(2026, 3, 10),
      DateTime(2026, 3, 11),
    );

    expect(ids, [inRangeId]);
  });

  test('getByIds returns matching meetings and ignores an empty set', () async {
    final id1 = await repository.insert(buildMeeting(title: 'One'));
    final id2 = await repository.insert(buildMeeting(title: 'Two'));
    await repository.insert(buildMeeting(title: 'Three'));

    final meetings = await repository.getByIds({id1, id2});

    expect(meetings.map((m) => m.title).toSet(), {'One', 'Two'});
    expect(await repository.getByIds(const []), isEmpty);
  });
}
