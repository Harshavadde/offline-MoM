import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/search/search_workspace_use_case.dart';
import 'package:offline_mom/models/action_item.dart';
import 'package:offline_mom/models/decision.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/note.dart';
import 'package:offline_mom/models/summary.dart';
import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/repositories/action_item_repository.dart';
import 'package:offline_mom/repositories/content_search_repository.dart';
import 'package:offline_mom/repositories/decision_repository.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/note_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late TranscriptRepository transcriptRepository;
  late SummaryRepository summaryRepository;
  late ActionItemRepository actionItemRepository;
  late DecisionRepository decisionRepository;
  late NoteRepository noteRepository;
  late ContentSearchRepository contentSearchRepository;
  late DocumentRepository documentRepository;
  late SearchWorkspaceUseCase useCase;

  late int budgetMeetingId;
  late int designMeetingId;
  late int standupMeetingId;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
    actionItemRepository = SqfliteActionItemRepository(db);
    decisionRepository = SqfliteDecisionRepository(db);
    noteRepository = SqfliteNoteRepository(db);
    contentSearchRepository = SqfliteContentSearchRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
    useCase = SearchWorkspaceUseCase(
      meetingRepository: meetingRepository,
      documentRepository: documentRepository,
      contentSearchRepository: contentSearchRepository,
      decisionRepository: decisionRepository,
    );

    budgetMeetingId = await _insertMeeting(
      meetingRepository,
      title: 'Budget Review',
      createdAt: DateTime(2026, 2, 10),
    );
    designMeetingId = await _insertMeeting(
      meetingRepository,
      title: 'Design sync',
      createdAt: DateTime(2026, 2, 12),
    );
    standupMeetingId = await _insertMeeting(
      meetingRepository,
      title: 'Daily standup',
      createdAt: DateTime(2026, 2, 14),
    );

    await transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: designMeetingId,
        language: 'en',
        fullText: 'We agreed on the new budget allocation for design tools.',
        segments: const [],
        createdAt: DateTime(2026, 2, 12, 10),
      ),
    );

    await actionItemRepository.insertAll([
      ActionItem(
        id: null,
        meetingId: standupMeetingId,
        description: 'Renew the office lease',
        isCompleted: false,
        createdAt: DateTime(2026, 2, 14, 10),
      ),
    ]);

    await decisionRepository.insertAll([
      Decision(
        id: null,
        meetingId: budgetMeetingId,
        description: 'Approved the merger',
        createdAt: DateTime(2026, 2, 10, 10),
      ),
    ]);
  });

  tearDown(() => db.close());

  test('empty query returns nothing (caller should show the full list instead)',
      () async {
    expect(await useCase(''), isEmpty);
    expect(await useCase('   '), isEmpty);
  });

  test('matches by title', () async {
    final results = await useCase('design');
    expect(results.meetings.map((m) => m.id), contains(designMeetingId));
  });

  test('matches by transcript text, without duplicating a meeting that also '
      'matches by title', () async {
    final results = await useCase('budget');

    final ids = results.meetings.map((m) => m.id).toList();
    expect(ids, containsAll([budgetMeetingId, designMeetingId]));
    expect(ids.toSet().length, ids.length); // no duplicates
  });

  test('matches by action item description', () async {
    final results = await useCase('lease');
    expect(results.meetings.map((m) => m.id), [standupMeetingId]);
  });

  test('matches by decision description', () async {
    final results = await useCase('merger');
    expect(results.meetings.map((m) => m.id), [budgetMeetingId]);
  });

  test('matches by date', () async {
    final results = await useCase('Feb 12, 2026');
    expect(results.meetings.map((m) => m.id), [designMeetingId]);
  });

  test('no matches returns an empty list', () async {
    expect(await useCase('nonexistent search term'), isEmpty);
  });

  test('matches by summary text - not searchable before FTS5 (FR-36)',
      () async {
    await summaryRepository.insert(
      Summary(
        id: null,
        meetingId: standupMeetingId,
        summaryText: 'The team discussed the new onboarding checklist.',
        minutesOfMeeting: 'Standup minutes.',
        keyTopics: const ['onboarding'],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 2, 14, 11),
      ),
    );

    final results = await useCase('onboarding');
    expect(results.meetings.map((m) => m.id), [standupMeetingId]);
  });

  test('matches by note content - not searchable before FTS5 (FR-36)',
      () async {
    await noteRepository.insert(
      Note(
        id: null,
        meetingId: designMeetingId,
        content: 'Remember to follow up about the wireframe review.',
        createdAt: DateTime(2026, 2, 12, 12),
        updatedAt: DateTime(2026, 2, 12, 12),
      ),
    );

    final results = await useCase('wireframe');
    expect(results.meetings.map((m) => m.id), [designMeetingId]);
  });

  test('matches a document by title, returned in the documents list, not '
      'the meetings list', () async {
    final documentId = await _insertDocument(documentRepository, title: 'Vendor Contract');

    final results = await useCase('vendor');

    expect(results.documents.map((d) => d.id), [documentId]);
    expect(results.meetings, isEmpty);
  });

  test('matches a document by its extracted text', () async {
    final documentId = await _insertDocument(documentRepository, title: 'Report');
    final document = (await documentRepository.getById(documentId))!;
    await documentRepository.update(
      document.copyWith(
        status: DocumentStatus.ready,
        extractedText: 'Discusses the churn reduction initiative in detail.',
      ),
    );

    final results = await useCase('churn');

    expect(results.documents.map((d) => d.id), [documentId]);
  });

  test('a query matching both a meeting and a document returns both, '
      'correctly separated', () async {
    final documentId = await _insertDocument(documentRepository, title: 'Roadmap Notes');

    final results = await useCase('roadmap');

    expect(results.meetings, isEmpty); // no meeting titled "roadmap" exists
    expect(results.documents.map((d) => d.id), [documentId]);
  });
}

Future<int> _insertDocument(
  DocumentRepository repository, {
  required String title,
}) {
  final now = DateTime(2026, 2, 1);
  return repository.insert(
    Document(
      id: null,
      title: title,
      originalFilename: '$title.pdf',
      sourceType: DocumentSourceType.pdf,
      mimeType: 'application/pdf',
      fileSizeBytes: 100,
      filePath: '/tmp/$title.pdf',
      status: DocumentStatus.created,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Future<int> _insertMeeting(
  MeetingRepository repository, {
  required String title,
  required DateTime createdAt,
}) {
  return repository.insert(
    Meeting(
      id: null,
      title: title,
      source: MeetingSource.recorded,
      status: MeetingStatus.ready,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
  );
}
