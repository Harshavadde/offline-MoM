import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/installed_model.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late InstalledModelRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteInstalledModelRepository(db);
  });

  tearDown(() => db.close());

  InstalledModel build({
    String modelId = 'whisper-small',
    ModelKind kind = ModelKind.speechToText,
    bool isActive = false,
  }) {
    return InstalledModel(
      id: null,
      modelId: modelId,
      kind: kind,
      localPath: '/data/ggml-small.bin',
      sizeBytes: 466 * 1024 * 1024,
      downloadedAt: DateTime(2026, 1, 1, 10),
      localSha256: 'deadbeef',
      isActive: isActive,
    );
  }

  test('insert then getById returns the same row', () async {
    final id = await repository.insert(build());
    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.modelId, 'whisper-small');
    expect(fetched.kind, ModelKind.speechToText);
    expect(fetched.localSha256, 'deadbeef');
    expect(fetched.isActive, isFalse);
  });

  test('getByModelId finds an installed model by its catalog id', () async {
    await repository.insert(build(modelId: 'whisper-tiny'));
    final fetched = await repository.getByModelId('whisper-tiny');
    expect(fetched, isNotNull);

    expect(await repository.getByModelId('does-not-exist'), isNull);
  });

  test('getByKind only returns rows of that kind', () async {
    await repository.insert(build(modelId: 'whisper-tiny', kind: ModelKind.speechToText));
    await repository.insert(build(modelId: 'llm-qwen', kind: ModelKind.llm));

    final sttRows = await repository.getByKind(ModelKind.speechToText);
    expect(sttRows.map((r) => r.modelId), ['whisper-tiny']);

    final llmRows = await repository.getByKind(ModelKind.llm);
    expect(llmRows.map((r) => r.modelId), ['llm-qwen']);
  });

  test('getAll returns most recently downloaded first', () async {
    await repository.insert(
      InstalledModel(
        modelId: 'a',
        kind: ModelKind.speechToText,
        localPath: '/a',
        sizeBytes: 1,
        downloadedAt: DateTime(2026, 1, 1),
        isActive: false,
      ),
    );
    await repository.insert(
      InstalledModel(
        modelId: 'b',
        kind: ModelKind.speechToText,
        localPath: '/b',
        sizeBytes: 1,
        downloadedAt: DateTime(2026, 1, 2),
        isActive: false,
      ),
    );

    final all = await repository.getAll();
    expect(all.map((r) => r.modelId), ['b', 'a']);
  });

  test('setActive deactivates every other row of the same kind, leaving other kinds untouched', () async {
    final smallId = await repository.insert(build(modelId: 'whisper-small', isActive: true));
    final tinyId = await repository.insert(build(modelId: 'whisper-tiny'));
    final llmId = await repository.insert(build(modelId: 'llm-qwen', kind: ModelKind.llm, isActive: true));

    await repository.setActive(ModelKind.speechToText, 'whisper-tiny');

    expect((await repository.getById(smallId))!.isActive, isFalse);
    expect((await repository.getById(tinyId))!.isActive, isTrue);
    // A different kind's active row is untouched by activating within speechToText.
    expect((await repository.getById(llmId))!.isActive, isTrue);

    final active = await repository.getActiveForKind(ModelKind.speechToText);
    expect(active!.modelId, 'whisper-tiny');
  });

  test('getActiveForKind returns null when nothing of that kind is active', () async {
    await repository.insert(build());
    expect(await repository.getActiveForKind(ModelKind.speechToText), isNull);
  });

  test('delete removes the row', () async {
    final id = await repository.insert(build());
    await repository.delete(id);
    expect(await repository.getById(id), isNull);
  });
}
