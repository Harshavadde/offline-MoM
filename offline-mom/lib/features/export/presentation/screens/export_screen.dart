import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/export/pdf_export_service.dart';
import '../providers/export_providers.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, required this.meetingId});

  final int meetingId;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _isExporting = false;
  ReportSections _sections = const ReportSections();

  Future<void> _exportAndShare() async {
    setState(() => _isExporting = true);
    try {
      final base =
          await ref.read(meetingReportDataProvider(widget.meetingId).future);
      final data = MeetingReportData(
        meeting: base.meeting,
        transcript: base.transcript,
        summary: base.summary,
        actionItems: base.actionItems,
        decisions: base.decisions,
        sections: _sections,
      );
      final bytes = await ref.read(pdfExportServiceProvider).buildReport(data);
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${data.meeting.title}.pdf',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not export the PDF. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sectionToggles = [
      (
        label: 'Summary',
        value: _sections.summary,
        onChanged: (bool v) => setState(() => _sections = _sections.copyWith(summary: v)),
      ),
      (
        label: 'Minutes of Meeting',
        value: _sections.minutesOfMeeting,
        onChanged: (bool v) =>
            setState(() => _sections = _sections.copyWith(minutesOfMeeting: v)),
      ),
      (
        label: 'Action items',
        value: _sections.actionItems,
        onChanged: (bool v) =>
            setState(() => _sections = _sections.copyWith(actionItems: v)),
      ),
      (
        label: 'Decisions',
        value: _sections.decisions,
        onChanged: (bool v) => setState(() => _sections = _sections.copyWith(decisions: v)),
      ),
      (
        label: 'Full transcript',
        value: _sections.transcript,
        onChanged: (bool v) => setState(() => _sections = _sections.copyWith(transcript: v)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  Icon(Icons.picture_as_pdf_outlined, size: 64, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Export this meeting as a single PDF report - fully '
                    'generated on this device.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Include in report', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Card(
                child: Column(
                  children: [
                    for (final toggle in sectionToggles)
                      SwitchListTile(
                        title: Text(toggle.label),
                        value: toggle.value,
                        onChanged: (v) => toggle.onChanged(v),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isExporting ? null : _exportAndShare,
                icon: _isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: const Text('Export & share'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(
                  RoutePaths.pdfPreviewPath(widget.meetingId),
                  extra: _sections,
                ),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview first'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
