import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/app_constants.dart';
import 'core/logging/local_crash_logger.dart';
import 'core/logging/startup_failure_screen.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'database/app_database.dart';
import 'providers/app_providers.dart';
import 'shared/widgets/lock_screen.dart';

/// Offline, on-device crash diagnostics (Product Validation Phase): every
/// uncaught exception anywhere in the app - during startup or afterward -
/// is captured into a local `crash.log` the device holds, since this app
/// is validated by sideloading to a physical phone with no `adb`/Android
/// Studio attached (`LocalCrashLogger`'s own doc comment explains what
/// this can and can't observe). This wraps only startup wiring and error
/// reporting - no AI/retrieval/database/toolkit/meetings/documents/chat
/// business logic below is touched.
Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LocalCrashLogger.init();

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previousOnError?.call(details);
      LocalCrashLogger.record(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'FlutterError.onError',
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
      LocalCrashLogger.record(error, stackTrace, source: 'PlatformDispatcher.onError');
      return true;
    };

    final crashPort = RawReceivePort((dynamic pair) {
      final errorAndStack = pair as List<dynamic>;
      LocalCrashLogger.record(
        errorAndStack.first as Object,
        errorAndStack.last == null ? StackTrace.empty : StackTrace.fromString(errorAndStack.last.toString()),
        source: 'Isolate.addErrorListener',
      );
    });
    Isolate.current.addErrorListener(crashPort.sendPort);

    try {
      // Required setup for BackgroundDownloadService, even though this app
      // doesn't use its TaskHandler<->UI data channel - see its doc comment.
      FlutterForegroundTask.initCommunicationPort();

      await Hive.initFlutter();
      final settingsBox = await Hive.openBox(AppConstants.hiveSettingsBoxName);
      final database = await AppDatabase.open();

      runApp(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            settingsBoxProvider.overrideWithValue(settingsBox),
          ],
          child: const OfflineMomApp(),
        ),
      );
    } catch (error, stackTrace) {
      await LocalCrashLogger.record(error, stackTrace, source: 'main() startup');
      runApp(StartupFailureApp(error: error, stackTrace: stackTrace));
    }
  }, (error, stackTrace) {
    LocalCrashLogger.record(error, stackTrace, source: 'runZonedGuarded');
  });
}

class OfflineMomApp extends ConsumerStatefulWidget {
  const OfflineMomApp({super.key});

  @override
  ConsumerState<OfflineMomApp> createState() => _OfflineMomAppState();
}

class _OfflineMomAppState extends ConsumerState<OfflineMomApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock (if the setting is on) whenever the app leaves the
    // foreground - not just on cold start - so switching away and back
    // can't bypass the lock by simply not force-closing the app.
    if (state == AppLifecycleState.paused) {
      ref.read(appLockControllerProvider.notifier).lockIfEnabled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.accentColor),
      darkTheme: AppTheme.dark(settings.accentColor),
      themeMode: settings.themeMode,
      routerConfig: appRouter,
      builder: (context, child) {
        final isLocked = ref.watch(appLockControllerProvider);
        return isLocked ? const LockScreen() : child ?? const SizedBox.shrink();
      },
    );
  }
}
