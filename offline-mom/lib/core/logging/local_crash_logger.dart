import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One recorded uncaught-exception entry, parsed back out of crash.log for
/// display (e.g. by the startup-failure fallback screen).
class CrashLogEntry {
  const CrashLogEntry({
    required this.timestamp,
    required this.source,
    required this.error,
    required this.stackTrace,
  });

  final DateTime timestamp;
  final String source;
  final String error;
  final String stackTrace;

  String get formatted =>
      'Timestamp: ${timestamp.toIso8601String()}\n'
      'Source: $source\n'
      'Error: $error\n'
      'Stack trace:\n$stackTrace';
}

/// Offline-only crash diagnostics (Product Validation Phase). Every
/// uncaught Dart-level exception - during startup or afterward - is
/// appended to `<app documents>/logs/crash.log` as one JSON line, so a
/// crash can be diagnosed by exporting/copying the log directly from the
/// device when `adb logcat`/Android Studio aren't available (e.g. a build
/// produced on a remote server and only ever installed by sideloading to
/// a physical phone). Never uploaded, never requires network access, never
/// requires a third-party crash-reporting SDK - the file never leaves the
/// device unless the user explicitly taps Export.
///
/// Deliberately narrow in scope: this can only ever observe failures that
/// reach Dart. A native/engine-embedding-level failure (e.g. a missing
/// native library, or plugin registration failing inside
/// `GeneratedPluginRegistrant`'s own Kotlin/Java code) happens before the
/// Dart VM is running at all - nothing this class hooks into can ever see
/// it, and that class of failure still needs `adb logcat` or an on-device
/// native crash reporter to diagnose. This limitation is disclosed, not
/// hidden.
///
/// Every public method is designed to never throw - a diagnostics feature
/// that itself crashes the app it's meant to diagnose would defeat its own
/// purpose, so every failure inside this class is caught and silently
/// swallowed rather than propagated.
class LocalCrashLogger {
  LocalCrashLogger._();

  static const _logsDirName = 'logs';
  static const _logFileName = 'crash.log';

  /// Keeps the log file small and always-relevant on a long-lived install -
  /// this is a rolling diagnostic aid for the current test pass, not a
  /// permanent audit trail.
  static const maxEntries = 20;

  static File? _logFile;

  /// True once [init] has resolved a writable logs directory. [record] is
  /// always safe to call regardless of this - it silently no-ops if false -
  /// so callers never need to check it themselves.
  static bool get isReady => _logFile != null;

  /// Absolute path to crash.log, for the startup-failure screen's Export
  /// button - null if storage isn't available (or [init] hasn't run yet).
  static String? get logFilePath => _logFile?.path;

  /// Resolves and creates `<app documents>/logs/`. Must be called before
  /// [record] can persist anything. Deliberately never throws - if
  /// `path_provider` itself is unavailable (or storage can't be written
  /// to), [record] simply becomes a no-op instead of taking down the app's
  /// own crash-handling path with it.
  static Future<void> init() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${docsDir.path}/$_logsDirName');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      _logFile = File('${logsDir.path}/$_logFileName');
    } catch (_) {
      _logFile = null;
    }
  }

  /// Appends one crash entry (timestamp, which hook reported it, the error,
  /// and its stack trace) to crash.log as a single JSON line, then trims
  /// the file down to the most recent [maxEntries] entries. [source]
  /// identifies which hook caught this (e.g. `'FlutterError.onError'`,
  /// `'PlatformDispatcher.onError'`) so a multi-entry log is legible about
  /// where each failure actually originated.
  static Future<void> record(Object error, StackTrace stackTrace, {required String source}) async {
    final file = _logFile;
    if (file == null) return;

    try {
      final line = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'source': source,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });

      final existingLines = await file.exists()
          ? (await file.readAsLines()).where((l) => l.trim().isNotEmpty).toList()
          : <String>[];
      existingLines.add(line);
      final trimmed = existingLines.length > maxEntries
          ? existingLines.sublist(existingLines.length - maxEntries)
          : existingLines;

      await file.writeAsString('${trimmed.join('\n')}\n');
    } catch (_) {
      // Deliberately swallowed - see class doc comment.
    }
  }

  /// The full current log file contents, verbatim - used by the
  /// startup-failure screen's Copy/Export actions where a raw dump (not a
  /// parsed view) is what the user wants to hand off. Null if nothing has
  /// been recorded yet or storage isn't available.
  static Future<String?> readRaw() async {
    final file = _logFile;
    if (file == null || !await file.exists()) return null;
    try {
      final contents = await file.readAsString();
      return contents.isEmpty ? null : contents;
    } catch (_) {
      return null;
    }
  }

  /// Every recorded entry, newest last, parsed for display - malformed
  /// lines (there shouldn't be any, since every write goes through
  /// [record]'s own `jsonEncode`) are skipped rather than thrown on, so one
  /// bad line can never make the rest of the log unreadable.
  static Future<List<CrashLogEntry>> readEntries() async {
    final file = _logFile;
    if (file == null || !await file.exists()) return const [];
    try {
      final lines = await file.readAsLines();
      final entries = <CrashLogEntry>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line) as Map<String, dynamic>;
          entries.add(
            CrashLogEntry(
              timestamp: DateTime.tryParse(decoded['timestamp'] as String? ?? '') ?? DateTime.now(),
              source: decoded['source'] as String? ?? 'unknown',
              error: decoded['error'] as String? ?? '',
              stackTrace: decoded['stackTrace'] as String? ?? '',
            ),
          );
        } catch (_) {
          continue;
        }
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }
}
