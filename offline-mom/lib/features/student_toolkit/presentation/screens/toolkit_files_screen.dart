import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../models/folder.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/knowledge_source_card.dart';
import '../../../../shared/widgets/text_input_dialog.dart';
import '../../toolkit_file_query.dart';
import '../providers/toolkit_folder_providers.dart';
import '../providers/toolkit_providers.dart';
import '../toolkit_tool_type_icons.dart';

/// Student Toolkit Files (Productivity Toolkit productization pass, P0-9 -
/// File-Manager Parity) - the browse/manage home for every saved toolkit
/// output: All Files / Recent / Favorites / Folders, reachable from the
/// same route Recent Files (V2 Phase 5A) used to own alone. Every action
/// here (rename/favorite/duplicate/share/delete/move) is a thin wrapper
/// over [ToolkitFileActions]/the folder providers - no second file-writing
/// or database mechanism is introduced by this screen.
class ToolkitFilesScreen extends ConsumerStatefulWidget {
  const ToolkitFilesScreen({super.key});

  @override
  ConsumerState<ToolkitFilesScreen> createState() => _ToolkitFilesScreenState();
}

class _ToolkitFilesScreenState extends ConsumerState<ToolkitFilesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _searchOpen = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _searchSortApplicable => _tabController.index == 0 || _tabController.index == 2;

  void _closeSearch() {
    _searchController.clear();
    ref.read(toolkitSearchQueryProvider.notifier).state = '';
    setState(() => _searchOpen = false);
  }

  void _exitSelectionMode() {
    ref.read(toolkitSelectionModeProvider.notifier).state = false;
    ref.read(toolkitSelectedFileIdsProvider.notifier).state = const {};
  }

  @override
  Widget build(BuildContext context) {
    final selectionMode = ref.watch(toolkitSelectionModeProvider);

    return Scaffold(
      appBar: selectionMode ? _buildSelectionAppBar(context) : _buildNormalAppBar(context),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AllFilesTab(),
          _RecentTab(),
          _FavoritesTab(),
          _FoldersTab(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(BuildContext context) {
    return AppBar(
      title: _searchOpen
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(hintText: 'Search files…', border: InputBorder.none),
              onChanged: (value) => ref.read(toolkitSearchQueryProvider.notifier).state = value,
            )
          : const Text('Files'),
      actions: [
        if (_searchSortApplicable) ...[
          if (_searchOpen)
            IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Close search', onPressed: _closeSearch)
          else
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search',
              onPressed: () => setState(() => _searchOpen = true),
            ),
          if (!_searchOpen) _SortMenuButton(onChanged: (sort) => ref.read(toolkitSortProvider.notifier).state = sort),
        ],
        if (!_searchOpen)
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Select',
            onPressed: () => ref.read(toolkitSelectionModeProvider.notifier).state = true,
          ),
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'All Files'),
          Tab(text: 'Recent'),
          Tab(text: 'Favorites'),
          Tab(text: 'Folders'),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(BuildContext context) {
    final selectedIds = ref.watch(toolkitSelectedFileIdsProvider);
    final filesAsync = ref.watch(toolkitFileListProvider);

    Future<void> bulkDelete() async {
      final files = filesAsync.value ?? [];
      final selected = files.where((f) => selectedIds.contains(f.id)).toList();
      if (selected.isEmpty) return;
      final confirmed = await showDestructiveConfirmDialog(
        context,
        title: 'Delete ${selected.length} file${selected.length == 1 ? '' : 's'}?',
        message: 'This permanently deletes the selected file${selected.length == 1 ? '' : 's'}. '
            'This can\'t be undone.',
      );
      if (!confirmed) return;
      final deleted = await ref.read(toolkitFileActionsProvider).deleteMany(selected);
      _exitSelectionMode();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deleted file${deleted == 1 ? '' : 's'}.')),
      );
    }

    Future<void> bulkShare() async {
      final files = filesAsync.value ?? [];
      final selected = files.where((f) => selectedIds.contains(f.id)).toList();
      final existing = <ToolkitFile>[];
      for (final file in selected) {
        if (await File(file.outputPath).exists()) existing.add(file);
      }
      if (existing.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('None of the selected files could be found on device.')),
        );
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [for (final f in existing) XFile(f.outputPath)]),
      );
      if (existing.length < selected.length && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${selected.length - existing.length} file(s) were skipped - not found on device.')),
        );
      }
    }

    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _exitSelectionMode),
      title: Text('${selectedIds.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.ios_share_rounded),
          tooltip: 'Share selected',
          onPressed: selectedIds.isEmpty ? null : bulkShare,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Delete selected',
          onPressed: selectedIds.isEmpty ? null : bulkDelete,
        ),
      ],
    );
  }
}

class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton({required this.onChanged});
  final ValueChanged<ToolkitFileSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ToolkitFileSort>(
      icon: const Icon(Icons.sort_rounded),
      tooltip: 'Sort',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final sort in ToolkitFileSort.values)
          PopupMenuItem(value: sort, child: Text(sort.label)),
      ],
    );
  }
}

/// Whether [path] exists on disk right now - used to show a graceful
/// "missing" state (P0-9 spec requirement) instead of crashing on a
/// row whose underlying file was moved/deleted outside the app.
bool _fileMissing(String path) => !File(path).existsSync();

Future<void> _renameFile(BuildContext context, WidgetRef ref, ToolkitFile file) async {
  final newTitle = await showTextInputDialog(
    context,
    title: 'Rename file',
    labelText: 'Title',
    initialValue: file.title,
  );
  if (newTitle == null) return;
  await ref.read(toolkitFileActionsProvider).rename(file, newTitle);
}

Future<void> _shareFile(ToolkitFile file) async {
  await SharePlus.instance.share(ShareParams(files: [XFile(file.outputPath)]));
}

bool _isPdf(ToolkitFile file) => file.outputPath.toLowerCase().endsWith('.pdf');

Future<void> _duplicateFile(BuildContext context, WidgetRef ref, ToolkitFile file) async {
  try {
    await ref.read(toolkitFileActionsProvider).duplicate(file);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not duplicate this file. Make sure you have enough free storage.')),
    );
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Duplicated "${file.title}".')));
}

Future<void> _openPreview(BuildContext context, ToolkitFile file) async {
  if (_fileMissing(file.outputPath)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This file could not be found. It may have been moved or deleted outside the app.')),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: _isPdf(file)
                ? PdfPreview(
                    build: (format) => File(file.outputPath).readAsBytes(),
                    pdfFileName: '${file.title}.pdf',
                    canDebug: false,
                    allowPrinting: false,
                    useActions: false,
                    onError: (context, error) => ErrorState(title: 'Preview unavailable', error: error),
                  )
                : InteractiveViewer(
                    child: Image.file(
                      File(file.outputPath),
                      errorBuilder: (context, error, stackTrace) =>
                          const ErrorState(title: 'Preview unavailable', error: 'This image could not be read.'),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _shareFile(file);
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showMoveToFolderSheet(BuildContext context, WidgetRef ref, ToolkitFile file) async {
  final folders = await ref.read(toolkitFolderRepositoryProvider).getAll();
  if (!context.mounted) return;
  final chosen = await showModalBottomSheet<Object>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Move to folder', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('All Files (no folder)'),
            selected: file.folderId == null,
            onTap: () => Navigator.of(sheetContext).pop(const _NoFolder()),
          ),
          for (final folder in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder.title),
              selected: file.folderId == folder.id,
              onTap: () => Navigator.of(sheetContext).pop(folder),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder'),
            onTap: () => Navigator.of(sheetContext).pop(const _NewFolder()),
          ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;

  if (chosen is _NoFolder) {
    await moveToolkitFileToFolder(ref, file.id!, null);
    return;
  }
  if (chosen is _NewFolder) {
    final title = await showTextInputDialog(context, title: 'New folder', labelText: 'Folder name');
    if (title == null || title.isEmpty) return;
    await createToolkitFolder(ref, title);
    final updated = await ref.read(toolkitFolderRepositoryProvider).getAll();
    final matches = updated.where((f) => f.title == title).toList();
    if (matches.isNotEmpty) await moveToolkitFileToFolder(ref, file.id!, matches.last.id);
    return;
  }
  if (chosen is Folder) {
    await moveToolkitFileToFolder(ref, file.id!, chosen.id);
  }
}

class _NoFolder {
  const _NoFolder();
}

class _NewFolder {
  const _NewFolder();
}

/// One file row - a checkbox in multi-select mode, otherwise the normal
/// [KnowledgeSourceCard] with its favorite/share/overflow actions. Shared
/// by every tab so there's exactly one row-rendering implementation
/// regardless of which list produced [file].
class ToolkitFileTile extends ConsumerWidget {
  const ToolkitFileTile({super.key, required this.file});
  final ToolkitFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionMode = ref.watch(toolkitSelectionModeProvider);
    final selectedIds = ref.watch(toolkitSelectedFileIdsProvider);
    final missing = _fileMissing(file.outputPath);
    final isSelected = selectedIds.contains(file.id);

    void toggleSelected() {
      final next = Set<int>.of(selectedIds);
      if (isSelected) {
        next.remove(file.id);
      } else {
        next.add(file.id!);
      }
      ref.read(toolkitSelectedFileIdsProvider.notifier).state = next;
    }

    final card = KnowledgeSourceCard(
      icon: missing ? Icons.error_outline_rounded : toolkitToolTypeIcon(file.toolType),
      title: file.title,
      updatedLabel: DateFormat.yMMMd().add_jm().format(file.createdAt),
      statusLabel: missing
          ? 'Missing'
          : file.reductionPercent == null
              ? file.toolType.label
              : '${file.reductionPercent! >= 0 ? '-' : '+'}${file.reductionPercent!.abs().toStringAsFixed(0)}%',
      statusColor: missing
          ? Theme.of(context).colorScheme.error
          : file.reductionPercent == null || file.reductionPercent! >= 0
              ? Colors.green
              : Colors.orange,
      sizeLabel: file.pageCount == null
          ? formatFileSize(file.fileSizeBytes)
          : '${formatFileSize(file.fileSizeBytes)} · ${file.pageCount} page${file.pageCount == 1 ? '' : 's'}',
      onTap: selectionMode ? toggleSelected : () => _openPreview(context, file),
      onDelete: selectionMode ? null : () => ref.read(toolkitFileActionsProvider).delete(file),
      dismissibleKey: selectionMode ? null : ValueKey('toolkit-file-${file.id}'),
      deleteConfirmTitle: 'Delete this file?',
      deleteConfirmMessage: 'This permanently deletes "${file.title}". This can\'t be undone.',
      trailing: selectionMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: file.isFavorite
                      ? const Icon(Icons.star_rounded)
                      : const Icon(Icons.star_outline_rounded),
                  tooltip: file.isFavorite ? 'Unfavorite' : 'Favorite',
                  onPressed: () => ref.read(toolkitFileActionsProvider).toggleFavorite(file),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Share',
                  onPressed: missing ? null : () => _shareFile(file),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        _renameFile(context, ref, file);
                      case 'duplicate':
                        _duplicateFile(context, ref, file);
                      case 'move':
                        _showMoveToFolderSheet(context, ref, file);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    PopupMenuItem(value: 'move', child: Text('Move to folder')),
                  ],
                ),
              ],
            ),
    );

    if (!selectionMode) return card;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: isSelected, onChanged: (_) => toggleSelected()),
        Expanded(child: card),
      ],
    );
  }
}

class _AllFilesTab extends ConsumerWidget {
  const _AllFilesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(toolkitFileListProvider);
    final query = ref.watch(toolkitSearchQueryProvider);
    final sort = ref.watch(toolkitSortProvider);

    return filesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load files', error: err),
      data: (allFiles) {
        if (allFiles.isEmpty) {
          return const EmptyState(
            icon: Icons.folder_open_rounded,
            title: 'No files yet',
            message: 'Every file you save from a Toolkit tool shows up here.',
          );
        }
        final files = sortToolkitFiles(filterToolkitFilesByQuery(allFiles, query), sort);
        if (files.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            message: 'No files match your search.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: files.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ToolkitFileTile(file: files[index]),
          ),
        );
      },
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(toolkitFileListProvider);
    final query = ref.watch(toolkitSearchQueryProvider);
    final sort = ref.watch(toolkitSortProvider);

    return filesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load files', error: err),
      data: (allFiles) {
        final favorites = allFiles.where((f) => f.isFavorite).toList();
        if (favorites.isEmpty) {
          return const EmptyState(
            icon: Icons.star_outline_rounded,
            title: 'No favorites yet',
            message: 'Tap the star on any file to keep it here.',
          );
        }
        final files = sortToolkitFiles(filterToolkitFilesByQuery(favorites, query), sort);
        if (files.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            message: 'No favorites match your search.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: files.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ToolkitFileTile(file: files[index]),
          ),
        );
      },
    );
  }
}

class _RecentTab extends ConsumerWidget {
  const _RecentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(toolkitFileListProvider);

    return filesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load recent files', error: err),
      data: (files) {
        if (files.isEmpty) {
          return const EmptyState(
            icon: Icons.folder_open_rounded,
            title: 'No files yet',
            message: 'Scans, compressed/resized images, and PDF outputs '
                'you save show up here, with their size, tool used, and '
                'when they were created.',
          );
        }

        final totalBytes = files.fold<int>(0, (sum, f) => sum + f.fileSizeBytes);
        final rows = _buildRows(files);

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${files.length} file${files.length == 1 ? '' : 's'} · ${formatFileSize(totalBytes)} used',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              );
            }
            final row = rows[index - 1];
            return switch (row) {
              _HeaderRow(:final label) => Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(label, style: Theme.of(context).textTheme.titleSmall),
                ),
              _FileRow(:final file) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ToolkitFileTile(file: file),
                ),
            };
          },
        );
      },
    );
  }

  List<_Row> _buildRows(List<ToolkitFile> files) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayFiles = <ToolkitFile>[];
    final weekFiles = <ToolkitFile>[];
    final olderFiles = <ToolkitFile>[];

    for (final file in files) {
      if (!file.createdAt.isBefore(today)) {
        todayFiles.add(file);
      } else if (!file.createdAt.isBefore(weekAgo)) {
        weekFiles.add(file);
      } else {
        olderFiles.add(file);
      }
    }

    return [
      if (todayFiles.isNotEmpty) const _HeaderRow('Today'),
      for (final f in todayFiles) _FileRow(f),
      if (weekFiles.isNotEmpty) const _HeaderRow('This Week'),
      for (final f in weekFiles) _FileRow(f),
      if (olderFiles.isNotEmpty) const _HeaderRow('Older'),
      for (final f in olderFiles) _FileRow(f),
    ];
  }
}

sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.label);
  final String label;
}

class _FileRow extends _Row {
  const _FileRow(this.file);
  final ToolkitFile file;
}

class _FoldersTab extends ConsumerWidget {
  const _FoldersTab();

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final title = await showTextInputDialog(context, title: 'New folder', labelText: 'Folder name');
    if (title == null || title.isEmpty) return;
    await createToolkitFolder(ref, title);
  }

  Future<void> _renameFolder(BuildContext context, WidgetRef ref, Folder folder) async {
    final newTitle = await showTextInputDialog(
      context,
      title: 'Rename folder',
      labelText: 'Folder name',
      initialValue: folder.title,
    );
    if (newTitle == null || newTitle.isEmpty) return;
    await renameToolkitFolder(ref, folder, newTitle);
  }

  Future<void> _deleteFolder(BuildContext context, WidgetRef ref, Folder folder) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete "${folder.title}"?',
      message: 'Files inside move back to All Files - they are not deleted.',
      confirmLabel: 'Delete folder',
    );
    if (!confirmed) return;
    await deleteToolkitFolder(ref, folder);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFolderId = ref.watch(selectedToolkitFolderProvider);

    if (selectedFolderId != null) {
      return _FolderContentsView(folderId: selectedFolderId);
    }

    final foldersAsync = ref.watch(toolkitFolderListProvider);
    final filesAsync = ref.watch(toolkitFileListProvider);

    return foldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(title: 'Couldn\'t load folders', error: err),
      data: (folders) {
        final counts = <int, int>{};
        for (final file in filesAsync.value ?? const <ToolkitFile>[]) {
          if (file.folderId != null) {
            counts[file.folderId!] = (counts[file.folderId!] ?? 0) + 1;
          }
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _createFolder(context, ref),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('New folder'),
                ),
              ),
            ),
            Expanded(
              child: folders.isEmpty
                  ? const EmptyState(
                      icon: Icons.folder_outlined,
                      title: 'No folders yet',
                      message: 'Create a folder to organize your saved files.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.folder_rounded),
                              title: Text(folder.title),
                              subtitle: Text('${counts[folder.id] ?? 0} file${counts[folder.id] == 1 ? '' : 's'}'),
                              onTap: () => ref.read(selectedToolkitFolderProvider.notifier).state = folder.id,
                              trailing: PopupMenuButton<String>(
                                tooltip: 'More',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'rename':
                                      _renameFolder(context, ref, folder);
                                    case 'delete':
                                      _deleteFolder(context, ref, folder);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FolderContentsView extends ConsumerWidget {
  const _FolderContentsView({required this.folderId});
  final int folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(toolkitFilesInSelectedFolderProvider);
    final foldersAsync = ref.watch(toolkitFolderListProvider);
    final matchingFolders = foldersAsync.value?.where((f) => f.id == folderId).toList() ?? const <Folder>[];
    final folderTitle = matchingFolders.isEmpty ? 'Folder' : matchingFolders.first.title;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to folders',
                onPressed: () => ref.read(selectedToolkitFolderProvider.notifier).state = null,
              ),
              Expanded(
                child: Text(folderTitle, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        Expanded(
          child: filesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => ErrorState(title: 'Couldn\'t load this folder', error: err),
            data: (files) {
              if (files.isEmpty) {
                return const EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'This folder is empty',
                  message: 'Use "Move to folder" on any file to add it here.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: files.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ToolkitFileTile(file: files[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
