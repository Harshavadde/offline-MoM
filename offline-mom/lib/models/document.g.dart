// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Document _$DocumentFromJson(Map<String, dynamic> json) => _Document(
  id: (json['id'] as num?)?.toInt(),
  title: json['title'] as String,
  originalFilename: json['originalFilename'] as String,
  sourceType: $enumDecode(_$DocumentSourceTypeEnumMap, json['sourceType']),
  mimeType: json['mimeType'] as String,
  fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
  filePath: json['filePath'] as String,
  status: $enumDecode(_$DocumentStatusEnumMap, json['status']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  extractedText: json['extractedText'] as String?,
  errorMessage: json['errorMessage'] as String?,
);

Map<String, dynamic> _$DocumentToJson(_Document instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'originalFilename': instance.originalFilename,
  'sourceType': _$DocumentSourceTypeEnumMap[instance.sourceType]!,
  'mimeType': instance.mimeType,
  'fileSizeBytes': instance.fileSizeBytes,
  'filePath': instance.filePath,
  'status': _$DocumentStatusEnumMap[instance.status]!,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'extractedText': instance.extractedText,
  'errorMessage': instance.errorMessage,
};

const _$DocumentSourceTypeEnumMap = {
  DocumentSourceType.pdf: 'pdf',
  DocumentSourceType.docx: 'docx',
  DocumentSourceType.txt: 'txt',
  DocumentSourceType.markdown: 'markdown',
};

const _$DocumentStatusEnumMap = {
  DocumentStatus.created: 'created',
  DocumentStatus.extracting: 'extracting',
  DocumentStatus.downloadingSummaryModel: 'downloadingSummaryModel',
  DocumentStatus.summarizing: 'summarizing',
  DocumentStatus.indexing: 'indexing',
  DocumentStatus.ready: 'ready',
  DocumentStatus.error: 'error',
};
