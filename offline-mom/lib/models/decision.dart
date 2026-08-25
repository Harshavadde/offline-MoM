import 'package:freezed_annotation/freezed_annotation.dart';

part 'decision.freezed.dart';
part 'decision.g.dart';

@freezed
abstract class Decision with _$Decision {
  const Decision._();

  const factory Decision({
    required int? id,
    required int meetingId,
    required String description,
    required DateTime createdAt,
  }) = _Decision;

  factory Decision.fromJson(Map<String, Object?> json) => _$DecisionFromJson(json);

  /// SQLite's own row shape (snake_case columns) - kept separate from
  /// [toJson]/[fromJson] (camelCase, generated) since the database schema
  /// and a general-purpose JSON representation aren't obligated to match.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Decision.fromMap(Map<String, Object?> map) {
    return Decision(
      id: map['id'] as int?,
      meetingId: map['meeting_id'] as int,
      description: map['description'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
