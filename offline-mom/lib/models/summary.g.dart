// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Summary _$SummaryFromJson(Map<String, dynamic> json) => _Summary(
  id: (json['id'] as num?)?.toInt(),
  meetingId: (json['meetingId'] as num?)?.toInt(),
  documentId: (json['documentId'] as num?)?.toInt(),
  summaryText: json['summaryText'] as String,
  minutesOfMeeting: json['minutesOfMeeting'] as String,
  keyTopics: (json['keyTopics'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  modelUsed: json['modelUsed'] as String,
  generatedAt: DateTime.parse(json['generatedAt'] as String),
);

Map<String, dynamic> _$SummaryToJson(_Summary instance) => <String, dynamic>{
  'id': instance.id,
  'meetingId': instance.meetingId,
  'documentId': instance.documentId,
  'summaryText': instance.summaryText,
  'minutesOfMeeting': instance.minutesOfMeeting,
  'keyTopics': instance.keyTopics,
  'modelUsed': instance.modelUsed,
  'generatedAt': instance.generatedAt.toIso8601String(),
};
