import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/knowledge/content_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../models/note.dart';
import '../../../../providers/app_providers.dart';

const _log = AppLogger('NotesController');

/// `autoDispose` (Phase 4B) - see `meetingByIdProvider`'s doc comment
/// (lib/features/meetings/presentation/providers/meeting_providers.dart) for
/// why every per-id detail-screen provider in this app uses it.
final notesForMeetingProvider =
    FutureProvider.autoDispose.family<List<Note>, int>((ref, meetingId) {
  return ref.watch(noteRepositoryProvider).getForMeeting(meetingId);
});

/// Add/edit/delete for a meeting's free-form notes. A thin wrapper over
/// [NoteRepository] rather than a full use case - there's no branching
/// orchestration here, just CRUD plus refreshing the list and keeping the
/// retrieval index in sync (M1.2/1C, ADR-021,
/// docs/v2/implementation/03-decisions.md: "Notes modified" is one of the
/// content changes the index must automatically stay consistent with).
///
/// Indexing failures are caught and logged, never rethrown - a note is
/// still successfully saved/edited/deleted even if the background
/// chunk-embed-store step fails, the same "don't let indexing look like
/// the primary action failed" posture `DocumentIndexer`/`MeetingIndexer`
/// already use for their own pipelines (there they flip a status field to
/// `error` instead; a bare [Note] has no such field, so logging is this
/// call site's equivalent).
class NotesController {
  NotesController(this.ref);

  final Ref ref;

  Future<void> add(int meetingId, String content) async {
    final now = DateTime.now();
    final noteId = await ref.read(noteRepositoryProvider).insert(
          Note(
            id: null,
            meetingId: meetingId,
            content: content,
            createdAt: now,
            updatedAt: now,
          ),
        );
    ref.invalidate(notesForMeetingProvider(meetingId));
    await _indexNote(sourceId: noteId, meetingId: meetingId, content: content);
  }

  Future<void> edit(Note note, String content) async {
    await ref.read(noteRepositoryProvider).update(
          note.copyWith(content: content, updatedAt: DateTime.now()),
        );
    ref.invalidate(notesForMeetingProvider(note.meetingId));
    await _indexNote(sourceId: note.id!, meetingId: note.meetingId, content: content);
  }

  Future<void> delete(Note note) async {
    await ref.read(noteRepositoryProvider).delete(note.id!);
    ref.invalidate(notesForMeetingProvider(note.meetingId));
    try {
      await ref
          .read(indexingServiceProvider)
          .removeIndexForSource(ContentType.note, note.id!);
    } catch (e, stackTrace) {
      _log.warning(
        'Failed to remove note ${note.id} from the retrieval index',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _indexNote({
    required int sourceId,
    required int meetingId,
    required String content,
  }) async {
    if (content.trim().isEmpty) return;
    try {
      await ref.read(indexingServiceProvider).indexContent(
            contentType: ContentType.note,
            sourceId: sourceId,
            meetingId: meetingId,
            text: content,
          );
    } catch (e, stackTrace) {
      _log.warning('Failed to index note $sourceId', error: e, stackTrace: stackTrace);
    }
  }
}

final notesControllerProvider = Provider<NotesController>((ref) {
  return NotesController(ref);
});
