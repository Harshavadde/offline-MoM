import 'package:freezed_annotation/freezed_annotation.dart';

part 'action_item.freezed.dart';
part 'action_item.g.dart';

@freezed
abstract class ActionItem with _$ActionItem {
  const ActionItem._();

  const factory ActionItem({
    required int? id,
    required int meetingId,
    required String description,
    required bool isCompleted,
    required DateTime createdAt,
    String? owner,
    DateTime? dueDate,
  }) = _ActionItem;

  factory ActionItem.fromJson(Map<String, Object?> json) =>
      _$ActionItemFromJson(json);

  /// SQLite's own row shape (snake_case columns, bool as 0/1) - kept
  /// separate from [toJson]/[fromJson] (camelCase, generated).
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'description': description,
      'owner': owner,
      'due_date': dueDate?.toIso8601String(),
      'is_completed': isCompleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ActionItem.fromMap(Map<String, Object?> map) {
    return ActionItem(
      id: map['id'] as int?,
      meetingId: map['meeting_id'] as int,
      description: map['description'] as String,
      owner: map['owner'] as String?,
      dueDate: map['due_date'] == null
          ? null
          : DateTime.parse(map['due_date'] as String),
      isCompleted: (map['is_completed'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
