import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../models/chat_message.dart';
import '../../../../models/chat_session.dart';
import '../../../../models/chat_source_ref.dart';

/// Builds an exportable transcript of a chat session (Phase 8B.1 /
/// Phase 7B item 4/10). TXT and Markdown are pure string builders
/// (unit-testable without a PDF renderer); PDF mirrors the same `pdf`
/// package convention already used by `PwPdfExportService`
/// (services/export/pw_pdf_export_service.dart) rather than inventing a
/// second layout approach.
///
/// Every format includes each assistant answer's citations and, for a
/// general-knowledge answer, the same provenance note already shown in the
/// chat UI (`ChatScreen`'s `_MessageBubble`) - an export should never look
/// more "grounded in your content" than the conversation actually was.
class ChatExportService {
  const ChatExportService();

  String buildPlainText(ChatSession? session, List<ChatMessage> messages) {
    final buffer = StringBuffer()
      ..writeln(session?.title ?? 'OfflineMoMAI chat')
      ..writeln();
    for (final message in messages) {
      buffer.writeln('${_speaker(message)}: ${message.content}');
      final note = _provenanceNote(message);
      if (note != null) buffer.writeln('  ($note)');
      final citations = _citationsLine(message);
      if (citations != null) buffer.writeln('  Sources: $citations');
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  String buildMarkdown(ChatSession? session, List<ChatMessage> messages) {
    final buffer = StringBuffer()
      ..writeln('# ${session?.title ?? 'OfflineMoMAI chat'}')
      ..writeln();
    for (final message in messages) {
      buffer.writeln('**${_speaker(message)}:**');
      buffer.writeln();
      buffer.writeln(message.content);
      final note = _provenanceNote(message);
      if (note != null) {
        buffer.writeln();
        buffer.writeln('_${note}_');
      }
      final citations = _citationsLine(message);
      if (citations != null) {
        buffer.writeln();
        buffer.writeln('Sources: $citations');
      }
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<Uint8List> buildPdf(ChatSession? session, List<ChatMessage> messages) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, text: session?.title ?? 'OfflineMoMAI chat'),
          pw.SizedBox(height: 12),
          for (final message in messages) ...[
            pw.Text(_speaker(message), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Paragraph(text: message.content),
            if (_provenanceNote(message) case final note?)
              pw.Text(
                note,
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                  fontSize: 10,
                ),
              ),
            if (_citationsLine(message) case final citations?)
              pw.Text(
                'Sources: $citations',
                style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
              ),
            pw.SizedBox(height: 10),
          ],
        ],
      ),
    );
    return doc.save();
  }

  String _speaker(ChatMessage message) =>
      message.role == ChatMessageRole.user ? 'You' : 'OfflineMoMAI';

  String? _provenanceNote(ChatMessage message) {
    if (message.answerProvenance == AnswerProvenance.generalKnowledge) {
      return "From the AI's general knowledge — not your documents";
    }
    return null;
  }

  String? _citationsLine(ChatMessage message) {
    final sources = ChatSourceRef.decodeList(message.sourcesJson);
    if (sources.isEmpty) return null;
    return sources.map((s) => s.label).join(', ');
  }
}
