/// Small display-formatting helpers shared by any screen/widget that shows
/// a file size or a duration - factored out for `KnowledgeSourceCard`
/// (lib/shared/widgets/knowledge_source_card.dart, Phase 2B) so
/// `MeetingListTile`/`DocumentListTile` don't each need their own copy.
library;

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

String formatDurationSeconds(int seconds) {
  final d = Duration(seconds: seconds);
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
}
