import '../../core/utils/document_title.dart';
import '../../models/document.dart';
import '../../repositories/document_repository.dart';
import '../../services/documents/document_import_service.dart';

/// Orchestrates importing a document: pick a file, copy it into app
/// storage, create the [Document] row (status [DocumentStatus.created]).
/// Mirrors `ImportController`'s meeting-import orchestration
/// (lib/features/import/presentation/providers/import_providers.dart), kept
/// as its own use case (rather than inline in the controller, the way
/// meeting import does it) per the file this app's own architecture
/// planning already named (docs/v2/10-system-architecture.md).
class DocumentImportUseCase {
  DocumentImportUseCase({
    required DocumentRepository documentRepository,
    required DocumentImportService documentImportService,
  })  : _documentRepository = documentRepository,
        _documentImportService = documentImportService;

  final DocumentRepository _documentRepository;
  final DocumentImportService _documentImportService;

  /// Returns the new document's id, or null if the user cancelled the file
  /// picker. Throws [DocumentImportException] on an unsupported file type
  /// or copy failure - the caller (`DocumentImportController`) surfaces
  /// that message directly, same pattern as `ImportController`.
  Future<int?> call() async {
    final pickedPath = await _documentImportService.pickFile();
    if (pickedPath == null) return null;

    final prepared = await _documentImportService.prepareDocumentFile(pickedPath);
    final now = DateTime.now();

    return _documentRepository.insert(
      Document(
        id: null,
        title: deriveDocumentTitle(prepared.originalFilename),
        originalFilename: prepared.originalFilename,
        sourceType: prepared.sourceType,
        mimeType: prepared.sourceType.mimeType,
        fileSizeBytes: prepared.fileSizeBytes,
        filePath: prepared.filePath,
        status: DocumentStatus.created,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}
