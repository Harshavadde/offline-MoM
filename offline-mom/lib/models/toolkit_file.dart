/// Which Student Toolkit tool produced a [ToolkitFile]. A plain enum, not a
/// sealed/freezed hierarchy - every tool produces the same shape of result
/// (one output file + before/after size + optional page count), so there's
/// nothing tool-specific for the type to carry beyond its name.
///
/// `scan`/`pdfCompress`/`pdfMerge`/`pdfSplit`/`pdfOrganize` added in V2
/// Phase 5B (Scanner + PDF Tools) alongside `pageCount` - see ADR-034,
/// docs/v2/implementation/03-decisions.md. `pdfOrganize` covers both
/// "Extract Pages" and "Reorder Pages" from the product brief: both are the
/// same underlying operation (rebuild a PDF from a chosen, ordered subset of
/// an existing PDF's pages), so they share one tool rather than two
/// near-identical page-list screens.
///
/// `pdfEdit` added in the Productivity Toolkit productization pass (P0-3,
/// ADR-041) - Add Text, Signatures, Annotations, and Watermark all save
/// through this one tool type, since they're all the same underlying
/// "apply overlays, rebuild the PDF" operation (`PdfOverlayService`, ADR-040)
/// distinguished only by which `PdfOverlayElement`s the editor session
/// produced, not by anything the saved-file record itself needs to track.
///
/// `pdfRedact` added in the same pass (P0-4, ADR-042) - deliberately its
/// own tool type, not folded into `pdfEdit`, since it is backed by a
/// different service (`PdfRedactionService`, not `PdfOverlayService`) with
/// a different security property (`pdfEdit`'s outputs still contain their
/// full original page content underneath any overlay; `pdfRedact`'s
/// outputs have had the selected regions' original pixels permanently
/// overwritten) - conflating the two in Recent Files would misrepresent
/// what actually happened to a saved file.
/// `imagesToPdf`/`pdfToImages` added in the same pass (P0-6) - converting
/// between standalone images and a PDF, distinct from Scanner's own
/// image->PDF path (`scan`, camera/gallery capture with crop/perspective
/// correction) and from Merge's own image-as-one-page-of-a-mix path
/// (`pdfMerge`) - this is a dedicated "just combine/split these, nothing
/// else" tool.
enum ToolkitToolType {
  imageCompress,
  imageResize,
  scan,
  pdfCompress,
  pdfMerge,
  pdfSplit,
  pdfOrganize,
  pdfEdit,
  pdfRedact,
  imagesToPdf,
  pdfToImages,
  ocr,
  pdfProtect,
  pdfUnlock,
}

extension ToolkitToolTypeLabel on ToolkitToolType {
  String get label => switch (this) {
        ToolkitToolType.imageCompress => 'Image Compress',
        ToolkitToolType.imageResize => 'Image Resize',
        ToolkitToolType.scan => 'Scan',
        ToolkitToolType.pdfCompress => 'PDF Compress',
        ToolkitToolType.pdfMerge => 'PDF Merge',
        ToolkitToolType.pdfSplit => 'PDF Split',
        ToolkitToolType.pdfOrganize => 'PDF Organize',
        ToolkitToolType.pdfEdit => 'PDF Edit',
        ToolkitToolType.pdfRedact => 'PDF Redact',
        ToolkitToolType.imagesToPdf => 'Images to PDF',
        ToolkitToolType.pdfToImages => 'PDF to Images',
        ToolkitToolType.ocr => 'Searchable PDF',
        ToolkitToolType.pdfProtect => 'Protected PDF',
        ToolkitToolType.pdfUnlock => 'Unlocked PDF',
      };
}

/// One saved Student Toolkit output (Recent Files) - a plain class, not
/// `@freezed`, mirroring [Note]/[KnowledgeChunk]'s precedent for a simple,
/// internal, `copyWith`-light value type with no nested unions.
class ToolkitFile {
  const ToolkitFile({
    required this.id,
    required this.toolType,
    required this.title,
    required this.outputPath,
    required this.fileSizeBytes,
    required this.originalFileSizeBytes,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
    this.pageCount,
    this.folderId,
  });

  final int? id;
  final ToolkitToolType toolType;

  /// User-editable display name - defaults to the source file's name
  /// (minus extension) at creation time, same convention as
  /// `Document.title`.
  final String title;

  /// Where the produced file lives on device (app-private storage - see
  /// `toolkit_paths.dart`).
  final String outputPath;
  final int fileSizeBytes;

  /// The source file's size before this tool ran, if known - drives the
  /// before/after reduction percentage shown in Recent Files. Null only if
  /// the source's size genuinely couldn't be read (should not happen in
  /// practice, since every tool reads the source file's length itself
  /// before processing it), or if the notion of "before" doesn't apply
  /// (e.g. a fresh scan has no prior file to compare against).
  final int? originalFileSizeBytes;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Page count for a scan or PDF output (V2 Phase 5B, migration v12) -
  /// null for image compress/resize rows, which have no notion of pages.
  final int? pageCount;

  /// Which `ToolkitFoldersTable` row this file has been organized into
  /// (P0-9 File-Manager Parity, migration v21) - null means "All Files",
  /// the unfiled default.
  final int? folderId;

  /// Percentage size reduction versus the original, or null if there's no
  /// original size to compare against. Negative if the "compressed" output
  /// ended up larger than the source (rare, but honest - e.g. a tiny PNG
  /// re-encoded through a pipeline with per-format overhead, or a
  /// text-heavy PDF rasterized to page images per ADR-034's disclosed
  /// tradeoff).
  double? get reductionPercent {
    final original = originalFileSizeBytes;
    if (original == null || original <= 0) return null;
    return (1 - (fileSizeBytes / original)) * 100;
  }

  ToolkitFile copyWith({
    String? title,
    bool? isFavorite,
    DateTime? updatedAt,
    int? folderId,
    bool clearFolder = false,
  }) {
    return ToolkitFile(
      id: id,
      toolType: toolType,
      title: title ?? this.title,
      outputPath: outputPath,
      fileSizeBytes: fileSizeBytes,
      originalFileSizeBytes: originalFileSizeBytes,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pageCount: pageCount,
      folderId: clearFolder ? null : (folderId ?? this.folderId),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tool_type': toolType.name,
      'title': title,
      'output_path': outputPath,
      'file_size_bytes': fileSizeBytes,
      'original_file_size_bytes': originalFileSizeBytes,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'page_count': pageCount,
      'folder_id': folderId,
    };
  }

  factory ToolkitFile.fromMap(Map<String, Object?> map) {
    return ToolkitFile(
      id: map['id'] as int?,
      toolType: ToolkitToolType.values.byName(map['tool_type'] as String),
      title: map['title'] as String,
      outputPath: map['output_path'] as String,
      fileSizeBytes: map['file_size_bytes'] as int,
      originalFileSizeBytes: map['original_file_size_bytes'] as int?,
      isFavorite: (map['is_favorite'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      pageCount: map['page_count'] as int?,
      folderId: map['folder_id'] as int?,
    );
  }
}
