import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';
import 'package:offline_mom/services/retrieval/knowledge_chunk_filter.dart';

void main() {
  KnowledgeChunk chunk({
    ContentType contentType = ContentType.document,
    int? meetingId,
    int? documentId,
  }) {
    return KnowledgeChunk(
      id: null,
      contentType: contentType,
      sourceId: meetingId ?? documentId ?? 1,
      meetingId: meetingId,
      documentId: documentId,
      chunkIndex: 0,
      chunkText: 'text',
      embedding: const [0.1],
      createdAt: DateTime(2026, 1, 1),
    );
  }

  group('KnowledgeChunkFilter.workspace', () {
    test('matches document-owned and meeting-owned chunks alike', () {
      expect(
        KnowledgeChunkFilter.workspace.matches(chunk(documentId: 1)),
        isTrue,
      );
      expect(
        KnowledgeChunkFilter.workspace.matches(
          chunk(meetingId: 1, contentType: ContentType.transcript),
        ),
        isTrue,
      );
    });

    test('matches every content type', () {
      for (final type in ContentType.values) {
        expect(
          KnowledgeChunkFilter.workspace.matches(
            chunk(contentType: type, documentId: 1),
          ),
          isTrue,
          reason: 'workspace filter should match $type',
        );
      }
    });
  });

  group('KnowledgeChunkFilter.meetingsOnly', () {
    test('excludes document-owned chunks', () {
      expect(
        KnowledgeChunkFilter.meetingsOnly.matches(chunk(documentId: 1)),
        isFalse,
      );
    });

    test('matches meeting-owned chunks of any content type', () {
      expect(
        KnowledgeChunkFilter.meetingsOnly.matches(
          chunk(meetingId: 1, contentType: ContentType.note),
        ),
        isTrue,
      );
    });
  });

  group('KnowledgeChunkFilter.documentsOnly', () {
    test('excludes meeting-owned chunks', () {
      expect(
        KnowledgeChunkFilter.documentsOnly.matches(
          chunk(meetingId: 1, contentType: ContentType.transcript),
        ),
        isFalse,
      );
    });

    test('matches document-owned chunks', () {
      expect(
        KnowledgeChunkFilter.documentsOnly.matches(chunk(documentId: 1)),
        isTrue,
      );
    });
  });

  group('KnowledgeChunkFilter.forMeeting', () {
    test('matches only the specified meeting', () {
      final filter = KnowledgeChunkFilter.forMeeting(42);
      expect(
        filter.matches(chunk(meetingId: 42, contentType: ContentType.summary)),
        isTrue,
      );
      expect(
        filter.matches(chunk(meetingId: 7, contentType: ContentType.summary)),
        isFalse,
      );
    });

    test('excludes document-owned chunks even with no id collision', () {
      final filter = KnowledgeChunkFilter.forMeeting(1);
      expect(filter.matches(chunk(documentId: 1)), isFalse);
    });
  });

  group('KnowledgeChunkFilter.forDocument', () {
    test('matches only the specified document', () {
      final filter = KnowledgeChunkFilter.forDocument(9);
      expect(filter.matches(chunk(documentId: 9)), isTrue);
      expect(filter.matches(chunk(documentId: 10)), isFalse);
    });

    test('excludes meeting-owned chunks even with no id collision', () {
      final filter = KnowledgeChunkFilter.forDocument(1);
      expect(
        filter.matches(chunk(meetingId: 1, contentType: ContentType.transcript)),
        isFalse,
      );
    });
  });

  group('KnowledgeChunkFilter contentTypes', () {
    test('restricts to the given set of content types', () {
      const filter = KnowledgeChunkFilter(
        contentTypes: {ContentType.transcript, ContentType.summary},
      );
      expect(
        filter.matches(chunk(meetingId: 1, contentType: ContentType.transcript)),
        isTrue,
      );
      expect(
        filter.matches(chunk(meetingId: 1, contentType: ContentType.summary)),
        isTrue,
      );
      expect(
        filter.matches(chunk(meetingId: 1, contentType: ContentType.note)),
        isFalse,
      );
    });

    test('combines with ownerType and meetingId/documentId restrictions', () {
      const filter = KnowledgeChunkFilter(
        contentTypes: {ContentType.note},
        ownerType: KnowledgeChunkOwnerType.meeting,
        meetingId: 5,
      );
      expect(
        filter.matches(chunk(meetingId: 5, contentType: ContentType.note)),
        isTrue,
      );
      // Wrong content type.
      expect(
        filter.matches(chunk(meetingId: 5, contentType: ContentType.transcript)),
        isFalse,
      );
      // Wrong meeting.
      expect(
        filter.matches(chunk(meetingId: 6, contentType: ContentType.note)),
        isFalse,
      );
    });
  });
}
