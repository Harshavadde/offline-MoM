// Phase 3A: ModelLifecycleManager is pure Dart (no llamadart/native
// dependency), so unlike the real LlamaDartLlmEngine/LlamaDartEmbeddingEngine
// it can be fully unit tested here. Uses real short Durations rather than
// fakeAsync (not a dependency of this project) - mirrors
// llm_request_queue_test.dart's own established convention.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';

void main() {
  group('attach/statusOf', () {
    test('an unattached kind reports unloaded', () {
      final manager = ModelLifecycleManager();
      expect(manager.statusOf(ModelKind.llm), ModelStatus.unloaded);
    });

    test('statusOf reflects whatever the attached callback currently reports', () {
      final manager = ModelLifecycleManager();
      var status = ModelStatus.unloaded;
      manager.attach(ModelKind.llm, unload: () async {}, statusOf: () => status);

      expect(manager.statusOf(ModelKind.llm), ModelStatus.unloaded);
      status = ModelStatus.loading;
      expect(manager.statusOf(ModelKind.llm), ModelStatus.loading);
      status = ModelStatus.loaded;
      expect(manager.statusOf(ModelKind.llm), ModelStatus.loaded);
    });

    test('re-attaching the same kind cancels any pending idle timer from '
        'the previous registration', () async {
      final manager = ModelLifecycleManager(idleTimeout: const Duration(milliseconds: 30));
      var firstUnloadCalls = 0;
      manager.attach(
        ModelKind.llm,
        unload: () async => firstUnloadCalls++,
        statusOf: () => ModelStatus.loaded,
      );
      manager.beginUse(ModelKind.llm);
      manager.endUse(ModelKind.llm); // starts the idle timer

      // Re-attach before the timer fires - simulates a provider rebuild
      // constructing a fresh engine instance.
      var secondUnloadCalls = 0;
      manager.attach(
        ModelKind.llm,
        unload: () async => secondUnloadCalls++,
        statusOf: () => ModelStatus.loaded,
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(firstUnloadCalls, 0, reason: 'the stale timer must never fire');
      expect(secondUnloadCalls, 0, reason: 'the fresh registration has no idle timer yet');
    });
  });

  group('reference counting', () {
    test('refCountOf increments on beginUse and decrements on endUse', () {
      final manager = ModelLifecycleManager();
      manager.attach(ModelKind.llm, unload: () async {}, statusOf: () => ModelStatus.loaded);

      expect(manager.refCountOf(ModelKind.llm), 0);
      manager.beginUse(ModelKind.llm);
      expect(manager.refCountOf(ModelKind.llm), 1);
      manager.beginUse(ModelKind.llm);
      expect(manager.refCountOf(ModelKind.llm), 2);
      manager.endUse(ModelKind.llm);
      expect(manager.refCountOf(ModelKind.llm), 1);
      manager.endUse(ModelKind.llm);
      expect(manager.refCountOf(ModelKind.llm), 0);
    });

    test('endUse never takes the ref count below zero', () {
      final manager = ModelLifecycleManager();
      manager.attach(ModelKind.llm, unload: () async {}, statusOf: () => ModelStatus.loaded);

      manager.endUse(ModelKind.llm);
      manager.endUse(ModelKind.llm);

      expect(manager.refCountOf(ModelKind.llm), 0);
    });

    test('beginUse/endUse for an unattached kind is a harmless no-op', () {
      final manager = ModelLifecycleManager();
      expect(() => manager.beginUse(ModelKind.embedding), returnsNormally);
      expect(() => manager.endUse(ModelKind.embedding), returnsNormally);
    });
  });

  group('idle-timeout unload', () {
    test('unloads automatically once idleTimeout elapses after the last '
        'caller finishes', () async {
      final manager = ModelLifecycleManager(idleTimeout: const Duration(milliseconds: 30));
      var unloadCalls = 0;
      var loaded = true;
      manager.attach(
        ModelKind.llm,
        unload: () async {
          unloadCalls++;
          loaded = false;
        },
        statusOf: () => loaded ? ModelStatus.loaded : ModelStatus.unloaded,
      );

      manager.beginUse(ModelKind.llm);
      manager.endUse(ModelKind.llm);

      expect(unloadCalls, 0, reason: 'not idle long enough yet');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(unloadCalls, 1);
      expect(manager.statusOf(ModelKind.llm), ModelStatus.unloaded);
    });

    test('a new use before the idle timeout cancels the pending unload',
        () async {
      final manager = ModelLifecycleManager(idleTimeout: const Duration(milliseconds: 40));
      var unloadCalls = 0;
      manager.attach(
        ModelKind.llm,
        unload: () async => unloadCalls++,
        statusOf: () => ModelStatus.loaded,
      );

      manager.beginUse(ModelKind.llm);
      manager.endUse(ModelKind.llm);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Re-used well before the 40ms idle timeout would have fired.
      manager.beginUse(ModelKind.llm);
      manager.endUse(ModelKind.llm);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(unloadCalls, 0, reason: 'the second use should have reset the idle clock');
    });

    test('never unloads while a caller is still actively using the model '
        '(long-running call outlasting idleTimeout)', () async {
      final manager = ModelLifecycleManager(idleTimeout: const Duration(milliseconds: 20));
      var unloadCalls = 0;
      manager.attach(
        ModelKind.llm,
        unload: () async => unloadCalls++,
        statusOf: () => ModelStatus.loaded,
      );

      manager.beginUse(ModelKind.llm); // never matched by endUse yet - simulates a slow call
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(unloadCalls, 0, reason: 'an in-flight caller must never be unloaded out from under it');
      expect(manager.refCountOf(ModelKind.llm), 1);
    });
  });

  group('unmanagedUnload', () {
    test('unloads immediately when nothing is using the model', () async {
      final manager = ModelLifecycleManager();
      var unloadCalls = 0;
      manager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalls++,
        statusOf: () => ModelStatus.loaded,
      );

      await manager.unmanagedUnload(ModelKind.embedding);

      expect(unloadCalls, 1);
    });

    test('refuses to unload while refCount is above zero', () async {
      final manager = ModelLifecycleManager();
      var unloadCalls = 0;
      manager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalls++,
        statusOf: () => ModelStatus.loaded,
      );
      manager.beginUse(ModelKind.embedding);

      await manager.unmanagedUnload(ModelKind.embedding);

      expect(unloadCalls, 0);
    });

    test('is a no-op when the model is already unloaded', () async {
      final manager = ModelLifecycleManager();
      var unloadCalls = 0;
      manager.attach(
        ModelKind.embedding,
        unload: () async => unloadCalls++,
        statusOf: () => ModelStatus.unloaded,
      );

      await manager.unmanagedUnload(ModelKind.embedding);

      expect(unloadCalls, 0);
    });

    test('is a no-op for an unattached kind', () async {
      final manager = ModelLifecycleManager();
      await expectLater(manager.unmanagedUnload(ModelKind.speechToText), completes);
    });

    test('a thrown unload error is caught and logged, not rethrown', () async {
      final manager = ModelLifecycleManager();
      manager.attach(
        ModelKind.llm,
        unload: () async => throw Exception('native unload failed'),
        statusOf: () => ModelStatus.loaded,
      );

      await expectLater(manager.unmanagedUnload(ModelKind.llm), completes);
    });
  });

  group('dispose', () {
    test('cancels every pending idle timer so none fire afterwards', () async {
      final manager = ModelLifecycleManager(idleTimeout: const Duration(milliseconds: 20));
      var unloadCalls = 0;
      manager.attach(
        ModelKind.llm,
        unload: () async => unloadCalls++,
        statusOf: () => ModelStatus.loaded,
      );
      manager.beginUse(ModelKind.llm);
      manager.endUse(ModelKind.llm);

      manager.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(unloadCalls, 0);
    });
  });

  group('independent kinds', () {
    test('the llm, embedding, and speechToText kinds track independently', () {
      final manager = ModelLifecycleManager();
      manager.attach(ModelKind.llm, unload: () async {}, statusOf: () => ModelStatus.loaded);
      manager.attach(ModelKind.embedding, unload: () async {}, statusOf: () => ModelStatus.unloaded);

      manager.beginUse(ModelKind.llm);

      expect(manager.refCountOf(ModelKind.llm), 1);
      expect(manager.refCountOf(ModelKind.embedding), 0);
      expect(manager.statusOf(ModelKind.llm), ModelStatus.loaded);
      expect(manager.statusOf(ModelKind.embedding), ModelStatus.unloaded);
      expect(manager.statusOf(ModelKind.speechToText), ModelStatus.unloaded);
    });
  });
}
