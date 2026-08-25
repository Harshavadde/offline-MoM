import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/features/documents/presentation/screens/documents_screen.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/folder.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/folder_repository.dart';
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
  late FolderRepository folderRepository;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
    folderRepository = SqfliteFolderRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertDocument(String title) {
    final now = DateTime(2026, 1, 1);
    return documentRepository.insert(
      Document(
        id: null,
        title: title,
        originalFilename: '$title.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 1024,
        filePath: '/tmp/$title.pdf',
        status: DocumentStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> pumpDocuments(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: RoutePaths.documents,
      routes: [
        GoRoute(path: RoutePaths.documents, builder: (_, __) => const DocumentsScreen()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documentRepository),
          folderRepositoryProvider.overrideWithValue(folderRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
  }

  testWidgets(
      '"All Documents" shows every document with no folder assigned - the same set every '
      'document already showed before folders existed (V2.2 Production Hardening, Priority 2, '
      'backward compatibility)', (tester) async {
    await tester.runAsync(() async {
      await insertDocument('Report');
      await insertDocument('Notes');
      await pumpDocuments(tester);

      expect(find.text('All Documents'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
    });
  });

  testWidgets('creating a folder adds it as a selectable chip', (tester) async {
    await tester.runAsync(() async {
      await pumpDocuments(tester);

      await tester.tap(find.text('New folder'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField), 'Coursework');
      await tester.tap(find.text('Create'));
      await settle(tester);

      expect(find.text('Coursework'), findsOneWidget);
    });
  });

  testWidgets(
      'selecting a folder with no documents in it shows the empty-folder state, not the '
      '"no documents yet" state (they mean different things)', (tester) async {
    await tester.runAsync(() async {
      await insertDocument('Unfiled document');
      await folderRepository.insert(
        Folder(id: null, title: 'Empty folder', createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1)),
      );
      await pumpDocuments(tester);
      await settle(tester);

      await tester.tap(find.text('Empty folder'));
      await settle(tester);

      expect(find.text('This folder is empty'), findsOneWidget);
      expect(find.text('Unfiled document'), findsNothing);
    });
  });

  testWidgets(
      'a document moved into a folder appears there and disappears from All Documents',
      (tester) async {
    await tester.runAsync(() async {
      final documentId = await insertDocument('Assignment');
      final folderId = await folderRepository.insert(
        Folder(id: null, title: 'Coursework', createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1)),
      );
      await documentRepository.moveToFolder(documentId, folderId);
      await pumpDocuments(tester);
      await settle(tester);

      // Still on "All Documents" by default - the moved document should
      // no longer appear there.
      expect(find.text('Assignment'), findsNothing);

      await tester.tap(find.text('Coursework'));
      await settle(tester);

      expect(find.text('Assignment'), findsOneWidget);
    });
  });

  testWidgets(
      'Document Manager improvement pass (Part D): typing in the search box filters the list '
      'to matching titles only, and clearing it restores every document', (tester) async {
    await tester.runAsync(() async {
      await insertDocument('Physics Notes');
      await insertDocument('Chemistry Lab Report');
      await insertDocument('Resume');
      await pumpDocuments(tester);

      await tester.enterText(find.byType(TextField), 'notes');
      await settle(tester);

      expect(find.text('Physics Notes'), findsOneWidget);
      expect(find.text('Chemistry Lab Report'), findsNothing);
      expect(find.text('Resume'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await settle(tester);

      expect(find.text('Physics Notes'), findsOneWidget);
      expect(find.text('Chemistry Lab Report'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });
  });

  testWidgets(
      'Document Manager improvement pass (Part D): a search with no matches shows a distinct '
      '"no results" empty state, not the generic "no documents yet" one', (tester) async {
    await tester.runAsync(() async {
      await insertDocument('Report');
      await pumpDocuments(tester);

      await tester.enterText(find.byType(TextField), 'nonexistent search term');
      await settle(tester);

      expect(find.textContaining('No documents match'), findsOneWidget);
      expect(find.text('No documents yet'), findsNothing);
    });
  });

  testWidgets(
      'Document Manager improvement pass (Part D): the sort menu switches list order to '
      'alphabetical, real persisted rows re-ordered, not a fake reorder', (tester) async {
    await tester.runAsync(() async {
      // Inserted in a deliberately non-alphabetical order.
      await insertDocument('Zebra Notes');
      await insertDocument('Apple Report');
      await pumpDocuments(tester);

      await tester.tap(find.byIcon(Icons.sort_rounded));
      await settle(tester);
      await tester.tap(find.text('Title (A-Z)'));
      await settle(tester);

      final listFinder = find.byType(ListView);
      final titleTexts = tester
          .widgetList<Text>(find.descendant(of: listFinder, matching: find.byType(Text)))
          .map((t) => t.data)
          .where((text) => text == 'Zebra Notes' || text == 'Apple Report')
          .toList();
      expect(titleTexts, ['Apple Report', 'Zebra Notes']);
    });
  });
}
