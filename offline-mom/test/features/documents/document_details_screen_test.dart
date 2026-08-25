import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/presentation/screens/document_details_screen.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/summary_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

// See chat_screen_test.dart's identical doc comment for why every real-I/O
// step here runs inside `tester.runAsync()` and `pumpAndSettle()` is
// avoided in favor of a bounded real-time pump loop.
Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Database db;
  late DocumentRepository documentRepository;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertDocument({required DocumentStatus status}) {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: 'Quarterly Report',
        originalFilename: 'Quarterly Report.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 4096,
        filePath: '/tmp/doc.pdf',
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> pumpDetails(WidgetTester tester, int documentId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documentRepository),
          summaryRepositoryProvider.overrideWithValue(SqfliteSummaryRepository(db)),
        ],
        child: MaterialApp(home: DocumentDetailsScreen(documentId: documentId)),
      ),
    );
    await settle(tester);
  }

  testWidgets(
      '"Chat about this document" is disabled while the document is still '
      'processing (Phase 8B.3, Priority 5/8) - starting a document-scoped '
      'chat before anything is indexed would silently fall back to a '
      'general-knowledge answer that could look like it was grounded in '
      'this document', (tester) async {
    await tester.runAsync(() async {
      final documentId = await insertDocument(status: DocumentStatus.extracting);
      await pumpDetails(tester, documentId);

      final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.forum_outlined));
      expect(button.onPressed, isNull);
    });
  });

  testWidgets('"Chat about this document" is enabled once the document is ready',
      (tester) async {
    await tester.runAsync(() async {
      final documentId = await insertDocument(status: DocumentStatus.ready);
      await pumpDetails(tester, documentId);

      final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.forum_outlined));
      expect(button.onPressed, isNotNull);
    });
  });
}
