// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ActionItem _$ActionItemFromJson(Map<String, dynamic> json) => _ActionItem(
  id: (json['id'] as num?)?.toInt(),
  meetingId: (json['meetingId'] as num).toInt(),
  description: json['description'] as String,
  isCompleted: json['isCompleted'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
  owner: json['owner'] as String?,
  dueDate: json['dueDate'] == null
      ? null
      : DateTime.parse(json['dueDate'] as String),
);

Map<String, dynamic> _$ActionItemToJson(_ActionItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'meetingId': instance.meetingId,
      'description': instance.description,
      'isCompleted': instance.isCompleted,
      'createdAt': instance.createdAt.toIso8601String(),
      'owner': instance.owner,
      'dueDate': instance.dueDate?.toIso8601String(),
    };
