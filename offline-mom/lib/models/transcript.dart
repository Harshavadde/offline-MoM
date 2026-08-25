import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript.freezed.dart';
part 'transcript.g.dart';

/// A single timed utterance produced by the offline speech-to-text engine.
///
/// Plain `@JsonSerializable`, not `@freezed`: it's a value embedded inside
/// [Transcript]'s single `segments_json` column, not an entity in its own
/// right, and wasn't part of the requested Meeting/Transcript/Summary/
/// ActionItem/Decision set. It still needs *some* JSON support, though -
/// once any field in a `@freezed` class has a `fromJson`/`toJson` method,
/// freezed expects the whole object graph (including `List<TranscriptSegment>`
/// here) to be JSON-codable, so this gets the minimal annotation needed to
/// satisfy that rather than hand-rolling a converter.
@JsonSerializable()
class TranscriptSegment {
  const TranscriptSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int startMs;
  final int endMs;
  final String text;

  factory TranscriptSegment.fromJson(Map<String, Object?> json) =>
      _$TranscriptSegmentFromJson(json);
  Map<String, Object?> toJson() => _$TranscriptSegmentToJson(this);

  Map<String, Object?> toMap() => {
        'start_ms': startMs,
        'end_ms': endMs,
        'text': text,
      };

  factory TranscriptSegment.fromMap(Map<String, Object?> map) {
    return TranscriptSegment(
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
      text: map['text'] as String,
    );
  }
}

/// The full offline transcription result for one meeting.
@freezed
abstract class Transcript with _$Transcript {
  const Transcript._();

  const factory Transcript({
    required int? id,
    required int meetingId,
    required String language,
    required String fullText,
    required List<TranscriptSegment> segments,
    required DateTime createdAt,
  }) = _Transcript;

  factory Transcript.fromJson(Map<String, Object?> json) => _$TranscriptFromJson(json);

  /// SQLite's own row shape (snake_case columns, `segments` flattened to
  /// one JSON-text column) - kept separate from [toJson]/[fromJson]
  /// (camelCase, generated, `segments` as a native JSON array).
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'language': language,
      'full_text': fullText,
      'segments_json': jsonEncode(segments.map((s) => s.toMap()).toList()),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Transcript.fromMap(Map<String, Object?> map) {
    final rawSegments = jsonDecode(map['segments_json'] as String) as List;
    return Transcript(
      id: map['id'] as int?,
      meetingId: map['meeting_id'] as int,
      language: map['language'] as String,
      fullText: map['full_text'] as String,
      segments: rawSegments
          .cast<Map<String, Object?>>()
          .map(TranscriptSegment.fromMap)
          .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
