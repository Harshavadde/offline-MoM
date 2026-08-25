import 'package:sqflite/sqflite.dart';

import '../database/tables.dart';
import '../models/chat_message.dart';

/// Backed by `chat_messages` (migration v9, V2 Phase 2A) - see
/// docs/v2/12-database-design.md and ADR-025
/// (docs/v2/implementation/03-decisions.md).
abstract class ChatMessageRepository {
  Future<int> insert(ChatMessage message);

  /// Not called by [DeleteChatSessionUseCase] (deleting the owning session
  /// already cascades to its messages, per `chat_messages.session_id`'s
  /// `ON DELETE CASCADE`) - kept for the narrower case of clearing a
  /// session's messages while keeping the session itself, and for direct
  /// repository-level test coverage.
  Future<void> deleteForSession(int sessionId);

  /// Oldest first - conversation reading order.
  Future<List<ChatMessage>> getForSession(int sessionId);

  /// Deletes exactly one message (Phase 8B.1, Priority 3: per-message
  /// Delete) - unlike [deleteForSession], this never touches any other row.
  Future<void> deleteMessage(int id);

  /// Deletes [messageId] and every message after it in [sessionId] -
  /// backs "Edit" (Phase 8B.1, Priority 2): editing an earlier turn
  /// discards it and everything that followed before the edited text is
  /// resent, so the old (pre-edit) turn and its answer never coexist
  /// alongside the new one. Safe because message ids are assigned in the
  /// same order messages are ever inserted for a session (never
  /// back-dated), so "id >= messageId" is exactly "this message or a
  /// later one" - the same ordering [getForSession] already relies on.
  Future<void> deleteFromMessageOnward(int sessionId, int messageId);
}

class SqfliteChatMessageRepository implements ChatMessageRepository {
  SqfliteChatMessageRepository(this._db);

  final Database _db;

  @override
  Future<int> insert(ChatMessage message) {
    final map = message.toMap()..remove(ChatMessagesTable.id);
    return _db.insert(ChatMessagesTable.name, map);
  }

  @override
  Future<void> deleteForSession(int sessionId) async {
    await _db.delete(
      ChatMessagesTable.name,
      where: '${ChatMessagesTable.sessionId} = ?',
      whereArgs: [sessionId],
    );
  }

  @override
  Future<List<ChatMessage>> getForSession(int sessionId) async {
    final rows = await _db.query(
      ChatMessagesTable.name,
      where: '${ChatMessagesTable.sessionId} = ?',
      whereArgs: [sessionId],
      orderBy: '${ChatMessagesTable.createdAt} ASC, ${ChatMessagesTable.id} ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  @override
  Future<void> deleteMessage(int id) async {
    await _db.delete(
      ChatMessagesTable.name,
      where: '${ChatMessagesTable.id} = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteFromMessageOnward(int sessionId, int messageId) async {
    await _db.delete(
      ChatMessagesTable.name,
      where: '${ChatMessagesTable.sessionId} = ? AND ${ChatMessagesTable.id} >= ?',
      whereArgs: [sessionId, messageId],
    );
  }
}
