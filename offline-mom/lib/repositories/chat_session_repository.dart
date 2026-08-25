import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/chat_session.dart';

/// Backed by `chat_sessions` (migration v9, V2 Phase 2A) - see
/// docs/v2/12-database-design.md and ADR-025
/// (docs/v2/implementation/03-decisions.md).
abstract class ChatSessionRepository {
  Future<int> insert(ChatSession session);
  Future<void> update(ChatSession session);
  Future<void> delete(int id);
  Future<ChatSession?> getById(int id);

  /// Most-recently-updated conversation first - the order the chat history
  /// list shows conversations in (mirrors `MeetingRepository.getAll`'s
  /// most-recent-first convention).
  Future<List<ChatSession>> getAll();
}

class SqfliteChatSessionRepository implements ChatSessionRepository {
  SqfliteChatSessionRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(ChatSession session) {
    final map = session.toMap()..remove(ChatSessionsTable.id);
    return _db.insert(ChatSessionsTable.name, map);
  }

  @override
  Future<void> update(ChatSession session) async {
    await _db.update(
      ChatSessionsTable.name,
      session.toMap(),
      where: '${ChatSessionsTable.id} = ?',
      whereArgs: [session.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      ChatSessionsTable.name,
      where: '${ChatSessionsTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<ChatSession?> getById(int id) async {
    final rows = await _db.query(
      ChatSessionsTable.name,
      where: '${ChatSessionsTable.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatSession.fromMap(rows.first);
  }

  @override
  Future<List<ChatSession>> getAll() async {
    final rows = await _db.query(
      ChatSessionsTable.name,
      orderBy: '${ChatSessionsTable.updatedAt} DESC',
    );
    return rows.map(ChatSession.fromMap).toList();
  }
}
