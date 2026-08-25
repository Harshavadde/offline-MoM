import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../providers/app_providers.dart';
import '../../../../services/export/pdf_export_service.dart';
import '../../../../shared/widgets/error_state.dart';
import '../providers/export_providers.dart';

class PdfPreviewScreen extends ConsumerWidget {
  const PdfPreviewScreen({
    super.key,
    required this.meetingId,
    this.sections = const ReportSections(),
  });

  final int meetingId;

  /// Which sections to include - carried over from the Export screen's
  /// checkboxes (via the route's `extra`) so the preview matches what will
  /// actually be shared.
  final ReportSections sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportDataAsync = ref.watch(meetingReportDataProvider(meetingId));

    return Scaffold(
      appBar: AppBar(
        title: Text(reportDataAsync.valueOrNull?.meeting.title ?? 'Preview'),
      ),
      body: reportDataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(title: 'Couldn\'t prepare this PDF', error: err),
        data: (reportData) {
          final withSections = MeetingReportData(
            meeting: reportData.meeting,
            transcript: reportData.transcript,
            summary: reportData.summary,
            actionItems: reportData.actionItems,
            decisions: reportData.decisions,
            sections: sections,
          );
          return PdfPreview(
            build: (format) =>
                ref.read(pdfExportServiceProvider).buildReport(withSections),
            pdfFileName: '${reportData.meeting.title}.pdf',
            canDebug: false,
            scrollViewDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
            ),
            // Toolkit productization pass, P0-1: see
            // pdf_merge_screen.dart's identical fix for the root cause
            // (release-mode ErrorWidget strips its own message, leaving a
            // bare textless box).
            onError: (context, error) => ErrorState(
              title: 'Preview unavailable',
              error: error,
            ),
          );
        },
      ),
    );
  }
}
