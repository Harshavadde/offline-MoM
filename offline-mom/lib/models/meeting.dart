import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting.freezed.dart';
part 'meeting.g.dart';

/// How a meeting's audio came to exist in the app.
enum MeetingSource { recorded, imported }

/// Where a meeting sits in the offline processing pipeline.
///
/// Every meeting starts at [created] and moves forward as later phases
/// (transcription, AI summarization) act on it. A meeting can only reach
/// [ready] once it has a transcript and a summary.
///
/// [downloadingModel] is a one-time-per-device sub-stage of transcription:
/// the whisper model has to be downloaded before it can transcribe
/// anything. Kept as its own status (rather than folded into
/// [transcribing]) so the UI can tell a user "downloading the speech
/// model" instead of leaving them staring at a generic spinner for
/// however long that one-time download takes.
///
/// [downloadingSummaryModel] is the same idea for the one-time-per-device
/// LLM (summarization) model download, a sub-stage of [summarizing].
///
/// [audioMissing] is a distinct, diagnosable terminal state (added in
/// migration v4/Phase 0 - see docs/v2/implementation/02-backlog.md Task
/// 1.3.1.1) for the specific case where [Meeting.audioFilePath] points at
/// a file that no longer exists on disk (deleted or moved outside the
/// app) when the pipeline is about to transcribe it - previously this
/// surfaced as a generic [error] with a confusing ffmpeg/whisper failure
/// message instead of the real, simple cause.
///
/// [indexing] (V2 Phase 1C, ADR-021, docs/v2/implementation/03-decisions.md)
/// mirrors [DocumentStatus.indexing] exactly: a brief, transient sub-stage
/// after [summarizing] where the meeting's transcript and summary are
/// chunked and embedded for retrieval (`MeetingIndexer`), before settling
/// on the final [ready]. Nothing reads or renders this state as blocking
/// - a meeting visits [ready] once from summarization, then briefly
/// [indexing], then [ready] again - same reasoning as `DocumentIndexer`'s
/// doc comment.
enum MeetingStatus {
  created,
  downloadingModel,
  transcribing,
  downloadingSummaryModel,
  summarizing,
  indexing,
  ready,
  error,
  audioMissing,
}

@freezed
abstract class Meeting with _$Meeting {
  const Meeting._();

  const factory Meeting({
    required int? id,
    required String title,
    required MeetingSource source,
    required MeetingStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(0) int durationSeconds,
    String? audioFilePath,
    @Default(false) bool isFavorite,

    /// Set when [status] is [MeetingStatus.error]; the exception message
    /// from whichever pipeline stage (transcription or AI summary) failed,
    /// so a failure is diagnosable instead of a dead end.
    String? errorMessage,
  }) = _Meeting;

  factory Meeting.fromJson(Map<String, Object?> json) => _$MeetingFromJson(json);

  /// Returns a copy with [errorMessage] explicitly cleared. A thin
  /// convenience wrapper now - freezed's generated `copyWith` (unlike the
  /// hand-written version this replaced) already distinguishes "not
  /// passed" from "explicitly passed null" for nullable fields, so
  /// `copyWith(errorMessage: null)` alone would do the same thing; this
  /// just names that specific, common case.
  Meeting clearError() => copyWith(errorMessage: null);

  /// SQLite's own row shape (snake_case columns, enums as their `.name`,
  /// bool as 0/1) - kept separate from [toJson]/[fromJson].
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'source': source.name,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'duration_seconds': durationSeconds,
      'audio_file_path': audioFilePath,
      'error_message': errorMessage,
      'is_favorite': isFavorite ? 1 : 0,
    };
  }

  factory Meeting.fromMap(Map<String, Object?> map) {
    return Meeting(
      id: map['id'] as int?,
      title: map['title'] as String,
      source: MeetingSource.values.byName(map['source'] as String),
      status: MeetingStatus.values.byName(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      audioFilePath: map['audio_file_path'] as String?,
      errorMessage: map['error_message'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
    );
  }
}
