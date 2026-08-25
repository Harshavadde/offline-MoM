// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranscriptSegment _$TranscriptSegmentFromJson(Map<String, dynamic> json) =>
    TranscriptSegment(
      startMs: (json['startMs'] as num).toInt(),
      endMs: (json['endMs'] as num).toInt(),
      text: json['text'] as String,
    );

Map<String, dynamic> _$TranscriptSegmentToJson(TranscriptSegment instance) =>
    <String, dynamic>{
      'startMs': instance.startMs,
      'endMs': instance.endMs,
      'text': instance.text,
    };

_Transcript _$TranscriptFromJson(Map<String, dynamic> json) => _Transcript(
  id: (json['id'] as num?)?.toInt(),
  meetingId: (json['meetingId'] as num).toInt(),
  language: json['language'] as String,
  fullText: json['fullText'] as String,
  segments: (json['segments'] as List<dynamic>)
      .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
      .toList(),
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$TranscriptToJson(_Transcript instance) =>
    <String, dynamic>{
      'id': instance.id,
      'meetingId': instance.meetingId,
      'language': instance.language,
      'fullText': instance.fullText,
      'segments': instance.segments,
      'createdAt': instance.createdAt.toIso8601String(),
    };
