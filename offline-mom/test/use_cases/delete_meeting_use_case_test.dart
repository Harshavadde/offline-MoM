import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/meetings/delete_meeting_use_case.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/retrieval/knowledge_chunk_filter.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

/// Counts [invalidateCache] calls without needing a real corpus - every
/// other method is unused by [DeleteMeetingUseCase] and just throws if
/// ever called, so a test relying on one would fail loudly, not silently.
class _SpyVectorStore implements VectorStore {
  int invalidateCacheCallCount = 0;

  @override
  void invalidateCache() => invalidateCacheCallCount++;

  @override
  Future<void> add(KnowledgeChunk chunk) => throw UnimplementedError();

  @override
  Future<void> addAll(List<KnowledgeChunk> chunks) => throw UnimplementedError();

  @override
  Future<List<KnowledgeChunk>> similaritySearch(
    List<double> queryEmbedding, {
    required int k,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  }) =>
      throw UnimplementedError();
}

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late _SpyVectorStore vectorStore;
  late DeleteMeetingUseCase useCase;
  late Directory tempDir;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    vectorStore = _SpyVectorStore();
    useCase = DeleteMeetingUseCase(
      meetingRepository: meetingRepository,
      vectorStore: vectorStore,
    );
    tempDir = await Directory.systemTemp.createTemp('delete_meeting_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> insertMeeting({String? audioFilePath}) {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'To be deleted',
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
        audioFilePath: audioFilePath,
      ),
    );
  }

  test('deletes the meeting row and its audio file', () async {
    final audioFile = File('${tempDir.path}/meeting.m4a');
    await audioFile.writeAsBytes([1, 2, 3]);

    final meetingId = await insertMeeting(audioFilePath: audioFile.path);

    await useCase(meetingId);

    expect(await meetingRepository.getById(meetingId), isNull);
    expect(await audioFile.exists(), isFalse);
  });

  test('deleting a meeting with no audio file does not throw', () async {
    final meetingId = await insertMeeting(audioFilePath: null);

    await useCase(meetingId);

    expect(await meetingRepository.getById(meetingId), isNull);
  });

  test('deleting a meeting whose audio file is already gone does not throw',
      () async {
    final missingPath = '${tempDir.path}/already_gone.m4a';
    final meetingId = await insertMeeting(audioFilePath: missingPath);

    await useCase(meetingId);

    expect(await meetingRepository.getById(meetingId), isNull);
  });

  test('deleting an unknown meeting id does not throw', () async {
    await useCase(9999);
  });

  test(
      'invalidates the vector store cache on a real delete, so a deleted '
      "meeting's chunks can't keep surfacing in retrieval/search for the "
      'rest of the app session (Phase 4B)', () async {
    final meetingId = await insertMeeting();

    await useCase(meetingId);

    expect(vectorStore.invalidateCacheCallCount, 1);
  });

  test('does not invalidate the vector store cache for an unknown meeting id '
      '- nothing was actually deleted', () async {
    await useCase(9999);

    expect(vectorStore.invalidateCacheCallCount, 0);
  });
}
