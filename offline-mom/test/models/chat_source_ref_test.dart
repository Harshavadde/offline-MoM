import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/models/chat_source_ref.dart';

void main() {
  test('encodeList returns null for an empty list', () {
    expect(ChatSourceRef.encodeList(const []), isNull);
  });

  test('decodeList returns an empty list for null or empty input', () {
    expect(ChatSourceRef.decodeList(null), isEmpty);
    expect(ChatSourceRef.decodeList(''), isEmpty);
  });

  test('encodeList then decodeList round-trips every field', () {
    const sources = [
      ChatSourceRef(
        label: 'Standup — Transcript',
        contentType: ContentType.transcript,
        meetingId: 1,
      ),
      ChatSourceRef(
        label: 'Report.pdf',
        contentType: ContentType.document,
        documentId: 2,
      ),
    ];

    final json = ChatSourceRef.encodeList(sources);
    final decoded = ChatSourceRef.decodeList(json);

    expect(decoded, hasLength(2));
    expect(decoded[0].label, 'Standup — Transcript');
    expect(decoded[0].contentType, ContentType.transcript);
    expect(decoded[0].meetingId, 1);
    expect(decoded[0].documentId, isNull);
    expect(decoded[1].label, 'Report.pdf');
    expect(decoded[1].contentType, ContentType.document);
    expect(decoded[1].documentId, 2);
    expect(decoded[1].meetingId, isNull);
  });
}
