import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Developer-only diagnostic logging - never analytics, never telemetry,
/// never a network call (docs/v2/17-privacy.md's zero-transmission
/// commitment applies here too: a "logging" feature that phoned anything
/// home would contradict the app's entire pitch). Every call routes through
/// `dart:developer`'s `log()`, which is a structured, filterable sink
/// visible in DevTools/`flutter logs` and is compiled away in release
/// builds' AOT snapshot the same way `debugPrint` is - this replaces the
/// scattered raw `print()` calls (with `// ignore: avoid_print`) that
/// predate Phase 3A, so pipeline failures are consistently named/leveled
/// instead of ad hoc.
///
/// [name] identifies the subsystem (e.g. `'MeetingIndexer'`,
/// `'ModelLifecycleManager'`) - `dart:developer`'s own convention, shown
/// alongside each entry so a filtered log view (or a bug report pasted from
/// one) is legible without guessing which component wrote which line.
class AppLogger {
  const AppLogger(this.name);

  final String name;

  /// Routine lifecycle/diagnostic information - model loaded/unloaded,
  /// cache hit/miss, a request queued - the "what's happening" trail useful
  /// when investigating a report, not something a user would ever see.
  void info(String message) {
    if (!kDebugMode) return;
    developer.log(message, name: name, level: 800);
  }

  /// A caught, handled failure (a pipeline stage's own catch block) - still
  /// not fatal to the app, but worth a distinct level from [info] so a
  /// filtered "warnings and up" view surfaces it.
  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: name, level: 900, error: error, stackTrace: stackTrace);
  }

  /// An unexpected/unhandled-shape failure - always logged, even in a
  /// release build (unlike [info]), since this is exactly the class of
  /// thing a developer debugging a field report needs, and `dart:developer`
  /// itself is a no-op sink outside an attached observatory/DevTools
  /// session in release mode, not a network transmission - logging it
  /// unconditionally does not violate the app's offline/zero-transmission
  /// posture.
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: name, level: 1000, error: error, stackTrace: stackTrace);
  }
}
