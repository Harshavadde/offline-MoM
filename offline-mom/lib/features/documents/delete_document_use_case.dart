import 'dart:io';

import '../../repositories/document_repository.dart';
import '../../services/retrieval/vector_store.dart';

/// Deletes a document and its file - mirrors `DeleteMeetingUseCase`
/// (lib/features/meetings/delete_meeting_use_case.dart) exactly, including
/// the Phase 4B `VectorStore.invalidateCache()` call - see that use case's
/// doc comment for why it's needed alongside the database's `ON DELETE
/// CASCADE` (migration v6/v7/v8), not instead of it.
class DeleteDocumentUseCase {
  DeleteDocumentUseCase({
    required DocumentRepository documentRepository,
    required VectorStore vectorStore,
  })  : _documentRepository = documentRepository,
        _vectorStore = vectorStore;

  final DocumentRepository _documentRepository;
  final VectorStore _vectorStore;

  Future<void> call(int documentId) async {
    final document = await _documentRepository.getById(documentId);
    if (document == null) return;

    final file = File(document.filePath);
    if (await file.exists()) {
      await file.delete();
    }

    await _documentRepository.delete(documentId);
    _vectorStore.invalidateCache();
  }
}
