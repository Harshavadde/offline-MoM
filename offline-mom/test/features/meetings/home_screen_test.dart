import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/features/meetings/presentation/screens/home_screen.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
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

/// Home doesn't own navigation itself (that's `AppShell`/`app_router.dart`)
/// - a minimal router with placeholder destinations is enough to prove Home
/// actually calls `context.push`/`context.go` with the right path for each
/// destination it links to ("Navigation tests").
GoRouter buildTestRouter() {
  Widget placeholder(String label) => Scaffold(body: Center(child: Text(label)));

  return GoRouter(
    initialLocation: RoutePaths.home,
    routes: [
      GoRoute(path: RoutePaths.home, builder: (_, __) => const HomeScreen()),
      GoRoute(path: RoutePaths.history, builder: (_, __) => placeholder('history-route')),
      GoRoute(path: RoutePaths.documents, builder: (_, __) => placeholder('documents-route')),
      GoRoute(path: RoutePaths.chat, builder: (_, __) => placeholder('chat-route')),
      GoRoute(path: RoutePaths.search, builder: (_, __) => placeholder('search-route')),
      GoRoute(path: RoutePaths.import_, builder: (_, __) => placeholder('import-route')),
      GoRoute(path: RoutePaths.record, builder: (_, __) => placeholder('record-route')),
      GoRoute(path: RoutePaths.studentToolkit, builder: (_, __) => placeholder('toolkit-route')),
      GoRoute(path: RoutePaths.aiModelSetup, builder: (_, __) => placeholder('ai-model-setup-route')),
    ],
  );
}

void main() {
  var boxCounter = 0;

  Future<List<Override>> buildOverrides(Database db) async {
    final tempDir = await Directory.systemTemp.createTemp('offline_mom_home_test_');
    Hive.init(tempDir.path);
    final box = await Hive.openBox('home_test_box_${boxCounter++}');
    addTearDown(() async {
      await box.deleteFromDisk();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    return [
      meetingRepositoryProvider.overrideWithValue(SqfliteMeetingRepository(db)),
      settingsBoxProvider.overrideWithValue(box),
    ];
  }

  Future<void> pumpHome(WidgetTester tester, Database db) async {
    // The default test surface (800x600) is wide and short compared to a
    // real phone, so lower sections fall outside the viewport and can't be
    // tapped even though `find` still locates them - same fix
    // `test/widget_test.dart` already documents and applies.
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: await buildOverrides(db),
        child: MaterialApp.router(routerConfig: buildTestRouter()),
      ),
    );
    await settle(tester);
  }

  testWidgets(
      'presents quick actions with no duplicate entry points (Phase 8B.2, '
      'Priority 1, still true after the Phase 9.2 redesign) - Search and the '
      'old AI Workspace/Ask AI entries are all absent since each duplicates '
      'a persistent bottom-nav destination; Chat is a real, new Phase 9.2 '
      'entry point, not a duplicate of anything in the bottom nav',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      await pumpHome(tester, db);

      expect(find.text('Record meeting'), findsOneWidget);
      expect(find.text('Import files'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Productivity tools'), findsOneWidget);
      expect(find.text('Search'), findsNothing);
      expect(find.text('AI Workspace'), findsNothing);
      expect(find.text('Ask AI about your meetings'), findsNothing);
    });
  });

  testWidgets(
      'Quick Actions appears above Recent Meetings (Phase 9.2, Priority 3: '
      'revisits Phase 8B.2\'s "content first" ordering now that Quick '
      'Actions is a real, discoverable "what can I do right now" anchor '
      '(including the app\'s only Home entry point into Chat) rather than '
      'three interchangeable tiles - it now leads the page, matching a '
      'create-new-above-recents dashboard pattern)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      await pumpHome(tester, db);

      final meetingsHeadingY = tester.getTopLeft(find.text('Recent Meetings')).dy;
      final quickActionsHeadingY = tester.getTopLeft(find.text('Quick Actions')).dy;
      expect(quickActionsHeadingY, lessThan(meetingsHeadingY));
    });
  });

  testWidgets(
      'shows a "recommended AI models" prompt when no profession has been '
      'chosen yet (Phase 9.2, Priority 4: AI model recommendations were '
      'previously reachable only via Settings > AI Models, with zero '
      'visibility from Home)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      await pumpHome(tester, db);

      expect(find.text('Get AI models recommended for you'), findsOneWidget);
    });
  });

  testWidgets('tapping Record meeting starts recording', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      await pumpHome(tester, db);

      await tester.tap(find.text('Record meeting'));
      await settle(tester);

      expect(find.text('record-route'), findsOneWidget);
    });
  });

  testWidgets('tapping Productivity tools opens the toolkit', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      await pumpHome(tester, db);

      await tester.tap(find.text('Productivity tools'));
      await settle(tester);

      expect(find.text('toolkit-route'), findsOneWidget);
    });
  });

  testWidgets('tapping Chat opens chat with no pre-selected scope (Phase 9.2)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      await pumpHome(tester, db);

      await tester.tap(find.text('Chat'));
      await settle(tester);

      expect(find.text('chat-route'), findsOneWidget);
    });
  });

  testWidgets('tapping the recommended-models prompt opens AI model setup (Phase 9.2)',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      await pumpHome(tester, db);

      await tester.tap(find.text('Get AI models recommended for you'));
      await settle(tester);

      expect(find.text('ai-model-setup-route'), findsOneWidget);
    });
  });
}
