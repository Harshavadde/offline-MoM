import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/logging/startup_failure_screen.dart';

void main() {
  group('StartupFailureScreen', () {
    testWidgets('shows a startup-failed message with the exception and stack trace', (tester) async {
      await tester.pumpWidget(
        StartupFailureApp(
          error: Exception('database open failed'),
          stackTrace: StackTrace.fromString('#0 AppDatabase.open (app_database.dart:10:5)'),
        ),
      );

      expect(find.text('Startup failed'), findsOneWidget);
      expect(find.textContaining('database open failed'), findsOneWidget);
      expect(find.textContaining('AppDatabase.open'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Export crash log'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Copy crash log'), findsOneWidget);
    });

    testWidgets('Copy crash log writes the full error + stack trace to the clipboard', (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        StartupFailureApp(
          error: Exception('boom'),
          stackTrace: StackTrace.fromString('#0 someFunction (file.dart:1:1)'),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Copy crash log'));
      await tester.pump();

      expect(copiedText, isNotNull);
      expect(copiedText, contains('boom'));
      expect(copiedText, contains('someFunction'));
      expect(find.text('Crash log copied to clipboard.'), findsOneWidget);
    });

    testWidgets('Export crash log shows a friendly message when no crash log file exists yet',
        (tester) async {
      // LocalCrashLogger.logFilePath is null here (init() was never called
      // in this test), so Export should hit the "no file available" path
      // rather than attempt (and fail on) a platform channel call.
      await tester.pumpWidget(
        StartupFailureApp(error: Exception('boom'), stackTrace: StackTrace.empty),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Export crash log'));
      await tester.pump();

      expect(find.text('No crash log file is available to export.'), findsOneWidget);
    });
  });
}
