/// A timestamp the user flagged mid-recording (the "Mark" button) - a
/// lightweight bookmark, not a transcript segment.
class RecordingMark {
  const RecordingMark({
    required this.id,
    required this.meetingId,
    required this.offsetMs,
    required this.createdAt,
  });

  final int? id;
  final int meetingId;
  final int offsetMs;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'offset_ms': offsetMs,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory RecordingMark.fromMap(Map<String, Object?> map) {
    return RecordingMark(
      id: map['id'] as int?,
      meetingId: map['meeting_id'] as int,
      offsetMs: map['offset_ms'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
