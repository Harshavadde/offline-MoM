import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// A trivial task handler: this app doesn't need periodic background work,
/// only the mere existence of an active Android foreground service, which
/// keeps the whole app process (including the main isolate where the
/// actual download runs) from being suspended by the OS while backgrounded.
@pragma('vm:entry-point')
void _backgroundDownloadTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_BackgroundDownloadTaskHandler());
}

class _BackgroundDownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Keeps the app alive in the background (via an Android foreground service
/// + a persistent notification) while a long model download is in flight,
/// so switching to another app doesn't pause or lose progress.
///
/// Opt-in only - see [AppSettings.allowBackgroundDownloads]. Android
/// requires a visible, ongoing notification to keep a foreground service
/// alive; that's a real, user-visible trade-off (a permanent notification
/// while it's active) that the user should choose, not something turned on
/// silently. Every method here is best-effort: if starting the service
/// fails for any reason (permission denied, OEM restrictions), the actual
/// download continues normally on the main isolate - it just won't survive
/// being backgrounded, same as if the user hadn't opted in at all.
class BackgroundDownloadService {
  BackgroundDownloadService._();

  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'model_download',
        channelName: 'AI model download',
        channelDescription:
            'Shown only while an AI model is downloading in the background.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Requests whatever the current platform needs to actually show the
  /// service's notification (Android 13+ requires runtime notification
  /// permission). Call this right when the user opts in, not silently
  /// later, so the system prompt appears at a moment that makes sense.
  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    _ensureInitialized();
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<void> start(String title, String text) async {
    try {
      _ensureInitialized();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 501,
        notificationTitle: title,
        notificationText: text,
        callback: _backgroundDownloadTaskCallback,
      );
    } catch (_) {
      // Best-effort - see class doc comment.
    }
  }

  static Future<void> update(String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationText: text);
      }
    } catch (_) {
      // Best-effort - see class doc comment.
    }
  }

  static Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Best-effort - see class doc comment.
    }
  }
}
