// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChatSession _$ChatSessionFromJson(Map<String, dynamic> json) => _ChatSession(
  id: (json['id'] as num?)?.toInt(),
  title: json['title'] as String,
  scope: $enumDecode(_$ChatScopeEnumMap, json['scope']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  documentId: (json['documentId'] as num?)?.toInt(),
  meetingId: (json['meetingId'] as num?)?.toInt(),
  isPinned: json['isPinned'] as bool? ?? false,
);

Map<String, dynamic> _$ChatSessionToJson(_ChatSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'scope': _$ChatScopeEnumMap[instance.scope]!,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'documentId': instance.documentId,
      'meetingId': instance.meetingId,
      'isPinned': instance.isPinned,
    };

const _$ChatScopeEnumMap = {
  ChatScope.general: 'general',
  ChatScope.workspace: 'workspace',
  ChatScope.document: 'document',
  ChatScope.meeting: 'meeting',
};
