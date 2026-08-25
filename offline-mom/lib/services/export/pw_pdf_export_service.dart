import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_export_service.dart';

/// [PdfExportService] implementation using the `pdf` package. Lays out a
/// single report: title, summary, minutes of meeting, key topics, action
/// items, decisions, then the full transcript - in that order, so a reader
/// gets the short version before the raw detail.
class PwPdfExportService implements PdfExportService {
  @override
  Future<Uint8List> buildReport(MeetingReportData data) async {
    final doc = pw.Document();
    final meeting = data.meeting;
    final sections = data.sections;
    final dateLabel = DateFormat.yMMMd().add_jm().format(meeting.createdAt);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, text: meeting.title),
          pw.Text(dateLabel, style: const pw.TextStyle(color: PdfColors.grey700)),
          pw.SizedBox(height: 16),
          if (data.summary != null) ...[
            if (sections.summary) ...[
              pw.Header(level: 1, text: 'Summary'),
              pw.Paragraph(text: data.summary!.summaryText),
            ],
            if (sections.minutesOfMeeting) ...[
              pw.Header(level: 1, text: 'Minutes of Meeting'),
              pw.Paragraph(text: data.summary!.minutesOfMeeting),
            ],
            if (sections.summary && data.summary!.keyTopics.isNotEmpty) ...[
              pw.Header(level: 1, text: 'Key Topics'),
              pw.Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final topic in data.summary!.keyTopics)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey200,
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: pw.Text(topic, style: const pw.TextStyle(fontSize: 10)),
                    ),
                ],
              ),
            ],
          ],
          if (sections.actionItems) ...[
            pw.Header(level: 1, text: 'Action Items'),
            if (data.actionItems.isEmpty)
              pw.Text('None recorded.', style: const pw.TextStyle(color: PdfColors.grey700))
            else
              for (final item in data.actionItems) pw.Bullet(text: item.description),
          ],
          if (sections.decisions) ...[
            pw.Header(level: 1, text: 'Decisions'),
            if (data.decisions.isEmpty)
              pw.Text('None recorded.', style: const pw.TextStyle(color: PdfColors.grey700))
            else
              for (final decision in data.decisions) pw.Bullet(text: decision.description),
          ],
          if (sections.transcript) ...[
            pw.Header(level: 1, text: 'Transcript'),
            if (data.transcript == null)
              pw.Text('Not available.', style: const pw.TextStyle(color: PdfColors.grey700))
            else
              pw.Paragraph(text: data.transcript!.fullText),
          ],
        ],
      ),
    );

    return doc.save();
  }
}
