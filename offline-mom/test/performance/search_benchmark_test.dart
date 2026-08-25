// Benchmarks FTS5 search (docs/v2/13-search-architecture.md, migration v4)
// against a realistic-scale seeded dataset, and against the old
// leading-wildcard `LIKE` approach it replaced, so the improvement is
// measured rather than assumed. Scale target follows NFR-16
// (docs/v2/09-non-functional-requirements.md): "hundreds to low thousands"
// of meetings for this app's realistic personal/small-team use case.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/database/tables.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/repositories/content_search_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

const _meetingCount = 3000;

// A deliberately narrow vocabulary so most words repeat across many
// transcripts (realistic - meeting notes reuse business/project
// terminology constantly) while exactly one rare word ("zephyrion") is
// planted in a single transcript, giving both benchmarks a genuine
// needle-in-a-haystack query rather than only common-word queries that
// would match a large fraction of rows either way.
const _vocabulary = [
  'budget', 'roadmap', 'sprint', 'design', 'review', 'client', 'launch',
  'deadline', 'feature', 'bug', 'release', 'stakeholder', 'metric',
  'onboarding', 'pipeline', 'incident', 'proposal', 'contract', 'vendor',
  'migration', 'architecture', 'testing', 'deployment', 'analytics',
];

void main() {
  late Database db;
  late TranscriptRepository transcriptRepository;
  late ContentSearchRepository contentSearchRepository;
  late int needleMeetingId;

  setUpAll(() async {
    db = await openTestDatabase();
    transcriptRepository = SqfliteTranscriptRepository(db);
    contentSearchRepository = SqfliteContentSearchRepository(db);

    final random = Random(42); // deterministic - a reproducible benchmark
    String randomTranscript() {
      final words = List.generate(
        200,
        (_) => _vocabulary[random.nextInt(_vocabulary.length)],
      );
      return words.join(' ');
    }

    final batch = db.batch();
    for (var i = 0; i < _meetingCount; i++) {
      final now = DateTime(2026, 1, 1).add(Duration(minutes: i));
      final meeting = Meeting(
        id: null,
        title: 'Meeting #$i',
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert(MeetingsTable.name, meeting.toMap()..remove(MeetingsTable.id));
    }
    await batch.commit(noResult: true);

    final meetingIds = await db.query(MeetingsTable.name, columns: [MeetingsTable.id]);
    final ids = meetingIds.map((r) => r[MeetingsTable.id] as int).toList();

    final transcriptBatch = db.batch();
    for (final id in ids) {
      final transcript = Transcript(
        id: null,
        meetingId: id,
        language: 'en',
        fullText: randomTranscript(),
        segments: const [],
        createdAt: DateTime(2026, 1, 1),
      );
      transcriptBatch.insert(
        TranscriptsTable.name,
        transcript.toMap()..remove(TranscriptsTable.id),
      );
    }
    await transcriptBatch.commit(noResult: true);

    // Plant one rare, uniquely-identifiable meeting for the needle query.
    needleMeetingId = ids.first;
    await transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: needleMeetingId,
        language: 'en',
        fullText: 'This transcript uniquely mentions zephyrion once.',
        segments: const [],
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  });

  tearDownAll(() => db.close());

  test('FTS5 needle-in-a-haystack query is fast and correct', () async {
    final stopwatch = Stopwatch()..start();
    final results = (await contentSearchRepository.search('zephyrion')).meetingIds;
    stopwatch.stop();

    expect(results, {needleMeetingId});
    // Generous bound for a CI/test-machine sqflite_common_ffi build (not a
    // real device) - this is a regression guard against something becoming
    // accidentally O(n) again, not a tight production SLA.
    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(500),
      reason: 'FTS5 query took ${stopwatch.elapsedMilliseconds}ms across '
          '$_meetingCount transcripts - investigate before this regresses '
          'further.',
    );
    // ignore: avoid_print
    print(
      'FTS5 needle query across $_meetingCount transcripts: '
      '${stopwatch.elapsedMicroseconds / 1000}ms',
    );
  });

  test('FTS5 common-word query (most rows match) is still fast', () async {
    final stopwatch = Stopwatch()..start();
    final results = (await contentSearchRepository.search('budget')).meetingIds;
    stopwatch.stop();

    expect(results, isNotEmpty);
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
    // ignore: avoid_print
    print(
      'FTS5 common-word query across $_meetingCount transcripts: '
      '${stopwatch.elapsedMicroseconds / 1000}ms, ${results.length} matches',
    );
  });

  test('comparison: the old LIKE-scan approach for the same needle query',
      () async {
    final stopwatch = Stopwatch()..start();
    final rows = await db.query(
      TranscriptsTable.name,
      columns: [TranscriptsTable.meetingId],
      where: '${TranscriptsTable.fullText} LIKE ?',
      whereArgs: ['%zephyrion%'],
    );
    stopwatch.stop();

    expect(rows.map((r) => r[TranscriptsTable.meetingId]), [needleMeetingId]);
    // ignore: avoid_print
    print(
      'Old LIKE-scan needle query across $_meetingCount transcripts: '
      '${stopwatch.elapsedMicroseconds / 1000}ms',
    );
  });
}
