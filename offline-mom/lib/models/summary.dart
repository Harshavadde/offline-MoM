import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'summary.freezed.dart';
part 'summary.g.dart';

/// The AI-generated summary artifacts for one meeting OR one document
/// (never both, never neither) - a short summary, the formal Minutes of
/// Meeting document, and the extracted key topics.
///
/// [meetingId]/[documentId] mirrors the schema's own two-nullable-FK +
/// CHECK constraint pattern (ADR-005, docs/v2/implementation/03-decisions.md):
/// one shared table for both content types rather than a parallel
/// `document_summaries` table, since the shape of "a text summary
/// belonging to one piece of content" is identical either way.
///
/// Action items and decisions are extracted alongside a meeting's summary
/// but stored as their own entities ([ActionItem], [Decision]) since
/// they're independently searchable and checkable off - documents have no
/// equivalent (V2 Phase 1A doesn't extract structured data from documents,
/// only a summary).
@freezed
abstract class Summary with _$Summary {
  const Summary._();

  @Assert(
    '(meetingId != null) != (documentId != null)',
    'exactly one of meetingId/documentId must be set',
  )
  const factory Summary({
    required int? id,
    int? meetingId,
    int? documentId,
    required String summaryText,
    required String minutesOfMeeting,
    required List<String> keyTopics,
    required String modelUsed,
    required DateTime generatedAt,
  }) = _Summary;

  factory Summary.fromJson(Map<String, Object?> json) => _$SummaryFromJson(json);

  /// SQLite's own row shape (snake_case columns, [keyTopics] flattened to
  /// one JSON-text column) - kept separate from [toJson]/[fromJson]
  /// (camelCase, generated, `keyTopics` as a native JSON array).
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'document_id': documentId,
      'summary_text': summaryText,
      'minutes_of_meeting': minutesOfMeeting,
      'key_topics_json': jsonEncode(keyTopics),
      'model_used': modelUsed,
      'generated_at': generatedAt.toIso8601String(),
    };
  }

  factory Summary.fromMap(Map<String, Object?> map) {
    return Summary(
      id: map['id'] as int?,
      meetingId: map['meeting_id'] as int?,
      documentId: map['document_id'] as int?,
      summaryText: map['summary_text'] as String,
      minutesOfMeeting: map['minutes_of_meeting'] as String,
      keyTopics: (jsonDecode(map['key_topics_json'] as String) as List)
          .cast<String>(),
      modelUsed: map['model_used'] as String,
      generatedAt: DateTime.parse(map['generated_at'] as String),
    );
  }
}
