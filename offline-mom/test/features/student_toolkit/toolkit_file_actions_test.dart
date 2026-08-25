// Tests ToolkitFileActions (rename/toggleFavorite/delete) through a
// ProviderContainer with only toolkitFileRepositoryProvider overridden,
// mirroring notes_controller_test.dart's leaf-provider-override pattern.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/toolkit_providers.dart';
import 'package:offline_mom/models/toolkit_file.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ToolkitFileRepository repository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteToolkitFileRepository(db);
    container = ProviderContainer(
      overrides: [toolkitFileRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> insertFile({String title = 'Original', String? path}) {
    final now = DateTime(2026, 1, 1);
    return repository.insert(
      ToolkitFile(
        id: null,
        toolType: ToolkitToolType.imageCompress,
        title: title,
        outputPath: path ?? '/nonexistent/${title}_output.jpg',
        fileSizeBytes: 1000,
        originalFileSizeBytes: 2000,
        isFavorite: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('rename() persists a trimmed title', () async {
    final id = await insertFile();
    final file = (await repository.getById(id))!;

    await container.read(toolkitFileActionsProvider).rename(file, '  Renamed  ');

    expect((await repository.getById(id))!.title, 'Renamed');
  });

  test('rename() with a blank or unchanged title is a no-op', () async {
    final id = await insertFile(title: 'Keep me');
    final file = (await repository.getById(id))!;

    await container.read(toolkitFileActionsProvider).rename(file, '   ');
    expect((await repository.getById(id))!.title, 'Keep me');

    await container.read(toolkitFileActionsProvider).rename(file, 'Keep me');
    expect((await repository.getById(id))!.title, 'Keep me');
  });

  test('toggleFavorite() flips the flag', () async {
    final id = await insertFile();
    final file = (await repository.getById(id))!;

    await container.read(toolkitFileActionsProvider).toggleFavorite(file);
    expect((await repository.getById(id))!.isFavorite, isTrue);

    final refetched = (await repository.getById(id))!;
    await container.read(toolkitFileActionsProvider).toggleFavorite(refetched);
    expect((await repository.getById(id))!.isFavorite, isFalse);
  });

  test('delete() removes both the on-disk file and the database row',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('toolkit_actions_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final outputFile = File('${tempDir.path}/output.jpg');
    await outputFile.writeAsBytes([1, 2, 3]);

    final id = await insertFile(path: outputFile.path);
    final file = (await repository.getById(id))!;

    await container.read(toolkitFileActionsProvider).delete(file);

    expect(await repository.getById(id), isNull);
    expect(await outputFile.exists(), isFalse);
  });

  test('delete() removes the database row even if the on-disk file is '
      'already gone', () async {
    final id = await insertFile(path: '/definitely/does/not/exist.jpg');
    final file = (await repository.getById(id))!;

    await container.read(toolkitFileActionsProvider).delete(file);

    expect(await repository.getById(id), isNull);
  });
}
