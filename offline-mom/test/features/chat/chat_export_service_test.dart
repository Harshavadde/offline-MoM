import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/knowledge/content_type.dart';
import 'package:offline_mom/features/chat/presentation/providers/chat_export_service.dart';
import 'package:offline_mom/models/chat_message.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/models/chat_source_ref.dart';

void main() {
  const service = ChatExportService();

  ChatSession session({String title = 'A conversation'}) {
    final now = DateTime(2026, 1, 1);
    return ChatSession(
      id: 1,
      title: title,
      scope: ChatScope.workspace,
      createdAt: now,
      updatedAt: now,
    );
  }

  ChatMessage userMessage(String content) {
    return ChatMessage(
      id: 1,
      sessionId: 1,
      role: ChatMessageRole.user,
      content: content,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  ChatMessage assistantMessage(
    String content, {
    AnswerProvenance? provenance,
    List<ChatSourceRef> sources = const [],
  }) {
    return ChatMessage(
      id: 2,
      sessionId: 1,
      role: ChatMessageRole.assistant,
      content: content,
      createdAt: DateTime(2026, 1, 1),
      sourcesJson: ChatSourceRef.encodeList(sources),
      answerProvenance: provenance,
    );
  }

  group('buildPlainText', () {
    test('includes the session title and every message with a speaker label', () {
      final text = service.buildPlainText(session(title: 'Budget planning'), [
        userMessage('What is the budget?'),
        assistantMessage('The budget is approved.', provenance: AnswerProvenance.local),
      ]);

      expect(text, contains('Budget planning'));
      expect(text, contains('You: What is the budget?'));
      expect(text, contains('OfflineMoMAI: The budget is approved.'));
    });

    test('includes citations for a locally-grounded answer', () {
      final text = service.buildPlainText(session(), [
        assistantMessage(
          'The budget is approved.',
          provenance: AnswerProvenance.local,
          sources: const [
            ChatSourceRef(label: 'Budget Standup — Transcript', contentType: ContentType.transcript),
          ],
        ),
      ]);

      expect(text, contains('Sources: Budget Standup — Transcript'));
    });

    test('includes a general-knowledge provenance note and no citations', () {
      final text = service.buildPlainText(session(), [
        assistantMessage('Paris is the capital of France.', provenance: AnswerProvenance.generalKnowledge),
      ]);

      expect(text, contains("From the AI's general knowledge"));
      expect(text, isNot(contains('Sources:')));
    });

    test('falls back to a generic title when the session is null', () {
      final text = service.buildPlainText(null, [userMessage('hi')]);
      expect(text, contains('OfflineMoMAI chat'));
    });
  });

  group('buildMarkdown', () {
    test('renders the title as a heading and each message with a bold speaker label', () {
      final markdown = service.buildMarkdown(session(title: 'Budget planning'), [
        userMessage('What is the budget?'),
        assistantMessage('The budget is approved.'),
      ]);

      expect(markdown, contains('# Budget planning'));
      expect(markdown, contains('**You:**'));
      expect(markdown, contains('**OfflineMoMAI:**'));
      expect(markdown, contains('What is the budget?'));
      expect(markdown, contains('The budget is approved.'));
    });

    test('includes citations for a locally-grounded answer', () {
      final markdown = service.buildMarkdown(session(), [
        assistantMessage(
          'The budget is approved.',
          provenance: AnswerProvenance.local,
          sources: const [
            ChatSourceRef(label: 'Budget Standup — Transcript', contentType: ContentType.transcript),
          ],
        ),
      ]);

      expect(markdown, contains('Sources: Budget Standup — Transcript'));
    });
  });
}
