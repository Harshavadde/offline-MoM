// Tests NotesController (features/meetings/presentation/providers/notes_providers.dart)
// through a ProviderContainer with only the two leaf providers it actually
// reads - noteRepositoryProvider and indexingServiceProvider - overridden to
// point at a throwaway in-memory database and a FakeEmbeddingEngine. This
// avoids needing appDatabaseProvider/AppDatabase (private constructor, real
// file IO) or the real llamadart-backed embeddingEngineProvider, neither of
// which can run in a test environment.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/features/meetings/presentation/providers/notes_providers.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/note_repository.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';
import 'package:offline_mom/services/retrieval/indexing_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

/// Wraps a real [IndexingService] but always throws from
/// [removeIndexForSource] - lets a test force the *deletion* side of the
/// index-sync contract to fail, which a failing [FakeEmbeddingEngine]
/// cannot do since [DefaultIndexingService.removeIndexForSource] never
/// calls the embedding engine.
class _RemoveAlwaysThrowsIndexingService implements IndexingService {
  _RemoveAlwaysThrowsIndexingService(this._delegate);

  final IndexingService _delegate;

  @override
  Future<void> indexContent({
    required ContentType contentType,
    required int sourceId,
    int? meetingId,
    int? documentId,
    required String text,
  }) {
    return _delegate.indexContent(
      contentType: contentType,
      sourceId: sourceId,
      meetingId: meetingId,
      documentId: documentId,
      text: text,
    );
  }

  @override
  Future<void> removeIndexForSource(ContentType contentType, int sourceId) {
    throw Exception('remove failed');
  }
}

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late NoteRepository noteRepository;
  late KnowledgeChunkRepository knowledgeChunkRepository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    noteRepository = SqfliteNoteRepository(db);
    knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  ProviderContainer buildContainer({FakeEmbeddingEngine? embeddingEngine}) {
    return ProviderContainer(
      overrides: [
        noteRepositoryProvider.overrideWithValue(noteRepository),
        indexingServiceProvider.overrideWithValue(
          DefaultIndexingService(
            chunkingService: const DefaultChunkingService(),
            embeddingEngine: embeddingEngine ?? FakeEmbeddingEngine(),
            vectorStore: BruteForceVectorStore(
              knowledgeChunkRepository: knowledgeChunkRepository,
            ),
            knowledgeChunkRepository: knowledgeChunkRepository,
          ),
        ),
      ],
    );
  }

  Future<int> insertMeeting() {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Standup',
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('add() persists the note and indexes it under ContentType.note',
      () async {
    container = buildContainer();
    final meetingId = await insertMeeting();

    await container.read(notesControllerProvider).add(meetingId, 'Follow up with vendor.');

    final notes = await noteRepository.getForMeeting(meetingId);
    expect(notes, hasLength(1));

    final chunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(chunks, isNotEmpty);
    expect(chunks.every((c) => c.contentType == ContentType.note), isTrue);
    expect(chunks.every((c) => c.sourceId == notes.single.id), isTrue);
  });

  test('add() with blank content persists the note but does not index it',
      () async {
    container = buildContainer();
    final meetingId = await insertMeeting();

    await container.read(notesControllerProvider).add(meetingId, '   ');

    expect(await noteRepository.getForMeeting(meetingId), hasLength(1));
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
  });

  test('edit() re-indexes the note, replacing rather than duplicating its '
      'chunks', () async {
    container = buildContainer();
    final meetingId = await insertMeeting();
    final controller = container.read(notesControllerProvider);
    await controller.add(meetingId, 'Original content.');
    final note = (await noteRepository.getForMeeting(meetingId)).single;

    await controller.edit(note, 'Updated content that is different.');

    final chunksAfterEdit = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(chunksAfterEdit, isNotEmpty);
    expect(chunksAfterEdit.every((c) => c.sourceId == note.id), isTrue);

    final updatedNote = (await noteRepository.getForMeeting(meetingId)).single;
    expect(updatedNote.content, 'Updated content that is different.');

    // Re-indexing must not leave the old chunks behind alongside the new
    // ones - a second call with unchanged content should produce the same
    // chunk count, not double it.
    await controller.edit(updatedNote, 'Updated content that is different.');
    final chunksAfterSecondEdit = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(chunksAfterSecondEdit.length, chunksAfterEdit.length);
  });

  test('delete() removes the note and its indexed chunks', () async {
    container = buildContainer();
    final meetingId = await insertMeeting();
    final controller = container.read(notesControllerProvider);
    await controller.add(meetingId, 'Note to be deleted.');
    final note = (await noteRepository.getForMeeting(meetingId)).single;
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isNotEmpty);

    await controller.delete(note);

    expect(await noteRepository.getForMeeting(meetingId), isEmpty);
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
  });

  test('delete() does not remove chunks belonging to a sibling note under '
      'the same meeting', () async {
    container = buildContainer();
    final meetingId = await insertMeeting();
    final controller = container.read(notesControllerProvider);
    await controller.add(meetingId, 'First note content.');
    await controller.add(meetingId, 'Second note content.');
    final notes = await noteRepository.getForMeeting(meetingId);
    final toDelete = notes.firstWhere((n) => n.content == 'First note content.');
    final toKeep = notes.firstWhere((n) => n.content == 'Second note content.');

    await controller.delete(toDelete);

    final remainingChunks = await knowledgeChunkRepository.getForMeeting(meetingId);
    expect(remainingChunks, isNotEmpty);
    expect(remainingChunks.every((c) => c.sourceId == toKeep.id), isTrue);
  });

  test('an indexing failure on add() does not prevent the note from being '
      'saved', () async {
    container = buildContainer(
      embeddingEngine: FakeEmbeddingEngine(errorToThrow: Exception('embedding crashed')),
    );
    final meetingId = await insertMeeting();

    await container.read(notesControllerProvider).add(meetingId, 'Should still save.');

    final notes = await noteRepository.getForMeeting(meetingId);
    expect(notes, hasLength(1));
    expect(notes.single.content, 'Should still save.');
    expect(await knowledgeChunkRepository.getForMeeting(meetingId), isEmpty);
  });

  test('an indexing failure on delete() does not prevent the note from '
      'being removed', () async {
    container = buildContainer();
    final meetingId = await insertMeeting();
    final controller = container.read(notesControllerProvider);
    await controller.add(meetingId, 'Note content.');
    final note = (await noteRepository.getForMeeting(meetingId)).single;

    // Swap in a container whose indexing service always throws on removal,
    // to prove delete() still removes the note row even when the
    // index-cleanup step fails.
    final failingContainer = ProviderContainer(
      overrides: [
        noteRepositoryProvider.overrideWithValue(noteRepository),
        indexingServiceProvider.overrideWithValue(
          _RemoveAlwaysThrowsIndexingService(
            DefaultIndexingService(
              chunkingService: const DefaultChunkingService(),
              embeddingEngine: FakeEmbeddingEngine(),
              vectorStore: BruteForceVectorStore(
                knowledgeChunkRepository: knowledgeChunkRepository,
              ),
              knowledgeChunkRepository: knowledgeChunkRepository,
            ),
          ),
        ),
      ],
    );
    addTearDown(failingContainer.dispose);
    await failingContainer.read(notesControllerProvider).delete(note);

    expect(await noteRepository.getForMeeting(meetingId), isEmpty);
  });
}
