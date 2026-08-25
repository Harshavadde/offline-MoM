// Tests DocumentListTile's status label (R-8.1) - previously rendered as
// "Summarizing 80%" for the entire duration of a stage (a fixed
// stage-position marker misrepresented as a real, moving completion
// percentage) - the exact same bug meeting_list_tile_test.dart already
// covers for meetings, missed here until this pass. A regression test for
// the specific label text, not the underlying pipeline (already covered by
// process_new_document_use_case_test.dart/retry_document_processing_use_case_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/presentation/widgets/document_list_tile.dart';
import 'package:offline_mom/models/document.dart';

Document _document(DocumentStatus status) {
  final now = DateTime(2026, 1, 1);
  return Document(
    id: 1,
    title: 'Job notes',
    originalFilename: 'job-notes.txt',
    sourceType: DocumentSourceType.txt,
    mimeType: 'text/plain',
    fileSizeBytes: 1024,
    filePath: '/fake/job-notes.txt',
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Future<void> pump(WidgetTester tester, Document document) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocumentListTile(document: document)),
      ),
    );
  }

  testWidgets('summarizing status never shows a percentage - no fixed number that could '
      'look stuck', (tester) async {
    await pump(tester, _document(DocumentStatus.summarizing));

    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Summarizing…'), findsOneWidget);
  });

  testWidgets('every in-progress pipeline stage shows an honest label with no percentage',
      (tester) async {
    for (final status in [
      DocumentStatus.created,
      DocumentStatus.extracting,
      DocumentStatus.downloadingSummaryModel,
      DocumentStatus.summarizing,
      DocumentStatus.indexing,
    ]) {
      await pump(tester, _document(status));
      expect(find.textContaining('%'), findsNothing, reason: status.name);
    }
  });

  testWidgets('a ready document shows a plain "Ready" label, still no percentage', (tester) async {
    await pump(tester, _document(DocumentStatus.ready));

    expect(find.text('Ready'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('an errored document shows a plain "Error" label, no percentage', (tester) async {
    await pump(tester, _document(DocumentStatus.error));

    expect(find.text('Error'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
