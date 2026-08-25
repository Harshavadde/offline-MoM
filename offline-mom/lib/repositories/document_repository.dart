import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/document.dart';

/// Contract for reading/writing [Document] rows - mirrors
/// [MeetingRepository]'s shape exactly (lib/repositories/meeting_repository.dart).
abstract class DocumentRepository {
  Future<int> insert(Document document);
  Future<void> update(Document document);
  Future<void> delete(int id);
  Future<Document?> getById(int id);

  /// Every document, most recently created first. **Does not populate
  /// [Document.extractedText]** (Phase 3B, ADR-030,
  /// docs/v2/implementation/03-decisions.md; R-22,
  /// docs/v2/implementation/04-risk-register.md) - list views (the only
  /// current callers) never render it, and it can be an entire document's
  /// extracted body, so this method skips fetching it entirely rather than
  /// paying that cost on every list load. Use [getById]/[getByIds] for the
  /// real value.
  Future<List<Document>> getAll();

  /// Fetches multiple documents by id, most recent first - mirrors
  /// [MeetingRepository.getByIds]'s purpose exactly: resolving a set of
  /// ids gathered from search into full rows in one query instead of one
  /// query per id.
  Future<List<Document>> getByIds(Iterable<int> ids);

  /// Documents in [folderId], most recently created first - `null` means
  /// "All Documents" (every document with no folder assigned, the
  /// default/unfiled view - V2.2 Production Hardening, Priority 2). Same
  /// "don't fetch extracted_text" discipline as [getAll] (Phase 3B) for
  /// the same reason: this is a list-view query, never a detail view.
  Future<List<Document>> getInFolder(int? folderId);

  /// Moves [documentId] into [folderId] (or back to "All Documents" -
  /// unfiled - when null). A thin, direct update - not folded into
  /// [update] (which would require callers to fetch, mutate, and write
  /// back a whole [Document] just to change one column) - mirrors
  /// [ActionItemRepository.setCompleted]'s identical "one focused column
  /// update, not a full round-trip" reasoning.
  Future<void> moveToFolder(int documentId, int? folderId);

  /// [documentId]'s current folder, or null if it's in "All Documents" -
  /// the read counterpart to [moveToFolder], for a caller (the "Move to
  /// folder" dialog) that needs to know the current value without
  /// fetching a whole [Document] (whose model deliberately doesn't carry
  /// this column - see [DocumentsTable.folderId]'s own doc comment).
  Future<int?> getFolderId(int documentId);
}

class SqfliteDocumentRepository implements DocumentRepository {
  SqfliteDocumentRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(Document document) {
    final map = document.toMap()..remove(DocumentsTable.id);
    return _db.insert(DocumentsTable.name, map);
  }

  @override
  Future<void> update(Document document) async {
    await _db.update(
      DocumentsTable.name,
      document.toMap(),
      where: '${DocumentsTable.id} = ?',
      whereArgs: [document.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      DocumentsTable.name,
      where: '${DocumentsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Document?> getById(int id) async {
    final rows = await _db.query(
      DocumentsTable.name,
      where: '${DocumentsTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Document.fromMap(rows.first);
  }

  @override
  Future<List<Document>> getAll() async {
    // Excludes `extracted_text` (Phase 3B) - every caller of `getAll()`
    // (`documentListProvider`/`DocumentsScreen`, `chatEligibleDocumentsProvider`
    // /the in-chat document picker) only ever renders a list tile
    // (title/status/size/updated), never the extracted text itself; a
    // document's full extracted text can be large (the whole body of a
    // PDF/DOCX), so fetching it for every row on every list load - a
    // screen visited far more often than any single document's detail
    // view - is real, unnecessary I/O. `Document.fromMap` already treats a
    // missing `extracted_text` key as `null` (the same as it does for a
    // genuinely-null column value), so this doesn't change the model's
    // shape, only what `getAll()` specifically populates - a caller that
    // needs the real text uses `getById`/`getByIds`, unaffected by this.
    final rows = await _db.query(
      DocumentsTable.name,
      columns: const [
        DocumentsTable.id,
        DocumentsTable.title,
        DocumentsTable.originalFilename,
        DocumentsTable.sourceType,
        DocumentsTable.mimeType,
        DocumentsTable.fileSizeBytes,
        DocumentsTable.filePath,
        DocumentsTable.status,
        DocumentsTable.errorMessage,
        DocumentsTable.createdAt,
        DocumentsTable.updatedAt,
      ],
      orderBy: '${DocumentsTable.createdAt} DESC',
    );
    return rows.map(Document.fromMap).toList();
  }

  @override
  Future<List<Document>> getByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db.query(
      DocumentsTable.name,
      where: '${DocumentsTable.id} IN ($placeholders)',
      whereArgs: ids.toList(),
      orderBy: '${DocumentsTable.createdAt} DESC',
    );
    return rows.map(Document.fromMap).toList();
  }

  @override
  Future<List<Document>> getInFolder(int? folderId) async {
    // Same excluded-columns list as getAll() (Phase 3B, ADR-030) - this is
    // the same list-view use case, just filtered.
    final rows = await _db.query(
      DocumentsTable.name,
      columns: const [
        DocumentsTable.id,
        DocumentsTable.title,
        DocumentsTable.originalFilename,
        DocumentsTable.sourceType,
        DocumentsTable.mimeType,
        DocumentsTable.fileSizeBytes,
        DocumentsTable.filePath,
        DocumentsTable.status,
        DocumentsTable.errorMessage,
        DocumentsTable.createdAt,
        DocumentsTable.updatedAt,
      ],
      where: folderId == null
          ? '${DocumentsTable.folderId} IS NULL'
          : '${DocumentsTable.folderId} = ?',
      whereArgs: folderId == null ? null : [folderId],
      orderBy: '${DocumentsTable.createdAt} DESC',
    );
    return rows.map(Document.fromMap).toList();
  }

  @override
  Future<void> moveToFolder(int documentId, int? folderId) async {
    await _db.update(
      DocumentsTable.name,
      {DocumentsTable.folderId: folderId},
      where: '${DocumentsTable.id} = ?',
      whereArgs: [documentId],
    );
  }

  @override
  Future<int?> getFolderId(int documentId) async {
    final rows = await _db.query(
      DocumentsTable.name,
      columns: const [DocumentsTable.folderId],
      where: '${DocumentsTable.id} = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first[DocumentsTable.folderId] as int?;
  }
}
