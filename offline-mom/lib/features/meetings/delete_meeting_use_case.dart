import 'dart:io';

import '../../repositories/meeting_repository.dart';
import '../../services/retrieval/vector_store.dart';

/// Deletes a meeting and its audio file. Transcript/summary/action items/
/// decisions/knowledge_chunks are removed automatically by the database's
/// `ON DELETE CASCADE` foreign keys - only the on-disk audio file needs
/// explicit cleanup here, since the database doesn't know about the
/// filesystem. [VectorStore.invalidateCache] is called too (Phase 4B): the
/// CASCADE removes the `knowledge_chunks` *rows*, but `BruteForceVectorStore`
/// keeps its own in-memory copy of them that nothing else here would ever
/// tell to drop this meeting's entries - without this, a deleted meeting's
/// content could still surface in workspace chat/search answers for the
/// rest of the app session, until some unrelated `indexContent` call
/// happened to invalidate the cache first.
class DeleteMeetingUseCase {
  DeleteMeetingUseCase({
    required MeetingRepository meetingRepository,
    required VectorStore vectorStore,
  })  : _meetingRepository = meetingRepository,
        _vectorStore = vectorStore;

  final MeetingRepository _meetingRepository;
  final VectorStore _vectorStore;

  Future<void> call(int meetingId) async {
    final meeting = await _meetingRepository.getById(meetingId);
    if (meeting == null) return;

    final audioPath = meeting.audioFilePath;
    if (audioPath != null) {
      final file = File(audioPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await _meetingRepository.delete(meetingId);
    _vectorStore.invalidateCache();
  }
}
