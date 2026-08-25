import 'package:sqflite/sqflite.dart';

import '../core/utils/fts5_query_builder.dart';
import '../database/tables.dart';

/// Full-text search over the [ContentFtsTable] index (migration v4,
/// extended for documents in v6) - covers meeting titles, transcripts,
/// summaries (meeting- or document-owned), action items, notes, document
/// titles, and document text, all through **one** query against **one**
/// table. This is what "one search implementation, no duplicate search
/// repositories" (V2 Phase 1A requirement) means concretely: adding
/// documents to search did not require a second repository, a second
/// index, or a second query - only two more trigger-fed content types in
/// the same index this repository already queried. Decisions intentionally
/// stay out of this index; see `migrations/v4.dart`'s doc comment.
abstract class ContentSearchRepository {
  /// Ids of every meeting and document with at least one indexed piece of
  /// content matching [query].
  Future<ContentSearchResults> search(String query);
}

/// Partitioned by content type so a caller (e.g. `SearchMeetingsUseCase`)
/// can resolve each set back to full [Meeting]/[Document] rows via their
/// own repository, exactly the same "collect matching ids, then one
/// `getByIds` call" pattern already used for meetings alone before V2.
class ContentSearchResults {
  const ContentSearchResults({
    required this.meetingIds,
    required this.documentIds,
    this.meetingContentTypes = const {},
    this.documentContentTypes = const {},
  });

  final Set<int> meetingIds;
  final Set<int> documentIds;

  /// Which [ContentType] names (e.g. `'note'`, `'transcript'`, `'summary'`)
  /// matched for each meeting id - Phase 2B (docs/v2/implementation/03-decisions.md,
  /// ADR-028): lets `SearchWorkspaceUseCase`/`SearchScreen` group results by
  /// content type and filter by Notes, without a second query - the data was
  /// already present per-row in `content_fts.content_type`, just previously
  /// discarded by the `SELECT DISTINCT` this repository used to run.
  final Map<int, Set<String>> meetingContentTypes;
  final Map<int, Set<String>> documentContentTypes;

  bool get isEmpty => meetingIds.isEmpty && documentIds.isEmpty;
}

class SqfliteContentSearchRepository implements ContentSearchRepository {
  SqfliteContentSearchRepository(this._db);

  final Database _db;

  @override
  Future<ContentSearchResults> search(String query) async {
    final matchQuery = buildFts5MatchQuery(query);
    if (matchQuery == null) {
      return const ContentSearchResults(meetingIds: {}, documentIds: {});
    }

    final rows = await _db.rawQuery(
      'SELECT DISTINCT ${ContentFtsTable.contentType}, ${ContentFtsTable.meetingId}, ${ContentFtsTable.documentId} '
      'FROM ${ContentFtsTable.name} '
      'WHERE ${ContentFtsTable.name} MATCH ?',
      [matchQuery],
    );

    final meetingIds = <int>{};
    final documentIds = <int>{};
    final meetingContentTypes = <int, Set<String>>{};
    final documentContentTypes = <int, Set<String>>{};
    for (final row in rows) {
      final contentType = row[ContentFtsTable.contentType] as String;
      final meetingId = row[ContentFtsTable.meetingId] as int?;
      final documentId = row[ContentFtsTable.documentId] as int?;
      if (meetingId != null) {
        meetingIds.add(meetingId);
        meetingContentTypes.putIfAbsent(meetingId, () => <String>{}).add(contentType);
      }
      if (documentId != null) {
        documentIds.add(documentId);
        documentContentTypes.putIfAbsent(documentId, () => <String>{}).add(contentType);
      }
    }
    return ContentSearchResults(
      meetingIds: meetingIds,
      documentIds: documentIds,
      meetingContentTypes: meetingContentTypes,
      documentContentTypes: documentContentTypes,
    );
  }
}
