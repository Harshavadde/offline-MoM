import 'dart:typed_data';

import '../../models/action_item.dart';
import '../../models/decision.dart';
import '../../models/meeting.dart';
import '../../models/summary.dart';
import '../../models/transcript.dart';

/// Which sections a report should include - lets the Export screen offer
/// "pick what to include" checkboxes instead of always dumping everything.
class ReportSections {
  const ReportSections({
    this.summary = true,
    this.minutesOfMeeting = true,
    this.actionItems = true,
    this.decisions = true,
    this.transcript = true,
  });

  final bool summary;
  final bool minutesOfMeeting;
  final bool actionItems;
  final bool decisions;
  final bool transcript;

  ReportSections copyWith({
    bool? summary,
    bool? minutesOfMeeting,
    bool? actionItems,
    bool? decisions,
    bool? transcript,
  }) {
    return ReportSections(
      summary: summary ?? this.summary,
      minutesOfMeeting: minutesOfMeeting ?? this.minutesOfMeeting,
      actionItems: actionItems ?? this.actionItems,
      decisions: decisions ?? this.decisions,
      transcript: transcript ?? this.transcript,
    );
  }
}

/// Everything a meeting report needs, gathered up front so the PDF builder
/// itself stays a pure function of data (no repository access).
class MeetingReportData {
  const MeetingReportData({
    required this.meeting,
    this.transcript,
    this.summary,
    this.actionItems = const [],
    this.decisions = const [],
    this.sections = const ReportSections(),
  });

  final Meeting meeting;
  final Transcript? transcript;
  final Summary? summary;
  final List<ActionItem> actionItems;
  final List<Decision> decisions;
  final ReportSections sections;
}

/// Contract for turning a meeting's data into a shareable PDF report
/// (transcript, summary, action items, decisions).
abstract class PdfExportService {
  Future<Uint8List> buildReport(MeetingReportData data);
}
