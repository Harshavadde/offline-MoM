import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/background/recording_foreground_service.dart';

// `flutter test` has no native platform channel for `flutter_foreground_task`
// registered at all (no Android runtime, no device) - every method here is
// expected to fail internally (a `MissingPluginException` from the plugin's
// method channel) and swallow that failure, per the class's own documented
// "best-effort, mirrors BackgroundDownloadService" contract. These tests
// prove that contract genuinely holds - a real recording session must never
// be interrupted or crashed by this service being unavailable - rather than
// only asserting it in a doc comment. What they cannot prove (no device
// available in this environment) is that the service actually keeps
// recording alive on a real, screen-off/locked Android device - that
// requires real-device verification.
void main() {
  group('RecordingForegroundService (best-effort contract)', () {
    test('start() never throws, even with no native platform channel available', () async {
      await expectLater(RecordingForegroundService.start('Test meeting'), completes);
    });

    test('stop() never throws, even with nothing running', () async {
      await expectLater(RecordingForegroundService.stop(), completes);
    });

    test('requestPermission() never throws', () async {
      await expectLater(RecordingForegroundService.requestPermission(), completes);
    });

    test('start() followed immediately by stop() never throws (mirrors a real record-then-stop session)',
        () async {
      await RecordingForegroundService.start('Test meeting');
      await expectLater(RecordingForegroundService.stop(), completes);
    });
  });
}
