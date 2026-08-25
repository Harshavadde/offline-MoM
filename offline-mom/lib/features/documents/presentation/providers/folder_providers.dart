import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/document.dart';
import '../../../../models/folder.dart';
import '../../../../providers/app_providers.dart';
import 'document_providers.dart';

/// Every folder, alphabetically (V2.2 Production Hardening, Priority 2) -
/// mirrors `documentListProvider`'s shape exactly
/// (lib/features/documents/presentation/providers/document_providers.dart).
final folderListProvider = FutureProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).getAll();
});

/// Which folder the Documents screen is currently showing - `null` means
/// "All Documents" (every document with no folder, the default). UI-only
/// selection, not persisted - reopening the Documents screen always
/// starts back at "All Documents", the same convention
/// `selectedWhisperModelsProvider` already uses for a screen-local,
/// never-persisted selection.
final selectedFolderProvider = StateProvider<int?>((ref) => null);

/// The documents shown on the Documents screen for whichever folder
/// [selectedFolderProvider] currently points at - "All Documents"
/// (`null`) returns exactly what `documentListProvider` already returns
/// (every document with no folder, which is every document that existed
/// before this feature), so a user who never touches folders sees no
/// change in behavior.
final documentsInSelectedFolderProvider = FutureProvider<List<Document>>((ref) {
  final folderId = ref.watch(selectedFolderProvider);
  return ref.watch(documentRepositoryProvider).getInFolder(folderId);
});

/// Which folder [documentId] currently belongs to (null = "All
/// Documents") - `autoDispose` since this is a per-id detail-screen
/// provider (mirrors `documentByIdProvider`'s own reasoning for the same
/// pattern).
final documentFolderIdProvider =
    FutureProvider.autoDispose.family<int?, int>((ref, documentId) {
  return ref.watch(documentRepositoryProvider).getFolderId(documentId);
});

/// Creates a new, empty folder titled [title] - empty folders are allowed
/// by design (a folder's existence never depends on any document
/// referencing it), so this is the entire "Create Folder" action.
Future<void> createFolder(WidgetRef ref, String title) async {
  final now = DateTime.now();
  await ref.read(folderRepositoryProvider).insert(
        Folder(id: null, title: title, createdAt: now, updatedAt: now),
      );
  ref.invalidate(folderListProvider);
}

/// Renames [folder] to [newTitle].
Future<void> renameFolder(WidgetRef ref, Folder folder, String newTitle) async {
  await ref.read(folderRepositoryProvider).update(
        folder.copyWith(title: newTitle, updatedAt: DateTime.now()),
      );
  ref.invalidate(folderListProvider);
}

/// Deletes [folder] - every document in it moves back to "All Documents"
/// (see [FolderRepository.delete]'s own doc comment); the documents
/// themselves are never touched beyond that.
Future<void> deleteFolder(WidgetRef ref, Folder folder) async {
  await ref.read(folderRepositoryProvider).delete(folder.id!);
  ref.invalidate(folderListProvider);
  ref.invalidate(documentsInSelectedFolderProvider);
  // If the folder being viewed was just deleted, fall back to "All
  // Documents" rather than continuing to point at a folder id that no
  // longer exists.
  if (ref.read(selectedFolderProvider) == folder.id) {
    ref.read(selectedFolderProvider.notifier).state = null;
  }
}

/// Moves [documentId] into [folderId] (or back to "All Documents" when
/// `null`).
Future<void> moveDocumentToFolder(WidgetRef ref, int documentId, int? folderId) async {
  await ref.read(documentRepositoryProvider).moveToFolder(documentId, folderId);
  ref.invalidate(documentListProvider);
  ref.invalidate(documentsInSelectedFolderProvider);
}
