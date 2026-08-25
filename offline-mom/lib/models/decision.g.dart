// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decision.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Decision _$DecisionFromJson(Map<String, dynamic> json) => _Decision(
  id: (json['id'] as num?)?.toInt(),
  meetingId: (json['meetingId'] as num).toInt(),
  description: json['description'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$DecisionToJson(_Decision instance) => <String, dynamic>{
  'id': instance.id,
  'meetingId': instance.meetingId,
  'description': instance.description,
  'createdAt': instance.createdAt.toIso8601String(),
};
