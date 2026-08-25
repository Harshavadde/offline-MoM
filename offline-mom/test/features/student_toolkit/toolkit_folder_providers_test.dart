// Tests toolkit_folder_providers.dart's top-level WidgetRef helper
// functions (P0-9, File-Manager Parity). Every FFI-database call runs
// inside tester.runAsync() - sqflite_common_ffi's isolate round-trip needs
// a real (non-fake-async) zone to resolve under testWidgets, the same
// requirement toolkit_files_screen_test.dart/every other widget test in
// this suite already follows; a shared setUp/tearDown outside runAsync
// deadlocks (confirmed - a first draft without runAsync hung indefinitely
// on the very first FFI insert). WidgetRef itself is a nominal type
// distinct from ProviderContainer's own API in this Riverpod version, so a
// minimal Consumer widget captures a real one.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/toolkit_folder_providers.dart';
import 'package:offline_mom/models/toolkit_file.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/repositories/toolkit_folder_repository.dart';

import '../../test_helpers/test_database.dart';

Future<int> _insertFile(ToolkitFileRepository repository, {String title = 'File'}) {
  final now = DateTime(2026, 1, 1);
  return repository.insert(
    ToolkitFile(
      id: null,
      toolType: ToolkitToolType.imageCompress,
      title: title,
      outputPath: '/data/toolkit/$title.jpg',
      fileSizeBytes: 1000,
      originalFileSizeBytes: 2000,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  testWidgets('createToolkitFolder inserts a folder and toolkitFolderListProvider reflects it',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final container = ProviderContainer(
        overrides: [toolkitFolderRepositoryProvider.overrideWithValue(SqfliteToolkitFolderRepository(db))],
      );
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, capturedRef, _) {
          ref = capturedRef;
          return const SizedBox();
        }),
      ));

      await createToolkitFolder(ref, 'Scholarships');

      final folders = await container.read(toolkitFolderListProvider.future);
      expect(folders.map((f) => f.title), contains('Scholarships'));
    });
  });

  testWidgets('renameToolkitFolder updates the title', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final container = ProviderContainer(
        overrides: [toolkitFolderRepositoryProvider.overrideWithValue(SqfliteToolkitFolderRepository(db))],
      );
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, capturedRef, _) {
          ref = capturedRef;
          return const SizedBox();
        }),
      ));

      await createToolkitFolder(ref, 'Old name');
      final folder = (await container.read(toolkitFolderListProvider.future)).first;

      await renameToolkitFolder(ref, folder, 'New name');

      final folders = await container.read(toolkitFolderRepositoryProvider).getAll();
      expect(folders.single.title, 'New name');
    });
  });

  testWidgets('deleteToolkitFolder moves files back to All Files, never deletes them',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final fileRepository = SqfliteToolkitFileRepository(db);
      final container = ProviderContainer(
        overrides: [
          toolkitFileRepositoryProvider.overrideWithValue(fileRepository),
          toolkitFolderRepositoryProvider.overrideWithValue(SqfliteToolkitFolderRepository(db)),
        ],
      );
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, capturedRef, _) {
          ref = capturedRef;
          return const SizedBox();
        }),
      ));

      await createToolkitFolder(ref, 'Receipts');
      final folder = (await container.read(toolkitFolderListProvider.future)).first;
      final fileId = await _insertFile(fileRepository, title: 'Receipt');
      await moveToolkitFileToFolder(ref, fileId, folder.id);
      expect((await fileRepository.getById(fileId))!.folderId, folder.id);

      await deleteToolkitFolder(ref, folder);

      final file = await fileRepository.getById(fileId);
      expect(file, isNotNull);
      expect(file!.folderId, isNull);
      final folders = await container.read(toolkitFolderRepositoryProvider).getAll();
      expect(folders, isEmpty);
    });
  });

  testWidgets('moveToolkitFileToFolder(fileId, null) moves a file back to All Files',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final fileRepository = SqfliteToolkitFileRepository(db);
      final container = ProviderContainer(
        overrides: [
          toolkitFileRepositoryProvider.overrideWithValue(fileRepository),
          toolkitFolderRepositoryProvider.overrideWithValue(SqfliteToolkitFolderRepository(db)),
        ],
      );
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, capturedRef, _) {
          ref = capturedRef;
          return const SizedBox();
        }),
      ));

      await createToolkitFolder(ref, 'Tax');
      final folder = (await container.read(toolkitFolderListProvider.future)).first;
      final fileId = await _insertFile(fileRepository);
      await moveToolkitFileToFolder(ref, fileId, folder.id);

      await moveToolkitFileToFolder(ref, fileId, null);

      expect((await fileRepository.getById(fileId))!.folderId, isNull);
    });
  });

  testWidgets('toolkitFilesInSelectedFolderProvider returns exactly the files in the selected '
      'folder', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final fileRepository = SqfliteToolkitFileRepository(db);
      final container = ProviderContainer(
        overrides: [
          toolkitFileRepositoryProvider.overrideWithValue(fileRepository),
          toolkitFolderRepositoryProvider.overrideWithValue(SqfliteToolkitFolderRepository(db)),
        ],
      );
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, capturedRef, _) {
          ref = capturedRef;
          return const SizedBox();
        }),
      ));

      await createToolkitFolder(ref, 'Coursework');
      final folder = (await container.read(toolkitFolderListProvider.future)).first;
      final inFolder = await _insertFile(fileRepository, title: 'In folder');
      final outside = await _insertFile(fileRepository, title: 'Outside');
      await moveToolkitFileToFolder(ref, inFolder, folder.id);

      container.read(selectedToolkitFolderProvider.notifier).state = folder.id;
      final files = await container.read(toolkitFilesInSelectedFolderProvider.future);

      expect(files.map((f) => f.id), [inFolder]);
      expect(files.map((f) => f.id), isNot(contains(outside)));
    });
  });

  testWidgets('deleting the currently-selected folder falls back to "All Files" (selection '
      'clears)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final container = ProviderContainer(
        overrides: [toolkitFolderRepositoryProvider.overrideWithValue(SqfliteToolkitFolderRepository(db))],
      );
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, capturedRef, _) {
          ref = capturedRef;
          return const SizedBox();
        }),
      ));

      await createToolkitFolder(ref, 'Temp');
      final folder = (await container.read(toolkitFolderListProvider.future)).first;
      container.read(selectedToolkitFolderProvider.notifier).state = folder.id;

      await deleteToolkitFolder(ref, folder);

      expect(container.read(selectedToolkitFolderProvider), isNull);
    });
  });

  testWidgets('an empty folder lists zero files, not an error', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final container = ProviderContainer(
        overrides: [
          toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
          toolkitFolderRepositoryProvider.overrideWithValue(SqfliteToolkitFolderRepository(db)),
        ],
      );
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, capturedRef, _) {
          ref = capturedRef;
          return const SizedBox();
        }),
      ));

      await createToolkitFolder(ref, 'Empty');
      final folder = (await container.read(toolkitFolderListProvider.future)).first;
      container.read(selectedToolkitFolderProvider.notifier).state = folder.id;

      final files = await container.read(toolkitFilesInSelectedFolderProvider.future);

      expect(files, isEmpty);
    });
  });
}
