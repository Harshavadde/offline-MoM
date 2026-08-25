import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// A trivial task handler: recording needs no periodic background work,
/// only the mere existence of an active Android foreground service, which
/// is what actually keeps the OS from suspending microphone access once
/// the app leaves the foreground (screen off, device locked, or another
/// app brought forward) - the same reasoning
/// `BackgroundDownloadService`'s identical handler documents for model
/// downloads.
@pragma('vm:entry-point')
void _recordingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

class _RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Keeps an active recording session alive when the screen turns off, the
/// device locks, or the app is otherwise backgrounded, via an Android
/// foreground service (`ForegroundServiceTypes.microphone`) + a persistent
/// notification - closing a real product gap: without a foreground
/// service, Android (API 29+) does not permit a backgrounded app to keep
/// using the microphone at all, so a recording started here previously had
/// no way to survive the user locking their phone mid-meeting.
///
/// Deliberately its own service, not a reuse of
/// `BackgroundDownloadService`: recording needs the `microphone`
/// foreground-service type specifically (a distinct Android permission,
/// `FOREGROUND_SERVICE_MICROPHONE`, and a distinct declared type from the
/// download feature's `dataSync`), and the two features are conceptually
/// unrelated - sharing one Dart wrapper class between them would only
/// couple two unrelated notification/lifecycle stories together. Both
/// still go through the same single underlying Android `Service` class
/// `flutter_foreground_task` itself provides (see
/// `android/app/src/main/AndroidManifest.xml`'s one `<service>`
/// declaration, now covering both `dataSync|microphone`). Since the
/// plugin only ever runs one such service at a time, [start] checks
/// `isRunningService` first and simply doesn't start a second one if
/// anything - this feature's own or the download feature's - is already
/// running, rather than risking overwriting a different feature's
/// in-flight notification with this one's text.
///
/// Every method here is best-effort, mirroring `BackgroundDownloadService`
/// exactly: if starting the service fails for any reason (permission
/// denied, OEM restrictions, or - as happens under `flutter test`, which
/// has no native platform channel for this plugin at all - simply not
/// being available), the actual recording continues normally via
/// `RecorderService`. This is a real, disclosed limitation of the
/// underlying OS/plugin, not something a pure-Dart retry could paper over.
class RecordingForegroundService {
  RecordingForegroundService._();

  static void _configure() {
    // Re-configures every time [start] is called (not gated behind an
    // "only once ever" flag) - `flutter_foreground_task`'s configuration
    // is a single global slot shared with `BackgroundDownloadService`, so
    // this must be (re-)applied immediately before this feature's own
    // `startService` call, not just the first time either feature ever
    // starts, or a recording started after a download's own `init()` call
    // would silently keep the download's channel/notification text.
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'recording',
        channelName: 'Meeting recording',
        channelDescription: 'Shown only while a meeting is actively being recorded.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Requests whatever the current platform needs to actually show the
  /// service's notification (Android 13+ requires runtime notification
  /// permission) - best-effort, same as [start] itself; a denied
  /// permission just means recording proceeds without the protection this
  /// service provides, not a blocked recording.
  static Future<void> requestPermission() async {
    try {
      _configure();
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {
      // Best-effort - see class doc comment.
    }
  }

  /// Starts the foreground service for an active recording session. A
  /// no-op, not an error, if a foreground service is already running at
  /// all - whether that's this feature's own (a rapid stop/start) or a
  /// different feature's (e.g. a background model download in flight);
  /// either way, recording simply proceeds without this specific
  /// protection rather than interrupting whatever is already running.
  static Future<void> start(String meetingTitle) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        // Already running - could be this feature's own service from a
        // rapid pause/resume, or another feature's (e.g. a model
        // download). Either way, never call startService again (the
        // plugin throws if you do); only this feature's own notification
        // text is safe to update, so leave a possibly-foreign service
        // alone rather than overwrite its text with a recording message.
        return;
      }
      _configure();
      await FlutterForegroundTask.startService(
        serviceId: 502,
        notificationTitle: 'Recording in progress',
        notificationText: meetingTitle,
        serviceTypes: const [ForegroundServiceTypes.microphone],
        callback: _recordingTaskCallback,
      );
    } catch (_) {
      // Best-effort - see class doc comment. The recording itself
      // (RecorderService) is entirely unaffected by this failing.
    }
  }

  /// Stops the foreground service - called when recording actually ends
  /// (stop) or is discarded (reset), never left running past the recording
  /// session it exists to protect (avoiding an orphaned foreground
  /// service/notification).
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
