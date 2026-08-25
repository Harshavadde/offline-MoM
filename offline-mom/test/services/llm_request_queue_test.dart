import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/llm_request_queue.dart';

/// Stands in for the shared `LlamaEngine` this queue exists to protect
/// (ADR-008, docs/v2/implementation/03-decisions.md): a real concurrent
/// call against `llamadart` fails outright with a `StateError` rather than
/// queuing - this fake reproduces exactly that failure mode so the tests
/// below can prove the queue never lets it happen, not just assume it.
class _SingleSlotResource {
  bool _busy = false;
  int maxConcurrentCalls = 0;
  int _concurrentCalls = 0;

  Future<String> run(String label) async {
    _concurrentCalls++;
    if (_concurrentCalls > maxConcurrentCalls) {
      maxConcurrentCalls = _concurrentCalls;
    }
    if (_busy) {
      _concurrentCalls--;
      throw StateError('llama.cpp generation is already in progress.');
    }
    _busy = true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _busy = false;
    _concurrentCalls--;
    return label;
  }
}

void main() {
  group('serialization (the regression this queue exists to fix)', () {
    test(
        'two concurrent enqueues never call the shared resource re-entrantly, '
        'and both complete successfully', () async {
      final resource = _SingleSlotResource();
      final queue = DefaultLlmRequestQueue();

      final a = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () => resource.run('a')),
      );
      final b = queue.enqueue(
        LlmQueueRequest(isForeground: true, run: () => resource.run('b')),
      );

      final results = await Future.wait([a.result, b.result]);

      expect(resource.maxConcurrentCalls, 1);
      expect(results.toSet(), {'a', 'b'});
    });
  });

  group('FIFO ordering', () {
    test('requests of the same class run in submission order', () async {
      final queue = DefaultLlmRequestQueue();
      final order = <String>[];
      final gate = Completer<void>();

      // Occupy the single slot so every enqueue below queues up rather
      // than racing to run first.
      final blocker = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () => gate.future),
      );

      final r1 = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () async => order.add('1')),
      );
      final r2 = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () async => order.add('2')),
      );
      final r3 = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () async => order.add('3')),
      );

      gate.complete();
      await blocker.result;
      await Future.wait([r1.result, r2.result, r3.result]);

      expect(order, ['1', '2', '3']);
    });
  });

  group('foreground/background priority (ADR-008)', () {
    test(
        'a pending foreground request runs before an earlier-queued but not '
        'yet started background request', () async {
      final queue = DefaultLlmRequestQueue();
      final order = <String>[];
      final firstStarted = Completer<void>();
      final firstCanFinish = Completer<void>();

      queue.enqueue(
        LlmQueueRequest(
          isForeground: false,
          run: () async {
            firstStarted.complete();
            order.add('bg-first');
            await firstCanFinish.future;
          },
        ),
      );
      await firstStarted.future;

      // Queued while bg-first is running: background before foreground,
      // in submission order.
      final bgSecond = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () async => order.add('bg-second')),
      );
      final fg = queue.enqueue(
        LlmQueueRequest(isForeground: true, run: () async => order.add('fg')),
      );

      firstCanFinish.complete();
      await Future.wait([bgSecond.result, fg.result]);

      expect(order, ['bg-first', 'fg', 'bg-second']);
    });

    test(
        'a background request already running when a foreground request '
        'arrives is not interrupted (ADR-008: no mid-generation preemption)',
        () async {
      final queue = DefaultLlmRequestQueue();
      final order = <String>[];
      final bgStarted = Completer<void>();
      final bgCanFinish = Completer<void>();

      final bg = queue.enqueue(
        LlmQueueRequest(
          isForeground: false,
          run: () async {
            bgStarted.complete();
            await bgCanFinish.future;
            order.add('bg-finished');
          },
        ),
      );
      await bgStarted.future;

      final fg = queue.enqueue(
        LlmQueueRequest(isForeground: true, run: () async => order.add('fg')),
      );

      // The foreground request must NOT be able to complete before the
      // already-running background one finishes, since only one slot
      // exists and this queue never preempts.
      var fgCompletedEarly = false;
      unawaited(fg.result.then((_) {
        if (order.isEmpty) fgCompletedEarly = true;
      }));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fgCompletedEarly, isFalse);
      expect(order, isEmpty);

      bgCanFinish.complete();
      await Future.wait([bg.result, fg.result]);
      expect(order, ['bg-finished', 'fg']);
    });
  });

  group('cancellation', () {
    test('cancelling a queued request completes it with LlmQueueCancelledException '
        'and it never runs', () async {
      final queue = DefaultLlmRequestQueue();
      final gate = Completer<void>();
      final blocker = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () => gate.future),
      );

      var ran = false;
      final handle = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () async => ran = true),
      );

      expect(queue.cancel(handle.id), isTrue);
      await expectLater(handle.result, throwsA(isA<LlmQueueCancelledException>()));

      gate.complete();
      await blocker.result;
      expect(ran, isFalse);
    });

    test('cancel returns false for an unknown request id', () {
      final queue = DefaultLlmRequestQueue();
      expect(queue.cancel(99999), isFalse);
    });

    test('cancel returns false once a request has already started running - '
        'in-flight work is never interrupted (ADR-008)', () async {
      final queue = DefaultLlmRequestQueue();
      final started = Completer<void>();
      final canFinish = Completer<void>();

      final handle = queue.enqueue(
        LlmQueueRequest(
          isForeground: false,
          run: () async {
            started.complete();
            await canFinish.future;
            return 'done';
          },
        ),
      );
      await started.future;

      expect(queue.cancel(handle.id), isFalse);

      canFinish.complete();
      expect(await handle.result, 'done');
    });
  });

  group('retry support', () {
    test('retries a failing request up to maxAttempts, in place, before '
        'succeeding', () async {
      final queue = DefaultLlmRequestQueue();
      var attempts = 0;

      final handle = queue.enqueue(
        LlmQueueRequest<String>(
          isForeground: false,
          maxAttempts: 3,
          run: () async {
            attempts++;
            if (attempts < 3) throw Exception('transient failure');
            return 'ok';
          },
        ),
      );

      expect(await handle.result, 'ok');
      expect(attempts, 3);
    });

    test('gives up after maxAttempts and propagates the last failure', () async {
      final queue = DefaultLlmRequestQueue();
      var attempts = 0;

      final handle = queue.enqueue(
        LlmQueueRequest<void>(
          isForeground: false,
          maxAttempts: 2,
          run: () async {
            attempts++;
            throw Exception('always fails');
          },
        ),
      );

      await expectLater(handle.result, throwsException);
      expect(attempts, 2);
    });

    test('defaults to a single attempt (no automatic retry) unless requested',
        () async {
      final queue = DefaultLlmRequestQueue();
      var attempts = 0;

      final handle = queue.enqueue(
        LlmQueueRequest<void>(
          isForeground: false,
          run: () async {
            attempts++;
            throw Exception('fails');
          },
        ),
      );

      await expectLater(handle.result, throwsException);
      expect(attempts, 1);
    });
  });

  group('queue status notifications', () {
    test('statusStream reports the running request and returns to idle',
        () async {
      final queue = DefaultLlmRequestQueue();
      final snapshots = <LlmQueueSnapshot>[];
      final subscription = queue.statusStream.listen(snapshots.add);

      final gate = Completer<void>();
      final handle = queue.enqueue(
        LlmQueueRequest(isForeground: true, run: () => gate.future),
      );

      // Broadcast-stream delivery is asynchronous even for a
      // synchronously-added event, so give it a microtask turn.
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await handle.result;
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(
        snapshots.any((s) => s.runningId == handle.id && s.runningIsForeground == true),
        isTrue,
      );
      expect(snapshots.last.isIdle, isTrue);
    });

    test('counts pending foreground/background requests separately', () async {
      final queue = DefaultLlmRequestQueue();
      // Listener must be attached before anything is enqueued - a broadcast
      // StreamController never replays past events to a late listener.
      final snapshots = <LlmQueueSnapshot>[];
      final subscription = queue.statusStream.listen(snapshots.add);

      final gate = Completer<void>();
      final blocker = queue.enqueue(
        LlmQueueRequest(isForeground: false, run: () => gate.future),
      );

      queue.enqueue(LlmQueueRequest(isForeground: false, run: () async {}));
      queue.enqueue(LlmQueueRequest(isForeground: true, run: () async {}));
      queue.enqueue(LlmQueueRequest(isForeground: true, run: () async {}));

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      final latest = snapshots.last;
      expect(latest.pendingForeground, 2);
      expect(latest.pendingBackground, 1);

      gate.complete();
      await blocker.result;
    });
  });
}
