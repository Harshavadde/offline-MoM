import 'package:intl/intl.dart';

import '../../models/document.dart';
import '../../models/meeting.dart';
import '../../repositories/content_search_repository.dart';
import '../../repositories/decision_repository.dart';
import '../../repositories/document_repository.dart';
import '../../repositories/meeting_repository.dart';

/// Both halves of a search: meetings and documents matching the same
/// query, resolved from the single [ContentSearchRepository] index (V2
/// Phase 1A requirement: "one search implementation, no duplicate search
/// repositories").
class SearchResults {
  const SearchResults({
    required this.meetings,
    required this.documents,
    this.meetingContentTypes = const {},
    this.documentContentTypes = const {},
  });

  final List<Meeting> meetings;
  final List<Document> documents;

  /// Which content-type strings (`'note'`, `'transcript'`, `'summary'`,
  /// `'action_item'`, `'meeting'`) matched for each result - Phase 2B
  /// Workspace Search ("Display grouped results", "Filter by ... Notes",
  /// docs/v2/implementation/03-decisions.md ADR-028). A date- or
  /// decision-only match has no entry here (those aren't part of the FTS5
  /// index - see `migrations/v4.dart`'s doc comment), which is correct: they
  /// have no content type to group or filter by.
  final Map<int, Set<String>> meetingContentTypes;
  final Map<int, Set<String>> documentContentTypes;

  bool get isEmpty => meetings.isEmpty && documents.isEmpty;
}

/// Searches across meeting titles, transcripts, summaries, action items,
/// notes, dates, document titles, and document text/summaries - a single
/// query fans out to [ContentSearchRepository] (one FTS5 index covering
/// everything except decisions and dates), [DecisionRepository], and a
/// date-range lookup, and the resulting ids are unioned per content type.
/// Real cross-repository orchestration, not a trivial single-table lookup.
///
/// Renamed from `SearchMeetingsUseCase` in Phase 2B (ADR-028,
/// docs/v2/implementation/03-decisions.md) - a rename anticipated by that
/// class's own former doc comment and gap-analysis §3: this use case always
/// searched both meetings and documents, so "workspace" now names what it
/// actually does, backing the Phase 2B "true Workspace Search" requirement.
///
/// Decisions deliberately stay on their own separate, unindexed lookup
/// rather than joining the FTS5 index (see `migrations/v4.dart`'s doc
/// comment) - that table is permanent schema-compatibility dead weight
/// (ADR-012, docs/v2/implementation/03-decisions.md).
class SearchWorkspaceUseCase {
  SearchWorkspaceUseCase({
    required MeetingRepository meetingRepository,
    required DocumentRepository documentRepository,
    required ContentSearchRepository contentSearchRepository,
    required DecisionRepository decisionRepository,
  })  : _meetingRepository = meetingRepository,
        _documentRepository = documentRepository,
        _contentSearchRepository = contentSearchRepository,
        _decisionRepository = decisionRepository;

  final MeetingRepository _meetingRepository;
  final DocumentRepository _documentRepository;
  final ContentSearchRepository _contentSearchRepository;
  final DecisionRepository _decisionRepository;

  static final List<DateFormat> _dateFormats = [
    DateFormat.yMMMd(),
    DateFormat('yyyy-MM-dd'),
    DateFormat('M/d/yyyy'),
    DateFormat('M/d/yy'),
  ];

  Future<SearchResults> call(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return const SearchResults(meetings: [], documents: []);
    }

    final matchedMeetingIds = <int>{};

    final asDate = _tryParseDate(query);
    if (asDate != null) {
      final startOfDay = DateTime(asDate.year, asDate.month, asDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      matchedMeetingIds.addAll(
        await _meetingRepository.findIdsByDateRange(startOfDay, endOfDay),
      );
    }

    final contentResults = await _contentSearchRepository.search(query);
    matchedMeetingIds.addAll(contentResults.meetingIds);
    matchedMeetingIds.addAll(
      await _decisionRepository.findMeetingIdsByDescription(query),
    );

    final meetings = matchedMeetingIds.isEmpty
        ? <Meeting>[]
        : await _meetingRepository.getByIds(matchedMeetingIds);

    final documents = contentResults.documentIds.isEmpty
        ? <Document>[]
        : await _documentRepository.getByIds(contentResults.documentIds);

    return SearchResults(
      meetings: meetings,
      documents: documents,
      meetingContentTypes: contentResults.meetingContentTypes,
      documentContentTypes: contentResults.documentContentTypes,
    );
  }

  DateTime? _tryParseDate(String query) {
    for (final format in _dateFormats) {
      try {
        return format.parseStrict(query);
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
