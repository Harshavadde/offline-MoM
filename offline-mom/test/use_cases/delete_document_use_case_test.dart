import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/delete_document_use_case.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/services/retrieval/knowledge_chunk_filter.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

/// See `delete_meeting_use_case_test.dart`'s identical spy for why every
/// method but [invalidateCache] just throws if ever called.
class _SpyVectorStore implements VectorStore {
  int invalidateCacheCallCount = 0;

  @override
  void invalidateCache() => invalidateCacheCallCount++;

  @override
  Future<void> add(KnowledgeChunk chunk) => throw UnimplementedError();

  @override
  Future<void> addAll(List<KnowledgeChunk> chunks) => throw UnimplementedError();

  @override
  Future<List<KnowledgeChunk>> similaritySearch(
    List<double> queryEmbedding, {
    required int k,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  }) =>
      throw UnimplementedError();
}

void main() {
  late Database db;
  late DocumentRepository documentRepository;
  late _SpyVectorStore vectorStore;
  late DeleteDocumentUseCase useCase;
  late Directory tempDir;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
    vectorStore = _SpyVectorStore();
    useCase = DeleteDocumentUseCase(
      documentRepository: documentRepository,
      vectorStore: vectorStore,
    );
    tempDir = await Directory.systemTemp.createTemp('delete_document_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> insertDocument(String filePath) {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'To be deleted',
        originalFilename: 'doc.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: filePath,
        status: DocumentStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('deletes the document row and its file', () async {
    final file = File('${tempDir.path}/document.pdf');
    await file.writeAsBytes([1, 2, 3]);

    final documentId = await insertDocument(file.path);

    await useCase(documentId);

    expect(await documentRepository.getById(documentId), isNull);
    expect(await file.exists(), isFalse);
  });

  test('deleting a document whose file is already gone does not throw',
      () async {
    final missingPath = '${tempDir.path}/already_gone.pdf';
    final documentId = await insertDocument(missingPath);

    await useCase(documentId);

    expect(await documentRepository.getById(documentId), isNull);
  });

  test('deleting an unknown document id does not throw', () async {
    await useCase(9999);
  });

  test(
      'invalidates the vector store cache on a real delete, so a deleted '
      "document's chunks can't keep surfacing in retrieval/search for the "
      'rest of the app session (Phase 4B)', () async {
    final documentId = await insertDocument('${tempDir.path}/document.pdf');

    await useCase(documentId);

    expect(vectorStore.invalidateCacheCallCount, 1);
  });

  test('does not invalidate the vector store cache for an unknown document '
      'id - nothing was actually deleted', () async {
    await useCase(9999);

    expect(vectorStore.invalidateCacheCallCount, 0);
  });
}
