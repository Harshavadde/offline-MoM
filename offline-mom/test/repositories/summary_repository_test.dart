import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/summary.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

/// Covers [SummaryRepository.getForDocument] and the polymorphic
/// meeting/document ownership migration v6 introduced (ADR-005,
/// docs/v2/implementation/03-decisions.md) - `getForMeeting` itself is
/// already exercised indirectly by generate_meeting_summary_use_case_test.dart,
/// so this file focuses on the document side and the CHECK constraint that
/// keeps the two mutually exclusive.
void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late DocumentRepository documentRepository;
  late SummaryRepository summaryRepository;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    documentRepository = SqfliteDocumentRepository(db);
    summaryRepository = SqfliteSummaryRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertDocument() {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'Report',
        originalFilename: 'report.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 1024,
        filePath: '/tmp/report.pdf',
        status: DocumentStatus.summarizing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<int> insertMeeting() {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Standup',
        source: MeetingSource.recorded,
        status: MeetingStatus.summarizing,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('insert then getForDocument returns the document-owned summary',
      () async {
    final documentId = await insertDocument();

    await summaryRepository.insert(
      Summary(
        id: null,
        documentId: documentId,
        summaryText: 'A concise summary.',
        minutesOfMeeting: '',
        keyTopics: const ['budget', 'timeline'],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 1, 1, 12),
      ),
    );

    final summary = await summaryRepository.getForDocument(documentId);
    expect(summary, isNotNull);
    expect(summary!.summaryText, 'A concise summary.');
    expect(summary.meetingId, isNull);
    expect(summary.documentId, documentId);
  });

  test('getForDocument returns null when no summary exists', () async {
    final documentId = await insertDocument();
    expect(await summaryRepository.getForDocument(documentId), isNull);
  });

  test('a document-owned summary is invisible to getForMeeting and vice versa',
      () async {
    final documentId = await insertDocument();
    final meetingId = await insertMeeting();

    await summaryRepository.insert(
      Summary(
        id: null,
        documentId: documentId,
        summaryText: 'Document summary.',
        minutesOfMeeting: '',
        keyTopics: const [],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 1, 1),
      ),
    );
    await summaryRepository.insert(
      Summary(
        id: null,
        meetingId: meetingId,
        summaryText: 'Meeting summary.',
        minutesOfMeeting: 'Minutes.',
        keyTopics: const [],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 1, 1),
      ),
    );

    expect(await summaryRepository.getForMeeting(meetingId), isNotNull);
    expect((await summaryRepository.getForMeeting(meetingId))!.summaryText,
        'Meeting summary.');
    expect(await summaryRepository.getForDocument(documentId), isNotNull);
    expect((await summaryRepository.getForDocument(documentId))!.summaryText,
        'Document summary.');
  });

  test('deleting a document cascades to its summary', () async {
    final documentId = await insertDocument();
    await summaryRepository.insert(
      Summary(
        id: null,
        documentId: documentId,
        summaryText: 'Will be cascaded away.',
        minutesOfMeeting: '',
        keyTopics: const [],
        modelUsed: 'test-model',
        generatedAt: DateTime(2026, 1, 1),
      ),
    );

    await documentRepository.delete(documentId);

    expect(await summaryRepository.getForDocument(documentId), isNull);
  });

  test(
      'the database rejects a summary row with both meeting_id and '
      'document_id set (CHECK constraint, ADR-005)', () async {
    final meetingId = await insertMeeting();
    final documentId = await insertDocument();

    await expectLater(
      db.insert('summaries', {
        'meeting_id': meetingId,
        'document_id': documentId,
        'summary_text': 'Invalid: both owners set.',
        'minutes_of_meeting': '',
        'key_topics_json': '[]',
        'model_used': 'test-model',
        'generated_at': DateTime(2026, 1, 1).toIso8601String(),
      }),
      throwsA(anything),
    );
  });

  test(
      'the database rejects a summary row with neither meeting_id nor '
      'document_id set (CHECK constraint, ADR-005)', () async {
    await expectLater(
      db.insert('summaries', {
        'meeting_id': null,
        'document_id': null,
        'summary_text': 'Invalid: no owner set.',
        'minutes_of_meeting': '',
        'key_topics_json': '[]',
        'model_used': 'test-model',
        'generated_at': DateTime(2026, 1, 1).toIso8601String(),
      }),
      throwsA(anything),
    );
  });
}
