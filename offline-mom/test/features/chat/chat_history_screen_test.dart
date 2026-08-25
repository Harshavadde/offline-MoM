import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/chat/presentation/screens/chat_history_screen.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/chat_session_repository.dart';

import '../../test_helpers/test_database.dart';

// `AutomatedTestWidgetsFlutterBinding` (what `flutter test` uses) does not
// let genuinely-real async I/O - opening the sqflite database, its
// FutureProvider-driven reads - complete on its own; only `pump()`-driven
// work progresses by default. Every real-I/O step is therefore wrapped in
// `tester.runAsync()`, and `pumpAndSettle()` is avoided in favor of a bounded
// real-time pump loop - both mirror test/widget_test.dart's own established
// pattern (`settle()`) exactly, for the same reason documented there: an
// indeterminate `CircularProgressIndicator` loading state never lets
// `pumpAndSettle()` settle.
Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Widget buildApp(ChatSessionRepository chatSessionRepository) {
    return ProviderScope(
      overrides: [chatSessionRepositoryProvider.overrideWithValue(chatSessionRepository)],
      child: const MaterialApp(home: ChatHistoryScreen()),
    );
  }

  testWidgets('shows the empty state when there are no conversations yet',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final chatSessionRepository = SqfliteChatSessionRepository(db);

      await tester.pumpWidget(buildApp(chatSessionRepository));
      await settle(tester);

      expect(find.text('No conversations yet'), findsOneWidget);
    });
  });

  testWidgets('lists an existing conversation by title', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final chatSessionRepository = SqfliteChatSessionRepository(db);

      final now = DateTime(2026, 1, 1);
      await chatSessionRepository.insert(
        ChatSession(
          id: null,
          title: 'Budget planning',
          scope: ChatScope.workspace,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(buildApp(chatSessionRepository));
      await settle(tester);

      expect(find.text('Budget planning'), findsOneWidget);
    });
  });

  testWidgets('renaming a conversation updates the visible title', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final chatSessionRepository = SqfliteChatSessionRepository(db);

      final now = DateTime(2026, 1, 1);
      await chatSessionRepository.insert(
        ChatSession(
          id: null,
          title: 'Draft title',
          scope: ChatScope.workspace,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(buildApp(chatSessionRepository));
      await settle(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField), 'Final title');
      await tester.tap(find.text('Save'));
      // The dialog's exit transition rebuilds the (formerly
      // TextEditingController-backed) TextField one more time after
      // `showDialog`'s Future resolves - settling across several pumps here
      // is what would have surfaced the disposed-controller assertion this
      // test guards against.
      await settle(tester);

      expect(find.text('Final title'), findsOneWidget);
      expect(find.text('Draft title'), findsNothing);
    });
  });

  testWidgets('pinning a conversation shows a pin indicator and moves it '
      'above unpinned conversations (Phase 2B "pin conversation")',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final chatSessionRepository = SqfliteChatSessionRepository(db);

      final now = DateTime(2026, 1, 1);
      await chatSessionRepository.insert(
        ChatSession(
          id: null,
          title: 'To be pinned',
          scope: ChatScope.workspace,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await chatSessionRepository.insert(
        ChatSession(
          id: null,
          title: 'Stays unpinned',
          scope: ChatScope.workspace,
          createdAt: now.add(const Duration(minutes: 5)),
          updatedAt: now.add(const Duration(minutes: 5)),
        ),
      );

      await tester.pumpWidget(buildApp(chatSessionRepository));
      await settle(tester);

      expect(find.byIcon(Icons.push_pin_rounded), findsNothing);

      // The two sessions render as two ListTiles, each with its own
      // PopupMenuButton - open the one belonging to "To be pinned"
      // specifically (it's the second one in the list, since it's older
      // than "Stays unpinned" and neither is pinned yet).
      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await settle(tester);
      await tester.tap(find.text('Pin'));
      await settle(tester);

      expect(find.text('Pinned'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);

      // "To be pinned" now sorts under the "Pinned" header, above "Recent".
      final pinnedHeaderY = tester.getTopLeft(find.text('Pinned')).dy;
      final pinnedTitleY = tester.getTopLeft(find.text('To be pinned')).dy;
      final recentHeaderY = tester.getTopLeft(find.text('Recent')).dy;
      expect(pinnedTitleY, greaterThan(pinnedHeaderY));
      expect(pinnedTitleY, lessThan(recentHeaderY));
    });
  });

  testWidgets('deleting a conversation removes it from the list', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final chatSessionRepository = SqfliteChatSessionRepository(db);

      final now = DateTime(2026, 1, 1);
      final id = await chatSessionRepository.insert(
        ChatSession(
          id: null,
          title: 'To be deleted',
          scope: ChatScope.workspace,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(buildApp(chatSessionRepository));
      await settle(tester);
      expect(find.text('To be deleted'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      // Confirm dialog.
      await tester.tap(find.text('Delete').last);
      await settle(tester);

      expect(find.text('To be deleted'), findsNothing);
      expect(await chatSessionRepository.getById(id), isNull);
    });
  });

  testWidgets('a large history only builds the rows actually scrolled into '
      'view, not every conversation up front (Phase 3B: ListView.builder, '
      'not a plain ListView(children: [...]))', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final chatSessionRepository = SqfliteChatSessionRepository(db);

      const sessionCount = 200;
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < sessionCount; i++) {
        await chatSessionRepository.insert(
          ChatSession(
            id: null,
            title: 'Conversation $i',
            scope: ChatScope.workspace,
            createdAt: base.add(Duration(minutes: i)),
            updatedAt: base.add(Duration(minutes: i)),
          ),
        );
      }

      // A realistic, bounded phone-sized viewport - a handful of rows fit
      // on screen at once, nowhere near all 200.
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(chatSessionRepository));
      await settle(tester);

      // Every row (visible or not) would be present if this were still a
      // plain `ListView(children: [...])` - `ListView.builder` only
      // realizes rows near the current viewport.
      final builtRows = find.byType(PopupMenuButton<String>).evaluate().length;
      expect(builtRows, greaterThan(0));
      expect(
        builtRows,
        lessThan(sessionCount ~/ 4),
        reason: 'Expected only a small window of the $sessionCount '
            'conversations to be built, not the whole list - got $builtRows.',
      );
    });
  });
}
