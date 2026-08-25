// Phase 4B: `KnowledgeChunk`'s meetingId/documentId-exactly-one-set
// invariant used to be an `assert`, which `flutter build --release` strips
// entirely - a violation would have built silently in release instead of
// failing loudly. Converted to a real, always-enforced `ArgumentError` (see
// lib/models/knowledge_chunk.dart's doc comment); these tests guard that
// conversion, not just the shape it enforces.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/knowledge_chunk.dart';

void main() {
  KnowledgeChunk build({int? meetingId, int? documentId}) => KnowledgeChunk(
        id: null,
        contentType: ContentType.transcript,
        sourceId: 1,
        meetingId: meetingId,
        documentId: documentId,
        chunkIndex: 0,
        chunkText: 'some text',
        embedding: const [0.1, 0.2, 0.3],
        createdAt: DateTime(2026, 1, 1),
      );

  test('constructs successfully with only meetingId set', () {
    expect(() => build(meetingId: 1), returnsNormally);
  });

  test('constructs successfully with only documentId set', () {
    expect(() => build(documentId: 1), returnsNormally);
  });

  test('throws when neither meetingId nor documentId is set - in every '
      'build mode, not just debug (this used to be an assert)', () {
    expect(() => build(), throwsArgumentError);
  });

  test('throws when both meetingId and documentId are set - in every build '
      'mode, not just debug (this used to be an assert)', () {
    expect(() => build(meetingId: 1, documentId: 2), throwsArgumentError);
  });
}
