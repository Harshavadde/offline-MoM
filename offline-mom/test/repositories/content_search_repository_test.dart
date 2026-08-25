import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/action_item.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/note.dart';
import 'package:offline_mom/models/summary.dart';
import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/repositories/action_item_repository.dart';
import 'package:offline_mom/repositories/content_search_repository.dart';
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
  late NoteRepository noteRepository;
  late DocumentRepository documentRepository;
  late ContentSearchRepository contentSearchRepository;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
    actionItemRepository = SqfliteActionItemRepository(db);
    noteRepository = SqfliteNoteRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
    contentSearchRepository = SqfliteContentSearchRepository(db);
  });

  tearDown(() => db.close());

  Future<Set<int>> searchMeetingIds(String query) async {
    return (await contentSearchRepository.search(query)).meetingIds;
  }

  Future<Set<int>> searchDocumentIds(String query) async {
    return (await contentSearchRepository.search(query)).documentIds;
  }

  Future<int> insertMeeting(String title) {
    final now = DateTime(2026, 3, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: title,
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// [extractedText], if given, is applied via a follow-up `update()` call
  /// rather than set at insert time - this matters because the
  /// `document_text_fts_au` trigger (migration v6) only fires on UPDATE OF
  /// extracted_text, matching the real pipeline (`ExtractDocumentTextUseCase`
  /// always populates it via an update, never at the initial insert).
  /// Setting it directly on insert would silently skip FTS indexing.
  Future<int> insertDocument(String title, {String? extractedText}) async {
    final now = DateTime(2026, 3, 1);
    final id = await documentRepository.insert(
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
    if (extractedText != null) {
      final document = (await documentRepository.getById(id))!;
      await documentRepository.update(
        document.copyWith(status: DocumentStatus.ready, extractedText: extractedText),
      );
    }
    return id;
  }

  test('matches by meeting title, including a partial/prefix word', () async {
    final id = await insertMeeting('Quarterly Budget Review');

    expect(await searchMeetingIds('budget'), {id});
    expect(await searchMeetingIds('budg'), {id});
    expect(await searchMeetingIds('nonexistent'), isEmpty);
  });

  test('matches by transcript text', () async {
    final id = await insertMeeting('Standup');
    await transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: id,
        language: 'en',
        fullText: 'We reviewed the deployment pipeline issues.',
        segments: const [],
        createdAt: DateTime(2026, 3, 1, 10),
      ),
    );

    expect(await searchMeetingIds('pipeline'), {id});
  });

  test('matches by summary text, minutes of meeting, and key topics', () async {
    final summaryId = await insertMeeting('Design Sync');
    await summaryRepository.insert(
      Summary(
        id: null,
        meetingId: summaryId,
        summaryText: 'Agreed on the new onboarding flow.',
        minutesOfMeeting: 'Formally approved the wireframes.',
        keyTopics: const ['onboarding', 'wireframes'],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 3, 1, 11),
      ),
    );

    expect(await searchMeetingIds('onboarding'), {summaryId});
    expect(await searchMeetingIds('wireframes'), {summaryId});
    expect(await searchMeetingIds('approved'), {summaryId});
  });

  test('matches by action item description', () async {
    final id = await insertMeeting('Ops Review');
    await actionItemRepository.insert(
      ActionItem(
        id: null,
        meetingId: id,
        description: 'Renew the office lease',
        isCompleted: false,
        createdAt: DateTime(2026, 3, 1, 12),
      ),
    );

    expect(await searchMeetingIds('lease'), {id});
  });

  test('matches by note content - a gap the old LIKE-based search never '
      'covered at all', () async {
    final id = await insertMeeting('Client Call');
    await noteRepository.insert(
      Note(
        id: null,
        meetingId: id,
        content: 'Client asked about invoicing timelines.',
        createdAt: DateTime(2026, 3, 1, 13),
        updatedAt: DateTime(2026, 3, 1, 13),
      ),
    );

    expect(await searchMeetingIds('invoicing'), {id});
  });

  test('a meeting matching in more than one content type is returned once',
      () async {
    final id = await insertMeeting('Budget Planning');
    await transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: id,
        language: 'en',
        fullText: 'The budget was the main topic today.',
        segments: const [],
        createdAt: DateTime(2026, 3, 1, 10),
      ),
    );

    final results = await searchMeetingIds('budget');
    expect(results, {id});
  });

  test('empty or whitespace-only query returns no results', () async {
    await insertMeeting('Anything');
    expect(await searchMeetingIds(''), isEmpty);
    expect(await searchMeetingIds('   '), isEmpty);
  });

  test('special characters that are meaningful in FTS5 syntax do not throw '
      'and are simply ignored as separators', () async {
    final id = await insertMeeting('Q&A Session');
    // "&", quotes, and parentheses are all meaningful in raw FTS5 query
    // syntax - this asserts they're treated as plain token separators
    // (per _buildMatchQuery's doc comment) rather than either throwing or
    // being interpreted as FTS5 operators.
    expect(
      await searchMeetingIds('"Q&A" (session)!!!'),
      {id},
    );
  });

  test('editing a note re-syncs the index: old content stops matching, new '
      'content starts matching', () async {
    final id = await insertMeeting('Retro');
    await noteRepository.insert(
      Note(
        id: null,
        meetingId: id,
        content: 'Original wording about velocity.',
        createdAt: DateTime(2026, 3, 1, 14),
        updatedAt: DateTime(2026, 3, 1, 14),
      ),
    );

    expect(await searchMeetingIds('velocity'), {id});

    final notes = await noteRepository.getForMeeting(id);
    await noteRepository.update(notes.single.copyWith(content: 'Updated wording about morale.'));

    expect(await searchMeetingIds('velocity'), isEmpty);
    expect(await searchMeetingIds('morale'), {id});
  });

  test('deleting an action item removes it from the index', () async {
    final id = await insertMeeting('Cleanup');
    final actionItemId = await actionItemRepository.insert(
      ActionItem(
        id: null,
        meetingId: id,
        description: 'Archive the old repository',
        isCompleted: false,
        createdAt: DateTime(2026, 3, 1, 15),
      ),
    );

    expect(await searchMeetingIds('archive'), {id});

    await actionItemRepository.delete(actionItemId);

    expect(await searchMeetingIds('archive'), isEmpty);
  });

  test('deleting a meeting removes every one of its indexed rows via cascade',
      () async {
    final id = await insertMeeting('Doomed Meeting');
    await transcriptRepository.insert(
      Transcript(
        id: null,
        meetingId: id,
        language: 'en',
        fullText: 'Some transcript text about a unique keyword: zorbex.',
        segments: const [],
        createdAt: DateTime(2026, 3, 1, 16),
      ),
    );
    await noteRepository.insert(
      Note(
        id: null,
        meetingId: id,
        content: 'A note mentioning zorbex too.',
        createdAt: DateTime(2026, 3, 1, 16),
        updatedAt: DateTime(2026, 3, 1, 16),
      ),
    );

    expect(await searchMeetingIds('zorbex'), {id});

    await meetingRepository.delete(id);

    expect(await searchMeetingIds('zorbex'), isEmpty);
    expect(await searchMeetingIds('doomed'), isEmpty);
  });

  test('matches by document title', () async {
    final id = await insertDocument('Vendor Contract');

    expect(await searchDocumentIds('vendor'), {id});
    expect(await searchMeetingIds('vendor'), isEmpty);
  });

  test('matches by document extracted text', () async {
    final id = await insertDocument(
      'Report',
      extractedText: 'The migration to the new platform completed on schedule.',
    );

    expect(await searchDocumentIds('migration'), {id});
  });

  test('matches by a document-owned summary', () async {
    final id = await insertDocument('Report');
    await summaryRepository.insert(
      Summary(
        id: null,
        documentId: id,
        summaryText: 'Highlights the churn reduction initiative.',
        minutesOfMeeting: '',
        keyTopics: const ['churn'],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 3, 1),
      ),
    );

    expect(await searchDocumentIds('churn'), {id});
  });

  test('a query matching both a meeting and a document returns both, '
      'correctly partitioned', () async {
    final meetingId = await insertMeeting('Roadmap Sync');
    final documentId = await insertDocument('Roadmap Draft');

    final results = await contentSearchRepository.search('roadmap');

    expect(results.meetingIds, {meetingId});
    expect(results.documentIds, {documentId});
  });

  test('exposes which content type matched, for Phase 2B Workspace Search '
      'grouping/filtering (ADR-028)', () async {
    final id = await insertMeeting('Retro');
    await noteRepository.insert(
      Note(
        id: null,
        meetingId: id,
        content: 'Discussed velocity trends.',
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
      ),
    );

    final results = await contentSearchRepository.search('velocity');

    expect(results.meetingContentTypes[id], {'note'});
  });

  test('a meeting matching by both title and note content exposes both '
      'content types', () async {
    final id = await insertMeeting('Zorbex Review');
    await noteRepository.insert(
      Note(
        id: null,
        meetingId: id,
        content: 'Mentions zorbex again.',
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
      ),
    );

    final results = await contentSearchRepository.search('zorbex');

    expect(results.meetingContentTypes[id], {'meeting', 'note'});
  });

  test('a document match exposes its content type in documentContentTypes',
      () async {
    final id = await insertDocument('Vendor Contract');

    final results = await contentSearchRepository.search('vendor');

    expect(results.documentContentTypes[id], {'document'});
  });

  test('renaming a document re-syncs the index: old title stops matching, '
      'new title starts matching', () async {
    final id = await insertDocument('Old Title');

    expect(await searchDocumentIds('old'), {id});

    final document = (await documentRepository.getById(id))!;
    await documentRepository.update(document.copyWith(title: 'New Title'));

    expect(await searchDocumentIds('old'), isEmpty);
    expect(await searchDocumentIds('new'), {id});
  });

  test('deleting a document removes its title, text and summary from the '
      'index via cascade', () async {
    final id = await insertDocument('Zorbex Filing', extractedText: 'Body mentions zorbex too.');
    await summaryRepository.insert(
      Summary(
        id: null,
        documentId: id,
        summaryText: 'Summary mentions zorbex as well.',
        minutesOfMeeting: '',
        keyTopics: const [],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 3, 1),
      ),
    );

    expect(await searchDocumentIds('zorbex'), {id});

    await documentRepository.delete(id);

    expect(await searchDocumentIds('zorbex'), isEmpty);
  });
}
