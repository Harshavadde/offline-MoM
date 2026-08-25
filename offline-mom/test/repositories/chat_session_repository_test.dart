import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/repositories/chat_session_repository.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ChatSessionRepository repository;
  late MeetingRepository meetingRepository;
  late DocumentRepository documentRepository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteChatSessionRepository(db);
    meetingRepository = SqfliteMeetingRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertMeeting() {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Standup',
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<int> insertDocument() {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'Report',
        originalFilename: 'report.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/report.pdf',
        status: DocumentStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  ChatSession buildSession({
    ChatScope scope = ChatScope.workspace,
    int? meetingId,
    int? documentId,
    String title = 'A conversation',
  }) {
    final now = DateTime(2026, 1, 1, 12);
    return ChatSession(
      id: null,
      title: title,
      scope: scope,
      createdAt: now,
      updatedAt: now,
      meetingId: meetingId,
      documentId: documentId,
    );
  }

  test('insert then getById round-trips a workspace-scoped session', () async {
    final id = await repository.insert(buildSession());
    final session = await repository.getById(id);

    expect(session, isNotNull);
    expect(session!.title, 'A conversation');
    expect(session.scope, ChatScope.workspace);
    expect(session.meetingId, isNull);
    expect(session.documentId, isNull);
  });

  test('insert then getById round-trips a meeting-scoped session', () async {
    final meetingId = await insertMeeting();
    final id = await repository.insert(buildSession(scope: ChatScope.meeting, meetingId: meetingId));
    final session = await repository.getById(id);

    expect(session!.scope, ChatScope.meeting);
    expect(session.meetingId, meetingId);
    expect(session.documentId, isNull);
  });

  test('insert then getById round-trips a document-scoped session', () async {
    final documentId = await insertDocument();
    final id =
        await repository.insert(buildSession(scope: ChatScope.document, documentId: documentId));
    final session = await repository.getById(id);

    expect(session!.scope, ChatScope.document);
    expect(session.documentId, documentId);
    expect(session.meetingId, isNull);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById(9999), isNull);
  });

  test('update persists a renamed title and touched updatedAt', () async {
    final id = await repository.insert(buildSession());
    final session = (await repository.getById(id))!;
    final renamed = session.copyWith(title: 'Renamed', updatedAt: DateTime(2026, 2, 2));

    await repository.update(renamed);

    final reloaded = await repository.getById(id);
    expect(reloaded!.title, 'Renamed');
    expect(reloaded.updatedAt, DateTime(2026, 2, 2));
  });

  test('delete removes the session', () async {
    final id = await repository.insert(buildSession());
    await repository.delete(id);
    expect(await repository.getById(id), isNull);
  });

  test('getAll orders by updatedAt descending', () async {
    final firstId = await repository.insert(
      buildSession(title: 'Older').copyWith(updatedAt: DateTime(2026, 1, 1)),
    );
    final secondId = await repository.insert(
      buildSession(title: 'Newer').copyWith(updatedAt: DateTime(2026, 1, 5)),
    );

    final all = await repository.getAll();
    expect(all.map((s) => s.id), [secondId, firstId]);
  });

  test('deleting the owning meeting cascades to its chat sessions', () async {
    final meetingId = await insertMeeting();
    final id = await repository.insert(buildSession(scope: ChatScope.meeting, meetingId: meetingId));

    await meetingRepository.delete(meetingId);

    expect(await repository.getById(id), isNull);
  });

  test('deleting the owning document cascades to its chat sessions', () async {
    final documentId = await insertDocument();
    final id =
        await repository.insert(buildSession(scope: ChatScope.document, documentId: documentId));

    await documentRepository.delete(documentId);

    expect(await repository.getById(id), isNull);
  });

  test('a new session defaults to isPinned false', () async {
    final id = await repository.insert(buildSession());
    final session = await repository.getById(id);
    expect(session!.isPinned, isFalse);
  });

  test('update persists a pinned session (Phase 2B "pin conversation")',
      () async {
    final id = await repository.insert(buildSession());
    final session = (await repository.getById(id))!;

    await repository.update(session.copyWith(isPinned: true));

    final reloaded = await repository.getById(id);
    expect(reloaded!.isPinned, isTrue);
  });
}
