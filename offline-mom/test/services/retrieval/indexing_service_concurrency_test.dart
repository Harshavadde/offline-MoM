// Concurrency coverage for the Phase 1C TESTS requirement: concurrent
// indexContent calls for different (contentType, sourceId) pairs sharing
// one owner must not interfere with each other - no source's chunks should
// be lost, duplicated, or attributed to the wrong source, even when the
// calls race.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;
  late DefaultIndexingService indexingService;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
    indexingService = DefaultIndexingService(
      chunkingService: const DefaultChunkingService(),
      embeddingEngine: FakeEmbeddingEngine(),
      vectorStore: BruteForceVectorStore(
        knowledgeChunkRepository: knowledgeChunkRepository,
      ),
      knowledgeChunkRepository: knowledgeChunkRepository,
    );
  });

  tearDown(() => db.close());

  Future<int> insertMeeting() {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Standup',
        source: MeetingSource.recorded,
        status: MeetingStatus.indexing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  // Regression test for a real bug caught during Phase 3A's own
  // duplicate-indexing-guard implementation (ADR-029,
  // docs/v2/implementation/03-decisions.md): the guard's first version
  // tracked in-flight calls in a `Map<String, Future<void>>` and cleaned up
  // via `.whenComplete(() => _inFlight.remove(key))` - an arrow-function
  // callback, whose *return value* (`Map.remove`'s return is the removed
  // *value*, i.e. that very `Future<void>`) `whenComplete` then treated as
  // something to await, deadlocking the future on itself. Every earlier
  // await inside `indexContent` completed normally; only the single call's
  // *own* returned Future never resolved - completely invisible without a
  // tightly bounded timeout like this one (the default 30s per-test
  // timeout made it look like a generic hang, not a specific regression).
  // A short, explicit timeout here means a future reintroduction of this
  // bug class fails fast and points straight at this file, not a vague
  // 30-second stall anywhere in the suite.
  test('a single, non-concurrent indexContent call completes well within a '
      'tight explicit timeout (guards against a self-referential '
      'Future.whenComplete deadlock)', () async {
    final meetingId = await insertMeeting();

    await indexingService.indexContent(
      contentType: ContentType.transcript,
      sourceId: 1,
      meetingId: meetingId,
      text: 'A single, ordinary indexing call with no concurrency at all.',
    );

    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(chunks, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('indexing a transcript, a summary, and several notes concurrently '
      'under the same meeting produces every source\'s chunks with none '
      'lost or cross-attributed', () async {
    final meetingId = await insertMeeting();

    await Future.wait([
      indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 1,
        meetingId: meetingId,
        text: 'Transcript discusses the annual budget in great detail today.',
      ),
      indexingService.indexContent(
        contentType: ContentType.summary,
        sourceId: 2,
        meetingId: meetingId,
        text: 'Summary of the annual budget discussion and next steps.',
      ),
      indexingService.indexContent(
        contentType: ContentType.note,
        sourceId: 3,
        meetingId: meetingId,
        text: 'Note one about follow-up items for the vendor contract.',
      ),
      indexingService.indexContent(
        contentType: ContentType.note,
        sourceId: 4,
        meetingId: meetingId,
        text: 'Note two about a completely different topic entirely.',
      ),
    ]);

    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    final bySource = <int, List<ContentType>>{};
    for (final chunk in chunks) {
      bySource.putIfAbsent(chunk.sourceId, () => []).add(chunk.contentType);
    }

    expect(bySource.keys.toSet(), {1, 2, 3, 4});
    expect(bySource[1]!.every((t) => t == ContentType.transcript), isTrue);
    expect(bySource[2]!.every((t) => t == ContentType.summary), isTrue);
    expect(bySource[3]!.every((t) => t == ContentType.note), isTrue);
    expect(bySource[4]!.every((t) => t == ContentType.note), isTrue);
  });

  test('concurrently re-indexing two different sources under the same '
      'meeting never leaves one source with the other\'s chunk count',
      () async {
    final meetingId = await insertMeeting();

    // Seed both sources once, sequentially, so we know the baseline shape.
    await indexingService.indexContent(
      contentType: ContentType.note,
      sourceId: 10,
      meetingId: meetingId,
      text: 'Original note ten content, moderately long for chunking.',
    );
    await indexingService.indexContent(
      contentType: ContentType.note,
      sourceId: 11,
      meetingId: meetingId,
      text: 'Original note eleven content, also moderately long.',
    );

    // Re-index both concurrently with new content.
    await Future.wait([
      indexingService.indexContent(
        contentType: ContentType.note,
        sourceId: 10,
        meetingId: meetingId,
        text: 'Updated note ten content, now about something else.',
      ),
      indexingService.indexContent(
        contentType: ContentType.note,
        sourceId: 11,
        meetingId: meetingId,
        text: 'Updated note eleven content, also now different.',
      ),
    ]);

    final chunksForTen = await knowledgeChunkRepository.getForMeeting(meetingId);
    final ten = chunksForTen.where((c) => c.sourceId == 10).toList();
    final eleven = chunksForTen.where((c) => c.sourceId == 11).toList();

    expect(ten, isNotEmpty);
    expect(eleven, isNotEmpty);
    expect(ten.every((c) => c.chunkText.contains('Updated note ten')), isTrue);
    expect(eleven.every((c) => c.chunkText.contains('Updated note eleven')), isTrue);
  });

  test('concurrent indexing across two different meetings does not '
      'cross-contaminate either meeting\'s chunks', () async {
    final meetingA = await insertMeeting();
    final meetingB = await insertMeeting();

    await Future.wait([
      indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 1,
        meetingId: meetingA,
        text: 'Meeting A transcript content about quarterly planning.',
      ),
      indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 2,
        meetingId: meetingB,
        text: 'Meeting B transcript content about staffing changes.',
      ),
    ]);

    final chunksA = await knowledgeChunkRepository.getForMeeting(meetingA);
    final chunksB = await knowledgeChunkRepository.getForMeeting(meetingB);

    expect(chunksA, isNotEmpty);
    expect(chunksB, isNotEmpty);
    expect(chunksA.every((c) => c.meetingId == meetingA), isTrue);
    expect(chunksB.every((c) => c.meetingId == meetingB), isTrue);
  });

  // Phase 3A: duplicate-indexing guard - two callers racing to index the
  // *same* (contentType, sourceId), unlike every case above (which already
  // covered different sources racing safely). Before this guard, both
  // calls would run the delete-then-insert sequence concurrently and could
  // each successfully insert their own chunk set, leaving duplicates.
  test('concurrent indexContent calls for the exact same (contentType, '
      'sourceId) coalesce into one indexed result, never duplicating '
      'chunks', () async {
    final meetingId = await insertMeeting();

    await Future.wait([
      indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 99,
        meetingId: meetingId,
        text: 'Racing call number one about the quarterly roadmap.',
      ),
      indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 99,
        meetingId: meetingId,
        text: 'Racing call number one about the quarterly roadmap.',
      ),
      indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 99,
        meetingId: meetingId,
        text: 'Racing call number one about the quarterly roadmap.',
      ),
    ]);

    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    final forSource99 = chunks.where((c) => c.sourceId == 99).toList();

    // A single short text chunks to exactly one row - three coalesced
    // calls must still leave exactly one row, not three.
    expect(forSource99, hasLength(1));
  });

  test('a later, non-overlapping indexContent call for the same source '
      'still runs (coalescing only merges genuinely concurrent calls, not '
      'every future call)', () async {
    final meetingId = await insertMeeting();

    await indexingService.indexContent(
      contentType: ContentType.note,
      sourceId: 42,
      meetingId: meetingId,
      text: 'Original note forty-two content.',
    );
    await indexingService.indexContent(
      contentType: ContentType.note,
      sourceId: 42,
      meetingId: meetingId,
      text: 'Edited note forty-two content, now different.',
    );

    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    final forSource42 = chunks.where((c) => c.sourceId == 42).toList();

    expect(forSource42, hasLength(1));
    expect(forSource42.single.chunkText, contains('Edited note forty-two'));
  });

  // Phase 4B: this boundary check used to be an `assert`, stripped
  // entirely from `flutter build --release` - a caller passing a
  // malformed owner reference would have silently indexed a chunk with
  // the wrong (or no) owner in release instead of failing loudly. Now a
  // real, always-enforced `ArgumentError`.
  test('indexContent throws when neither meetingId nor documentId is set - '
      'in every build mode, not just debug', () async {
    expect(
      () => indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 1,
        text: 'orphaned content with no owner',
      ),
      throwsArgumentError,
    );
  });

  test('indexContent throws when both meetingId and documentId are set - in '
      'every build mode, not just debug', () async {
    final meetingId = await insertMeeting();
    expect(
      () => indexingService.indexContent(
        contentType: ContentType.transcript,
        sourceId: 1,
        meetingId: meetingId,
        documentId: 1,
        text: 'ambiguously-owned content',
      ),
      throwsArgumentError,
    );
  });
}
