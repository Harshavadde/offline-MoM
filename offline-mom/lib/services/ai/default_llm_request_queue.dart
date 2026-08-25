import 'dart:async';
import 'dart:collection';

import 'llm_request_queue.dart';

/// The only concrete [LlmRequestQueue]. See that class's doc comment for
/// the behavior contract (ADR-008, docs/v2/implementation/03-decisions.md)
/// this implements.
///
/// Single-threaded by construction: Dart's event loop already serializes
/// everything here, so no lock/mutex is needed to keep `_running` and
/// `_pending` consistent - the only concurrency this class has to reason
/// about is "what order do async callbacks arrive in," not true parallel
/// access.
class DefaultLlmRequestQueue implements LlmRequestQueue {
  final Queue<_QueueEntry> _pending = Queue<_QueueEntry>();
  _QueueEntry? _running;
  int _nextId = 1;

  final StreamController<LlmQueueSnapshot> _statusController =
      StreamController<LlmQueueSnapshot>.broadcast();

  @override
  Stream<LlmQueueSnapshot> get statusStream => _statusController.stream;

  @override
  LlmQueueHandle<T> enqueue<T>(LlmQueueRequest<T> request) {
    final completer = Completer<T>();
    final id = _nextId++;
    late final _QueueEntry entry;

    Future<void> execute() async {
      var attemptsLeft = request.maxAttempts;
      while (true) {
        if (entry.cancelled) {
          completer.completeError(const LlmQueueCancelledException());
          return;
        }
        try {
          final result = await request.run();
          completer.complete(result);
          return;
        } catch (error, stackTrace) {
          attemptsLeft--;
          if (attemptsLeft <= 0) {
            completer.completeError(error, stackTrace);
            return;
          }
          // Retry immediately, in place - still holding this request's
          // turn rather than re-queuing behind other work. See
          // LlmQueueRequest.maxAttempts's doc comment.
        }
      }
    }

    entry = _QueueEntry(
      id: id,
      isForeground: request.isForeground,
      execute: execute,
      completeCancelled: () =>
          completer.completeError(const LlmQueueCancelledException()),
    );

    _pending.add(entry);
    _emitStatus();
    unawaited(_pump());

    return LlmQueueHandle<T>(id: id, result: completer.future);
  }

  @override
  bool cancel(int requestId) {
    for (final entry in _pending) {
      if (entry.id == requestId) {
        _pending.remove(entry);
        entry.cancelled = true;
        entry.completeCancelled();
        _emitStatus();
        return true;
      }
    }
    // Not pending - either unknown, already running (per the class doc
    // comment, in-flight requests can't be cancelled through this queue),
    // or already finished.
    return false;
  }

  /// Starts the next eligible request if the engine is currently idle.
  /// Idempotent - safe to call any time the queue's composition changes.
  Future<void> _pump() async {
    if (_running != null) return;

    final next = _selectNext();
    if (next == null) return;

    _pending.remove(next);
    _running = next;
    _emitStatus();

    try {
      await next.execute();
    } finally {
      _running = null;
      _emitStatus();
      // More work may have arrived (or become eligible) while this one
      // ran - keep pumping rather than waiting for the next enqueue/cancel
      // to trigger it.
      unawaited(_pump());
    }
  }

  /// ADR-008: foreground requests are FIFO among themselves and always
  /// precede background requests; a background request only becomes
  /// eligible once no foreground request is pending anywhere in the queue.
  _QueueEntry? _selectNext() {
    for (final entry in _pending) {
      if (entry.isForeground) return entry;
    }
    return _pending.isEmpty ? null : _pending.first;
  }

  void _emitStatus() {
    if (_statusController.isClosed) return;
    var pendingForeground = 0;
    var pendingBackground = 0;
    for (final entry in _pending) {
      if (entry.isForeground) {
        pendingForeground++;
      } else {
        pendingBackground++;
      }
    }
    _statusController.add(
      LlmQueueSnapshot(
        pendingForeground: pendingForeground,
        pendingBackground: pendingBackground,
        runningId: _running?.id,
        runningIsForeground: _running?.isForeground,
      ),
    );
  }

  /// Releases the status stream. Not called anywhere in the app today
  /// (this queue lives for the app's whole lifetime, registered once at
  /// the composition root) - provided for symmetry/testability.
  void dispose() {
    unawaited(_statusController.close());
  }
}

class _QueueEntry {
  _QueueEntry({
    required this.id,
    required this.isForeground,
    required this.execute,
    required this.completeCancelled,
  });

  final int id;
  final bool isForeground;
  final Future<void> Function() execute;
  final void Function() completeCancelled;
  bool cancelled = false;
}
