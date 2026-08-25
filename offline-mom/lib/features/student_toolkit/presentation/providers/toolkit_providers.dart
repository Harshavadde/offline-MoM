import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/toolkit_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../toolkit_file_query.dart';
import 'toolkit_folder_providers.dart';

/// Recent Files (Student Toolkit, V2 Phase 5A) - mirrors
/// `meetingListProvider`/`documentListProvider`'s shape exactly.
final toolkitFileListProvider = FutureProvider<List<ToolkitFile>>((ref) {
  return ref.watch(toolkitFileRepositoryProvider).getAll();
});

/// Files screen search text (P0-9, File-Manager Parity) - UI-only, never
/// persisted, same convention as `selectedFolderProvider`.
final toolkitSearchQueryProvider = StateProvider<String>((ref) => '');

/// Files screen sort order - defaults to newest-first, matching the
/// pre-P0-9 Recent Files list's own always-`createdAt DESC` behavior, so a
/// user who never touches sort sees no change.
final toolkitSortProvider = StateProvider<ToolkitFileSort>((ref) => ToolkitFileSort.dateNewest);

/// Whether the Files screen is in multi-select mode - entering/leaving is
/// a UI action (an AppBar toggle or a long-press), not a persisted
/// preference.
final toolkitSelectionModeProvider = StateProvider<bool>((ref) => false);

/// Ids of the files currently checked while `toolkitSelectionModeProvider`
/// is true.
final toolkitSelectedFileIdsProvider = StateProvider<Set<int>>((ref) => const {});

/// Rename/favorite/delete for a saved toolkit output - a thin wrapper over
/// [ToolkitFileRepository], same "no branching orchestration, just CRUD
/// plus refreshing the list" reasoning as `NotesController`
/// (lib/features/meetings/presentation/providers/notes_providers.dart).
class ToolkitFileActions {
  ToolkitFileActions(this.ref);

  final Ref ref;

  Future<void> rename(ToolkitFile file, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty || trimmed == file.title) return;
    await ref.read(toolkitFileRepositoryProvider).update(
          file.copyWith(title: trimmed, updatedAt: DateTime.now()),
        );
    ref.invalidate(toolkitFileListProvider);
    ref.invalidate(toolkitFilesInSelectedFolderProvider);
  }

  Future<void> toggleFavorite(ToolkitFile file) async {
    await ref.read(toolkitFileRepositoryProvider).update(
          file.copyWith(isFavorite: !file.isFavorite, updatedAt: DateTime.now()),
        );
    ref.invalidate(toolkitFileListProvider);
    ref.invalidate(toolkitFilesInSelectedFolderProvider);
  }

  /// Deletes the row **and** the on-disk file it points to - mirrors
  /// `DeleteMeetingUseCase`/`DeleteDocumentUseCase`'s identical "the
  /// database doesn't know about the filesystem" reasoning
  /// (lib/features/meetings/delete_meeting_use_case.dart).
  Future<void> delete(ToolkitFile file) async {
    final path = file.outputPath;
    final ioFile = File(path);
    if (await ioFile.exists()) {
      await ioFile.delete();
    }
    await ref.read(toolkitFileRepositoryProvider).delete(file.id!);
    ref.invalidate(toolkitFileListProvider);
    ref.invalidate(toolkitFilesInSelectedFolderProvider);
  }

  /// Deletes every file in [files] (P0-9, File-Manager Parity bulk delete) -
  /// one at a time through the same [delete] path (same on-disk-then-row
  /// order, same "missing on-disk file is not an error" tolerance), so bulk
  /// delete is never a second, parallel deletion implementation. A failure
  /// partway through (e.g. one file's row already gone) is swallowed for
  /// that one file and the rest still proceed - the caller only needs "did
  /// everything end up deleted," not which specific step of which specific
  /// file failed, matching this app's other best-effort bulk operations.
  /// Returns the count actually deleted.
  Future<int> deleteMany(List<ToolkitFile> files) async {
    var deleted = 0;
    for (final file in files) {
      try {
        await delete(file);
        deleted++;
      } catch (_) {
        // Best-effort - move on to the rest of the selection.
      }
    }
    return deleted;
  }

  /// Copies [file]'s on-disk output to a new toolkit output path and
  /// inserts a second row pointing at it (V2 Phase 5B - Scanner/PDF Tools'
  /// "Duplicate" action). A real file copy, not a shared-path second
  /// reference - deleting one duplicate must never affect the other,
  /// matching every other toolkit output's "one row, one owned file"
  /// invariant.
  Future<ToolkitFile> duplicate(ToolkitFile file) async {
    final extension = p.extension(file.outputPath).replaceFirst('.', '');
    final newPath = await newToolkitOutputPath(file.toolType, extension);
    await File(file.outputPath).copy(newPath);

    final now = DateTime.now();
    final copy = ToolkitFile(
      id: null,
      toolType: file.toolType,
      title: '${file.title} (copy)',
      outputPath: newPath,
      fileSizeBytes: file.fileSizeBytes,
      originalFileSizeBytes: file.originalFileSizeBytes,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      pageCount: file.pageCount,
    );
    final id = await ref.read(toolkitFileRepositoryProvider).insert(copy);
    ref.invalidate(toolkitFileListProvider);

    return ToolkitFile(
      id: id,
      toolType: copy.toolType,
      title: copy.title,
      outputPath: copy.outputPath,
      fileSizeBytes: copy.fileSizeBytes,
      originalFileSizeBytes: copy.originalFileSizeBytes,
      isFavorite: copy.isFavorite,
      createdAt: copy.createdAt,
      updatedAt: copy.updatedAt,
      pageCount: copy.pageCount,
    );
  }
}

final toolkitFileActionsProvider = Provider<ToolkitFileActions>((ref) {
  return ToolkitFileActions(ref);
});
