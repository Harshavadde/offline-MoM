import 'package:freezed_annotation/freezed_annotation.dart';

part 'document.freezed.dart';
part 'document.g.dart';

/// The imported file format, driving which parser
/// (services/documents/parsers/) handles extraction.
enum DocumentSourceType { pdf, docx, txt, markdown }

/// Where a document sits in the offline processing pipeline - mirrors
/// [MeetingStatus] deliberately (same reasoning: [downloadingSummaryModel]
/// is a one-time-per-device sub-stage of [summarizing], kept distinct so
/// the UI can say "downloading the AI model" instead of a generic
/// spinner).
///
/// [indexing] is reserved for V2 Phase 1B (chunking/embedding, see
/// docs/v2/14-rag-architecture.md) - **not used by any Phase 1A code
/// path**. It exists now only so a future migration doesn't need to
/// reintroduce it; Phase 1A's pipeline is
/// `created -> extracting -> downloadingSummaryModel -> summarizing -> ready`.
enum DocumentStatus {
  created,
  extracting,
  downloadingSummaryModel,
  summarizing,
  indexing,
  ready,
  error,
}

@freezed
abstract class Document with _$Document {
  const Document._();

  const factory Document({
    required int? id,

    /// User-editable display name - defaults to [originalFilename] minus
    /// its extension on import, same convention as `ImportController`
    /// titling an imported meeting from its picked filename.
    required String title,

    /// The literal filename as picked at import time - immutable
    /// historical record, distinct from [title] (which the user can
    /// rename freely via [DocumentStatus]-independent rename support).
    required String originalFilename,
    required DocumentSourceType sourceType,
    required String mimeType,
    required int fileSizeBytes,
    required String filePath,
    required DocumentStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? extractedText,

    /// Set when [status] is [DocumentStatus.error] - mirrors
    /// [Meeting.errorMessage]'s diagnosability rationale.
    String? errorMessage,
  }) = _Document;

  factory Document.fromJson(Map<String, Object?> json) =>
      _$DocumentFromJson(json);

  /// SQLite's own row shape, kept separate from [toJson]/[fromJson] - same
  /// convention as every other model in lib/models/.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'original_filename': originalFilename,
      'source_type': sourceType.name,
      'mime_type': mimeType,
      'file_size_bytes': fileSizeBytes,
      'file_path': filePath,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'extracted_text': extractedText,
      'error_message': errorMessage,
    };
  }

  factory Document.fromMap(Map<String, Object?> map) {
    return Document(
      id: map['id'] as int?,
      title: map['title'] as String,
      originalFilename: map['original_filename'] as String,
      sourceType: DocumentSourceType.values.byName(map['source_type'] as String),
      mimeType: map['mime_type'] as String,
      fileSizeBytes: map['file_size_bytes'] as int,
      filePath: map['file_path'] as String,
      status: DocumentStatus.values.byName(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      extractedText: map['extracted_text'] as String?,
      errorMessage: map['error_message'] as String?,
    );
  }
}

/// Maps a [DocumentSourceType] to its canonical MIME type, and vice versa
/// for interpreting a picked file's extension - kept next to [Document]
/// since both the import flow and the parser-selection logic
/// (services/documents/document_text_extraction_service.dart) need this
/// same mapping and shouldn't each maintain their own copy of it.
extension DocumentSourceTypeMime on DocumentSourceType {
  String get mimeType => switch (this) {
        DocumentSourceType.pdf => 'application/pdf',
        DocumentSourceType.docx =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        DocumentSourceType.txt => 'text/plain',
        DocumentSourceType.markdown => 'text/markdown',
      };

  static DocumentSourceType? fromExtension(String extension) {
    switch (extension.toLowerCase().replaceFirst('.', '')) {
      case 'pdf':
        return DocumentSourceType.pdf;
      case 'docx':
        return DocumentSourceType.docx;
      case 'txt':
        return DocumentSourceType.txt;
      case 'md':
      case 'markdown':
        return DocumentSourceType.markdown;
      default:
        return null;
    }
  }
}
