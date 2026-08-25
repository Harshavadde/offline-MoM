import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:offline_mom/features/search/presentation/screens/search_screen.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/note.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/content_search_repository.dart';
import 'package:offline_mom/repositories/decision_repository.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/note_repository.dart';
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
  var boxCounter = 0;

  /// `SearchScreen` reads `recentSearchesProvider`, which needs a real Hive
  /// box (`settingsBoxProvider`) - mirrors `test/widget_test.dart`'s own
  /// setup. A fresh temp dir + uniquely-named box per call avoids
  /// cross-test collisions since Hive boxes are process-global by name.
  Future<List<Override>> buildOverrides(Database db) async {
    final tempDir = await Directory.systemTemp.createTemp('offline_mom_search_test_');
    Hive.init(tempDir.path);
    final box = await Hive.openBox('search_test_box_${boxCounter++}');
    addTearDown(() async {
      await box.deleteFromDisk();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    return [
      meetingRepositoryProvider.overrideWithValue(SqfliteMeetingRepository(db)),
      documentRepositoryProvider.overrideWithValue(SqfliteDocumentRepository(db)),
      contentSearchRepositoryProvider.overrideWithValue(SqfliteContentSearchRepository(db)),
      decisionRepositoryProvider.overrideWithValue(SqfliteDecisionRepository(db)),
      settingsBoxProvider.overrideWithValue(box),
    ];
  }

  Future<int> insertMeeting(MeetingRepository repo, String title) {
    final now = DateTime(2026, 3, 1);
    return repo.insert(
      Meeting(
        id: null,
        title: title,
        source: MeetingSource.recorded,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<int> insertDocument(DocumentRepository repo, String title) {
    final now = DateTime(2026, 3, 1);
    return repo.insert(
      Document(
        id: null,
        title: title,
        originalFilename: '$title.pdf',
        sourceType: DocumentSourceType.pdf,
        mimeType: 'application/pdf',
        fileSizeBytes: 100,
        filePath: '/tmp/$title.pdf',
        status: DocumentStatus.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  testWidgets('typing a query groups matching meetings and documents into '
      'their own sections (Phase 2B Workspace Search)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final meetingRepository = SqfliteMeetingRepository(db);
      final documentRepository = SqfliteDocumentRepository(db);
      await insertMeeting(meetingRepository, 'Roadmap Sync');
      await insertDocument(documentRepository, 'Roadmap Draft');

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'roadmap');
      await tester.pump();
      await settle(tester);

      // "Documents"/"Meetings" also appear as filter-chip labels, so the
      // section headers alone aren't uniquely findable by text - the result
      // rows themselves are the meaningful assertion here.
      expect(find.text('Roadmap Sync'), findsOneWidget);
      expect(find.text('Roadmap Draft'), findsOneWidget);
      // Documents render above meetings (SearchScreen's section order).
      final documentY = tester.getTopLeft(find.text('Roadmap Draft')).dy;
      final meetingY = tester.getTopLeft(find.text('Roadmap Sync')).dy;
      expect(documentY, lessThan(meetingY));
    });
  });

  testWidgets('the Notes filter only shows meetings whose match came from a '
      'note, not one that only matched by title', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final meetingRepository = SqfliteMeetingRepository(db);
      final noteRepository = SqfliteNoteRepository(db);

      final titleOnlyId = await insertMeeting(meetingRepository, 'Zorbex Kickoff');
      final noteMatchId = await insertMeeting(meetingRepository, 'Weekly Sync');
      await noteRepository.insert(
        Note(
          id: null,
          meetingId: noteMatchId,
          content: 'Mentions zorbex in the note body.',
          createdAt: DateTime(2026, 3, 1),
          updatedAt: DateTime(2026, 3, 1),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'zorbex');
      await tester.pump();
      await settle(tester);

      // Both meetings match "zorbex" before filtering.
      expect(find.text('Zorbex Kickoff'), findsOneWidget);
      expect(find.text('Weekly Sync'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Notes'));
      await settle(tester);

      expect(find.text('Weekly Sync'), findsOneWidget);
      expect(find.text('Zorbex Kickoff'), findsNothing);

      expect(titleOnlyId, isNot(noteMatchId));
    });
  });
}
