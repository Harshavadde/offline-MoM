import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/folder.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import 'toolkit_providers.dart';

/// Student Toolkit folders (P0-9, File-Manager Parity) - mirrors
/// `folder_providers.dart`'s (Documents) shape exactly, scoped to
/// `toolkitFolderRepositoryProvider`/`toolkitFileRepositoryProvider`
/// instead.
final toolkitFolderListProvider = FutureProvider<List<Folder>>((ref) {
  return ref.watch(toolkitFolderRepositoryProvider).getAll();
});

/// Which folder the Files screen's Folders tab is currently showing -
/// `null` means "All Files". UI-only selection, not persisted, same
/// convention as `selectedFolderProvider`.
final selectedToolkitFolderProvider = StateProvider<int?>((ref) => null);

/// The files shown for whichever folder [selectedToolkitFolderProvider]
/// currently points at.
final toolkitFilesInSelectedFolderProvider = FutureProvider<List<ToolkitFile>>((ref) {
  final folderId = ref.watch(selectedToolkitFolderProvider);
  return ref.watch(toolkitFileRepositoryProvider).getInFolder(folderId);
});

/// Creates a new, empty folder titled [title] - empty folders are allowed
/// by design, same as Documents' own folders.
Future<void> createToolkitFolder(WidgetRef ref, String title) async {
  final now = DateTime.now();
  await ref.read(toolkitFolderRepositoryProvider).insert(
        Folder(id: null, title: title, createdAt: now, updatedAt: now),
      );
  ref.invalidate(toolkitFolderListProvider);
}

/// Renames [folder] to [newTitle].
Future<void> renameToolkitFolder(WidgetRef ref, Folder folder, String newTitle) async {
  await ref.read(toolkitFolderRepositoryProvider).update(
        folder.copyWith(title: newTitle, updatedAt: DateTime.now()),
      );
  ref.invalidate(toolkitFolderListProvider);
}

/// Deletes [folder] - every file in it moves back to "All Files" (see
/// `SqfliteToolkitFolderRepository.delete`'s own doc comment); the files
/// themselves are never touched beyond that.
Future<void> deleteToolkitFolder(WidgetRef ref, Folder folder) async {
  await ref.read(toolkitFolderRepositoryProvider).delete(folder.id!);
  ref.invalidate(toolkitFolderListProvider);
  ref.invalidate(toolkitFilesInSelectedFolderProvider);
  ref.invalidate(toolkitFileListProvider);
  if (ref.read(selectedToolkitFolderProvider) == folder.id) {
    ref.read(selectedToolkitFolderProvider.notifier).state = null;
  }
}

/// Moves [fileId] into [folderId] (or back to "All Files" when `null`).
Future<void> moveToolkitFileToFolder(WidgetRef ref, int fileId, int? folderId) async {
  await ref.read(toolkitFileRepositoryProvider).moveToFolder(fileId, folderId);
  ref.invalidate(toolkitFileListProvider);
  ref.invalidate(toolkitFilesInSelectedFolderProvider);
}
