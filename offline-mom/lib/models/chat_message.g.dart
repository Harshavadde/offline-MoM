// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => _ChatMessage(
  id: (json['id'] as num?)?.toInt(),
  sessionId: (json['sessionId'] as num).toInt(),
  role: $enumDecode(_$ChatMessageRoleEnumMap, json['role']),
  content: json['content'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  sourcesJson: json['sourcesJson'] as String?,
  answerProvenance: $enumDecodeNullable(
    _$AnswerProvenanceEnumMap,
    json['answerProvenance'],
  ),
);

Map<String, dynamic> _$ChatMessageToJson(_ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sessionId': instance.sessionId,
      'role': _$ChatMessageRoleEnumMap[instance.role]!,
      'content': instance.content,
      'createdAt': instance.createdAt.toIso8601String(),
      'sourcesJson': instance.sourcesJson,
      'answerProvenance': _$AnswerProvenanceEnumMap[instance.answerProvenance],
    };

const _$ChatMessageRoleEnumMap = {
  ChatMessageRole.user: 'user',
  ChatMessageRole.assistant: 'assistant',
};

const _$AnswerProvenanceEnumMap = {
  AnswerProvenance.local: 'local',
  AnswerProvenance.generalKnowledge: 'generalKnowledge',
};
