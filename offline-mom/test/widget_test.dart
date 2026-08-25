// Phase 0 smoke test: the app boots past Splash to Home, and every route in
// the nav graph resolves to a real screen without throwing.
//
// sqflite normally talks to the platform's native SQLite via a method
// channel, which doesn't exist under `flutter test`. `sqflite_common_ffi`
// swaps in a pure-Dart/native FFI implementation so repositories can run
// against a real SQLite database in tests. Hive similarly needs a real
// directory instead of the path_provider platform channel that
// `Hive.initFlutter()` normally uses.
//
// `flutter test` runs widget tests under `AutomatedTestWidgetsFlutterBinding`,
// which does not let genuinely-real async I/O (temp directory creation,
// opening the sqlite/Hive files) complete on its own — only `pump()`-driven
// work progresses by default. Everything that touches real I/O is therefore
// wrapped in `tester.runAsync()`.
//
// `pumpAndSettle()` is deliberately avoided: it only returns once no further
// frames get scheduled, which never happens reliably here (a `Riverpod`
// `FutureProvider` resolving via real I/O keeps triggering rebuilds on its
// own schedule, not the fake animation clock `pumpAndSettle` expects). A
// bounded real-time pump loop is used instead.
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:offline_mom/core/router/app_router.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/database/app_database.dart';
import 'package:offline_mom/main.dart';
import 'package:offline_mom/models/app_settings.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/services/ai/model_catalog.dart';

/// Gives real async work (DB/Hive I/O, provider rebuilds) a bounded chance
/// to finish, pumping a frame after each short real wait.
Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Points `getApplicationDocumentsPath()` at a real, throwaway directory
/// instead of the platform channel `path_provider` normally uses (which
/// doesn't exist under `flutter test`) - `AppDatabase.open()` needs this
/// directly now (Product Validation Phase FTS5 fix: it resolves the
/// database path via `path_provider`, not `sqflite`'s own
/// `getDatabasesPath()`, anymore). Mirrors this project's own established
/// fake-platform pattern (`storage_providers_test.dart`,
/// `app_database_test.dart`).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._docsPath);

  final String _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('boots to Splash, reaches Home, and every route renders',
      (tester) async {
    // The default test surface (800x600) is wide and short compared to a
    // real phone, so a scrollable screen's later content (e.g. Home's empty
    // state, below the greeting + quick-action grid) can fall outside the
    // viewport's cache extent and never get its elements realized/attached
    // at all - `find` (with its default `skipOffstage: true`) only matches
    // attached, laid-out elements, not merely-built ones; `debugDumpApp()`
    // will happily show a widget that `find.text()` still can't see. A
    // phone-shaped, phone-tall surface avoids that mismatch. R-6 added a
    // card above "Recent Meetings" (Recommended Models - R-6's own Offline
    // Readiness card was removed again in R-11, see home_screen.dart),
    // pushing it further down the page than this height originally
    // accounted for - raised from 915 to 1400 for the same reason the
    // original comment gives, not a new problem.
    await tester.binding.setSurfaceSize(const Size(412, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      final tempDir =
          await Directory.systemTemp.createTemp('offline_mom_test_');
      Hive.init(tempDir.path);
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      final settingsBox = await Hive.openBox('settings_box_test');
      // The route-graph smoke test exercises the main app, not the
      // first-run onboarding flow (name entry + mandatory model download,
      // which would need real network access here) - pre-completing
      // onboarding keeps Splash routing straight to Home as before.
      await settingsBox.put(
        'app_settings',
        const AppSettings(hasCompletedOnboarding: true).toMap(),
      );
      final database = await AppDatabase.open();
      addTearDown(() async {
        await database.close();
        await settingsBox.deleteFromDisk();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            settingsBoxProvider.overrideWithValue(settingsBox),
          ],
          child: const OfflineMomApp(),
        ),
      );

      // Splash is shown first...
      expect(find.text('OfflineMoMAI'), findsOneWidget);

      // ...then it redirects to Home, which is genuinely empty (no meetings
      // exist yet in this fresh database). Splash's `Future.delayed` is a
      // *real* Timer here (we're inside `runAsync`'s real zone), so it needs
      // an actual real wait.
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      await settle(tester);
      expect(find.text('Ready when you are'), findsOneWidget);

      final routesToVisit = [
        RoutePaths.onboardingWhy,
        RoutePaths.onboardingName,
        RoutePaths.onboardingSetup,
        RoutePaths.history,
        RoutePaths.search,
        RoutePaths.settings,
        RoutePaths.home,
        RoutePaths.record,
        RoutePaths.recording,
        RoutePaths.import_,
        RoutePaths.ask,
        RoutePaths.about,
        RoutePaths.privacy,
        RoutePaths.help,
        RoutePaths.appearance,
        RoutePaths.aiModels,
        RoutePaths.aiModelSetup,
        RoutePaths.aiModelStorage,
        RoutePaths.aiModelDetailsPath(ModelCatalog.whisperSmall.id),
        RoutePaths.storage,
        RoutePaths.recordingPreferences,
        RoutePaths.language,
        RoutePaths.backup,
        RoutePaths.meetingDetailsPath(1),
        RoutePaths.pdfPreviewPath(1),
        RoutePaths.exportPath(1),
      ];

      for (final route in routesToVisit) {
        appRouter.go(route);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'route $route threw');
      }
    });
  });
}
