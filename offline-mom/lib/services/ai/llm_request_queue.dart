/// Coordinates every call against the single shared on-device LLM engine
/// (`LlamaDartLlmEngine`, unchanged - see llamadart_llm_engine.dart).
///
/// Resolves ADR-008 (docs/v2/implementation/03-decisions.md): the engine
/// can only run one generation at a time (a second concurrent call fails
/// outright rather than queuing, per `llamadart`'s actual behavior - see
/// that ADR's "correction to the existing documented model"). This queue is
/// the thing that makes that true safely: every caller submits a request
/// here instead of calling [LlmEngine] directly, and the queue guarantees
/// only one request is ever in flight against the engine.
///
/// Queueing behavior, exactly as decided in ADR-008 - not an open design
/// question:
/// - FIFO within each class (foreground/background).
/// - A background request never starts while any foreground request is
///   pending; a foreground request never waits behind a *queued* (not yet
///   started) background request.
/// - A background request already in flight when a foreground request
///   arrives is **not** interrupted - it runs to completion or its own
///   existing stall timeout, whichever comes first. This queue does not
///   attempt to cancel in-flight generation; that stays exactly where it
///   already lives, inside [LlmEngine]'s own implementation.
abstract class LlmRequestQueue {
  /// Submits [request]. Returns a handle carrying both the request's id
  /// (for [cancel]) and a [Future] that resolves once the engine has
  /// actually processed it - subject to whatever timeout [request.run]
  /// itself applies (this queue adds none; see the class doc comment).
  LlmQueueHandle<T> enqueue<T>(LlmQueueRequest<T> request);

  /// Cancels [requestId] if it is still queued (not yet started). Returns
  /// false if the id is unknown, already running, or already finished - an
  /// in-flight request cannot be cancelled through this queue, per the
  /// class doc comment.
  bool cancel(int requestId);

  /// Emits a new [LlmQueueSnapshot] every time the queue's composition
  /// changes (a request is added, starts running, finishes, or is
  /// cancelled) - the "queue status notifications" a future chat/workspace
  /// UI can subscribe to without polling.
  Stream<LlmQueueSnapshot> get statusStream;
}

/// One request to run against the shared LLM engine.
class LlmQueueRequest<T> {
  const LlmQueueRequest({
    required this.isForeground,
    required this.run,
    this.maxAttempts = 1,
  }) : assert(maxAttempts >= 1, 'maxAttempts must be at least 1');

  /// True for user-initiated requests (chat); false for background
  /// pipeline work (meeting/document summarization) - the distinction
  /// ADR-008's pause behavior depends on.
  final bool isForeground;

  final Future<T> Function() run;

  /// How many times [run] is attempted (immediately, in place - not
  /// re-queued behind other work) before the request is considered failed.
  /// Cancellation is never retried regardless of this value. Defaults to 1
  /// (no retry), since automatic retry is a real behavior change existing
  /// callers haven't opted into - see docs/v2/implementation/02-backlog.md
  /// Task 1.2.1.1 and the Phase 0 completion report for which callers, if
  /// any, currently request more than one attempt.
  final int maxAttempts;
}

/// Returned by [LlmRequestQueue.enqueue] - lets a caller both await the
/// result and, separately, cancel the request by [id] while it's still
/// queued.
class LlmQueueHandle<T> {
  const LlmQueueHandle({required this.id, required this.result});

  final int id;
  final Future<T> result;
}

/// Thrown (via [LlmQueueHandle.result]) when a request is cancelled via
/// [LlmRequestQueue.cancel] before it started running.
class LlmQueueCancelledException implements Exception {
  const LlmQueueCancelledException();

  @override
  String toString() => 'Request was cancelled before it started running.';
}

/// A snapshot of the queue's current composition - see
/// [LlmRequestQueue.statusStream].
class LlmQueueSnapshot {
  const LlmQueueSnapshot({
    required this.pendingForeground,
    required this.pendingBackground,
    required this.runningId,
    required this.runningIsForeground,
  });

  final int pendingForeground;
  final int pendingBackground;

  /// Id of the request currently executing against the engine, or null if
  /// the queue is idle.
  final int? runningId;

  /// Whether the running request (if any) is foreground or background -
  /// null exactly when [runningId] is null.
  final bool? runningIsForeground;

  bool get isIdle => runningId == null;
}
