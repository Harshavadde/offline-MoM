// Reliability-overhaul pass, Phase 15/16: the offline-readiness report the
// user should be able to check before entering airplane mode. Built from a
// real (in-memory) InstalledModelRepository - the same source of truth the
// AI Model Manager itself reads - rather than a mock, so this test proves
// the report actually reflects real installed/active rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/installed_model.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart' show ModelKind;
import 'package:offline_mom/services/offline/offline_readiness_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late InstalledModelRepository repo;
  const service = OfflineReadinessService();

  setUp(() async {
    db = await openTestDatabase();
    repo = SqfliteInstalledModelRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> installActive(ModelKind kind, String modelId) async {
    await repo.insert(InstalledModel(
      modelId: modelId,
      kind: kind,
      localPath: '/fake/$modelId',
      sizeBytes: 1000,
      downloadedAt: DateTime.now(),
      isActive: true,
    ));
  }

  group('OfflineReadinessService.evaluate', () {
    test('is not ready when no models are installed at all', () async {
      final report = await service.evaluate(repo);
      expect(report.isReady, isFalse);
      expect(report.failingChecks.map((c) => c.label), containsAll([
        'AI language model',
        'Embedding model (semantic search)',
        'Speech-to-text model',
      ]));
    });

    test('is not ready when only some of the required models are installed', () async {
      await installActive(ModelKind.llm, 'qwen-1.5b');
      final report = await service.evaluate(repo);
      expect(report.isReady, isFalse);
      final llmCheck = report.checks.firstWhere((c) => c.label == 'AI language model');
      expect(llmCheck.passed, isTrue);
      final embeddingCheck = report.checks.firstWhere((c) => c.label == 'Embedding model (semantic search)');
      expect(embeddingCheck.passed, isFalse);
    });

    test('is ready once LLM, embedding, and speech-to-text all have an active install', () async {
      await installActive(ModelKind.llm, 'qwen-1.5b');
      await installActive(ModelKind.embedding, 'bge-small');
      await installActive(ModelKind.speechToText, 'whisper-small');

      final report = await service.evaluate(repo);
      expect(report.isReady, isTrue, reason: report.failingChecks.map((c) => c.label).join(', '));
      expect(report.failingChecks, isEmpty);
    });

    test('an installed-but-not-active model does not count toward readiness', () async {
      // isActive: false - installed on disk, but not the model the app
      // would actually use right now (mirrors InstalledModelRepository's
      // own "at most one active per kind" invariant).
      await repo.insert(InstalledModel(
        modelId: 'qwen-1.5b',
        kind: ModelKind.llm,
        localPath: '/fake/qwen',
        sizeBytes: 1000,
        downloadedAt: DateTime.now(),
        isActive: false,
      ));

      final report = await service.evaluate(repo);
      final llmCheck = report.checks.firstWhere((c) => c.label == 'AI language model');
      expect(llmCheck.passed, isFalse);
    });

    test('always reports the static, network-audited checks as passing', () async {
      final report = await service.evaluate(repo);
      final staticLabels = [
        'Local database available',
        'AI inference runs entirely on-device',
        'No network required for inference, search, OCR, or PDF generation',
      ];
      for (final label in staticLabels) {
        final check = report.checks.firstWhere((c) => c.label == label);
        expect(check.passed, isTrue, reason: label);
      }
    });

    test(
      'Part F (offline readiness, product-quality remediation pass): the network-usage detail '
      'text never mentions a network-capable feature that does not actually exist in this '
      'codebase (regression test for a real inaccuracy: this text previously claimed network was '
      'used for "one-time model downloads and an optional update check", but no update-check '
      'feature has ever existed anywhere in lib/ - confirmed by a direct repo-wide grep, not '
      'assumed)',
      () async {
        final report = await service.evaluate(repo);
        final networkCheck =
            report.checks.firstWhere((c) => c.label == 'No network required for inference, search, OCR, or PDF generation');
        expect(networkCheck.detail, isNot(contains('update')));
        expect(networkCheck.detail, 'Network is used only for one-time model downloads.');
      },
    );
  });
}
