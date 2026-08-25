// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meeting.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Meeting _$MeetingFromJson(Map<String, dynamic> json) => _Meeting(
  id: (json['id'] as num?)?.toInt(),
  title: json['title'] as String,
  source: $enumDecode(_$MeetingSourceEnumMap, json['source']),
  status: $enumDecode(_$MeetingStatusEnumMap, json['status']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
  audioFilePath: json['audioFilePath'] as String?,
  isFavorite: json['isFavorite'] as bool? ?? false,
  errorMessage: json['errorMessage'] as String?,
);

Map<String, dynamic> _$MeetingToJson(_Meeting instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'source': _$MeetingSourceEnumMap[instance.source]!,
  'status': _$MeetingStatusEnumMap[instance.status]!,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'durationSeconds': instance.durationSeconds,
  'audioFilePath': instance.audioFilePath,
  'isFavorite': instance.isFavorite,
  'errorMessage': instance.errorMessage,
};

const _$MeetingSourceEnumMap = {
  MeetingSource.recorded: 'recorded',
  MeetingSource.imported: 'imported',
};

const _$MeetingStatusEnumMap = {
  MeetingStatus.created: 'created',
  MeetingStatus.downloadingModel: 'downloadingModel',
  MeetingStatus.transcribing: 'transcribing',
  MeetingStatus.downloadingSummaryModel: 'downloadingSummaryModel',
  MeetingStatus.summarizing: 'summarizing',
  MeetingStatus.indexing: 'indexing',
  MeetingStatus.ready: 'ready',
  MeetingStatus.error: 'error',
  MeetingStatus.audioMissing: 'audioMissing',
};
