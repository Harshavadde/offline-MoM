import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/chat_message.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/repositories/chat_message_repository.dart';
import 'package:offline_mom/repositories/chat_session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ChatMessageRepository repository;
  late ChatSessionRepository sessionRepository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteChatMessageRepository(db);
    sessionRepository = SqfliteChatSessionRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertSession() {
    final now = DateTime(2026, 1, 1);
    return sessionRepository.insert(
      ChatSession(
        id: null,
        title: 'A conversation',
        scope: ChatScope.workspace,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  ChatMessage buildMessage({
    required int sessionId,
    ChatMessageRole role = ChatMessageRole.user,
    String content = 'Hello?',
    String? sourcesJson,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: null,
      sessionId: sessionId,
      role: role,
      content: content,
      createdAt: createdAt ?? DateTime(2026, 1, 1, 12),
      sourcesJson: sourcesJson,
    );
  }

  test('insert then getForSession round-trips a user message', () async {
    final sessionId = await insertSession();
    await repository.insert(buildMessage(sessionId: sessionId));

    final messages = await repository.getForSession(sessionId);
    expect(messages, hasLength(1));
    expect(messages.single.role, ChatMessageRole.user);
    expect(messages.single.content, 'Hello?');
    expect(messages.single.sourcesJson, isNull);
  });

  test('insert then getForSession round-trips an assistant message with '
      'sourcesJson', () async {
    final sessionId = await insertSession();
    const sourcesJson = '[{"label":"Standup — Transcript"}]';
    await repository.insert(
      buildMessage(
        sessionId: sessionId,
        role: ChatMessageRole.assistant,
        content: 'The answer is...',
        sourcesJson: sourcesJson,
      ),
    );

    final messages = await repository.getForSession(sessionId);
    expect(messages.single.role, ChatMessageRole.assistant);
    expect(messages.single.sourcesJson, sourcesJson);
  });

  test('getForSession returns messages oldest first', () async {
    final sessionId = await insertSession();
    await repository.insert(
      buildMessage(sessionId: sessionId, content: 'first', createdAt: DateTime(2026, 1, 1, 10)),
    );
    await repository.insert(
      buildMessage(sessionId: sessionId, content: 'second', createdAt: DateTime(2026, 1, 1, 11)),
    );

    final messages = await repository.getForSession(sessionId);
    expect(messages.map((m) => m.content), ['first', 'second']);
  });

  test('getForSession only returns messages for that session', () async {
    final sessionA = await insertSession();
    final sessionB = await insertSession();
    await repository.insert(buildMessage(sessionId: sessionA, content: 'A'));
    await repository.insert(buildMessage(sessionId: sessionB, content: 'B'));

    final messages = await repository.getForSession(sessionA);
    expect(messages.map((m) => m.content), ['A']);
  });

  test('deleteForSession removes only that session\'s messages', () async {
    final sessionA = await insertSession();
    final sessionB = await insertSession();
    await repository.insert(buildMessage(sessionId: sessionA, content: 'A'));
    await repository.insert(buildMessage(sessionId: sessionB, content: 'B'));

    await repository.deleteForSession(sessionA);

    expect(await repository.getForSession(sessionA), isEmpty);
    expect(await repository.getForSession(sessionB), hasLength(1));
  });

  test('deleting the owning session cascades to its messages', () async {
    final sessionId = await insertSession();
    await repository.insert(buildMessage(sessionId: sessionId));

    await sessionRepository.delete(sessionId);

    expect(await repository.getForSession(sessionId), isEmpty);
  });

  group('deleteMessage (Phase 8B.1, per-message Delete)', () {
    test('removes only that one message, leaving its neighbors', () async {
      final sessionId = await insertSession();
      await repository.insert(
        buildMessage(sessionId: sessionId, content: 'first', createdAt: DateTime(2026, 1, 1, 10)),
      );
      await repository.insert(
        buildMessage(sessionId: sessionId, content: 'second', createdAt: DateTime(2026, 1, 1, 11)),
      );
      await repository.insert(
        buildMessage(sessionId: sessionId, content: 'third', createdAt: DateTime(2026, 1, 1, 12)),
      );

      final middle = (await repository.getForSession(sessionId))[1];
      await repository.deleteMessage(middle.id!);

      final remaining = await repository.getForSession(sessionId);
      expect(remaining.map((m) => m.content), ['first', 'third']);
    });
  });

  group('deleteFromMessageOnward (Phase 8B.1, "Edit" truncation)', () {
    test('removes the given message and every message after it, keeping '
        'everything before it', () async {
      final sessionId = await insertSession();
      await repository.insert(
        buildMessage(sessionId: sessionId, content: 'q1', createdAt: DateTime(2026, 1, 1, 10)),
      );
      await repository.insert(
        buildMessage(
          sessionId: sessionId,
          role: ChatMessageRole.assistant,
          content: 'a1',
          createdAt: DateTime(2026, 1, 1, 10, 1),
        ),
      );
      await repository.insert(
        buildMessage(sessionId: sessionId, content: 'q2 (to be edited)', createdAt: DateTime(2026, 1, 1, 11)),
      );
      await repository.insert(
        buildMessage(
          sessionId: sessionId,
          role: ChatMessageRole.assistant,
          content: 'a2',
          createdAt: DateTime(2026, 1, 1, 11, 1),
        ),
      );

      final editedMessage = (await repository.getForSession(sessionId))[2];
      await repository.deleteFromMessageOnward(sessionId, editedMessage.id!);

      final remaining = await repository.getForSession(sessionId);
      expect(remaining.map((m) => m.content), ['q1', 'a1']);
    });

    test('never touches another session\'s messages', () async {
      final sessionA = await insertSession();
      final sessionB = await insertSession();
      await repository.insert(buildMessage(sessionId: sessionA, content: 'A1'));
      final aMessage = (await repository.getForSession(sessionA)).single;
      await repository.insert(buildMessage(sessionId: sessionB, content: 'B1'));

      await repository.deleteFromMessageOnward(sessionA, aMessage.id!);

      expect(await repository.getForSession(sessionA), isEmpty);
      expect(await repository.getForSession(sessionB), hasLength(1));
    });
  });
}
