class Note {
  const Note({
    required this.id,
    required this.meetingId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int meetingId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note copyWith({String? content, DateTime? updatedAt}) {
    return Note(
      id: id,
      meetingId: meetingId,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    return Note(
      id: map['id'] as int?,
      meetingId: map['meeting_id'] as int,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
