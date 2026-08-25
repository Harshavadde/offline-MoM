import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../models/folder.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/entrance_fade.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/skeleton_loader.dart';
import '../../../../shared/widgets/text_input_dialog.dart';
import '../providers/document_providers.dart';
import '../providers/folder_providers.dart';
import '../widgets/document_list_tile.dart';

/// Documents Home: every imported document, optionally filtered to one
/// folder, searched by title, and sorted - mirrors `history_screen.dart`'s
/// list pattern (lib/features/meetings/presentation/screens/history_screen.dart).
///
/// V2.2 Production Hardening, Priority 2: adds a lightweight folder
/// system (Create/Rename/Delete/Move, empty folders allowed, "All
/// Documents" as the default) on top of the previously flat document
/// list - the list itself, its empty state, its Import FAB, and every
/// existing document's visibility are all unchanged for a user who never
/// touches folders (see `documentsInSelectedFolderProvider`'s doc
/// comment).
///
/// Document Manager improvement pass (Part D): search (by title, against
/// the already-fetched folder's document list - see
/// [documentSearchQueryProvider]'s own doc comment for why this is a
/// lightweight list filter, not a duplicate of the app's separate
/// full-content Search feature) and sort ([DocumentSortOrder]) - both
/// screen-local UI state, applied client-side via
/// [applyDocumentSearchAndSort] so every document already visible on this
/// screen (real, stored, persisted rows - never a fabricated list) can
/// actually be found and ordered, closing the prior pass's own disclosed
/// gap (D-M8-08, 03-decisions.md).
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final entered = await showTextInputDialog(
      context,
      title: 'New folder',
      labelText: 'Folder name',
      confirmLabel: 'Create',
    );
    if (entered == null || entered.isEmpty) return;
    await createFolder(ref, entered);
  }

  Future<void> _renameFolder(BuildContext context, WidgetRef ref, Folder folder) async {
    final entered = await showTextInputDialog(
      context,
      title: 'Rename folder',
      labelText: 'Folder name',
      initialValue: folder.title,
    );
    if (entered == null || entered.isEmpty || entered == folder.title) return;
    await renameFolder(ref, folder, entered);
  }

  Future<void> _deleteFolder(BuildContext context, WidgetRef ref, Folder folder) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete "${folder.title}"?',
      message: 'Documents inside move back to All Documents - nothing is '
          'deleted.',
    );
    if (!confirmed) return;
    await deleteFolder(ref, folder);
  }

  Future<void> _showFolderActions(BuildContext context, WidgetRef ref, Folder folder) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _renameFolder(context, ref, folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteFolder(context, ref, folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  static const _sortLabels = {
    DocumentSortOrder.newestFirst: 'Newest first',
    DocumentSortOrder.oldestFirst: 'Oldest first',
    DocumentSortOrder.titleAZ: 'Title (A-Z)',
    DocumentSortOrder.largestFirst: 'Largest first',
  };

  @override
  Widget build(BuildContext context) {
    final documentsAsync = ref.watch(documentsInSelectedFolderProvider);
    final foldersAsync = ref.watch(folderListProvider);
    final selectedFolderId = ref.watch(selectedFolderProvider);
    final searchQuery = ref.watch(documentSearchQueryProvider);
    final sortOrder = ref.watch(documentSortOrderProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          PopupMenuButton<DocumentSortOrder>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            initialValue: sortOrder,
            onSelected: (order) => ref.read(documentSortOrderProvider.notifier).state = order,
            itemBuilder: (context) => [
              for (final entry in _sortLabels.entries)
                PopupMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      if (entry.key == sortOrder)
                        Icon(Icons.check_rounded, size: 18, color: scheme.primary)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Text(entry.value),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search documents',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          ref.read(documentSearchQueryProvider.notifier).state = '';
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (value) => ref.read(documentSearchQueryProvider.notifier).state = value,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All Documents'),
                    selected: selectedFolderId == null,
                    onSelected: (_) => ref.read(selectedFolderProvider.notifier).state = null,
                  ),
                  const SizedBox(width: 8),
                  ...foldersAsync.maybeWhen(
                    data: (folders) => [
                      for (final folder in folders) ...[
                        GestureDetector(
                          onLongPress: () => _showFolderActions(context, ref, folder),
                          child: ChoiceChip(
                            label: Text(folder.title),
                            selected: selectedFolderId == folder.id,
                            onSelected: (_) =>
                                ref.read(selectedFolderProvider.notifier).state = folder.id,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                    orElse: () => const <Widget>[],
                  ),
                  ActionChip(
                    avatar: Icon(Icons.add_rounded, size: 18, color: scheme.primary),
                    label: const Text('New folder'),
                    onPressed: () => _createFolder(context, ref),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: documentsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: SkeletonCardList(),
              ),
              error: (err, _) => ErrorState(title: 'Couldn\'t load your documents', error: err),
              data: (allDocuments) {
                final documents =
                    applyDocumentSearchAndSort(allDocuments, searchQuery, sortOrder);
                // AnimatedSwitcher (Phase 8B.5, Material motion consistency) -
                // `history_screen.dart` already crossfades between its empty and
                // list states this way; this screen previously cut between them
                // abruptly, the one list-style screen in the app that didn't
                // match that established transition.
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: documents.isEmpty
                      ? EmptyState(
                          key: ValueKey(
                            searchQuery.isNotEmpty ? 'documents-no-search-results' : 'documents-empty',
                          ),
                          icon: searchQuery.isNotEmpty
                              ? Icons.search_off_rounded
                              : Icons.description_outlined,
                          title: searchQuery.isNotEmpty
                              ? 'No documents match "$searchQuery"'
                              : selectedFolderId == null
                                  ? 'No documents yet'
                                  : 'This folder is empty',
                          message: searchQuery.isNotEmpty
                              ? 'Try a different search, or clear it to see every document '
                                  'again.'
                              : selectedFolderId == null
                                  ? 'Import a PDF, Word, text or Markdown file to '
                                      'read it and generate an offline AI summary.'
                                  : 'Move a document here from its details page, '
                                      'or pick a different folder above.',
                          // No action button here (Phase 8B.3, Priority 1) - the
                          // "Import" FAB below is always visible on this screen
                          // and does the exact same thing; a second, redundant
                          // button was a real duplicate entry point, the same
                          // reasoning Home's own empty states already follow.
                        )
                      : ListView.separated(
                          key: const ValueKey('documents-list'),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                          itemCount: documents.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final document = documents[index];
                            return EntranceFade(
                              delay: Duration(milliseconds: 20 * index),
                              child: DocumentListTile(
                                document: document,
                                onTap: () => context.push(
                                  RoutePaths.documentDetailsPath(document.id!),
                                ),
                                onDelete: () async {
                                  await ref.read(deleteDocumentUseCaseProvider)(document.id!);
                                  ref.invalidate(documentListProvider);
                                  ref.invalidate(documentsInSelectedFolderProvider);
                                },
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.documentImport),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Import'),
      ),
    );
  }
}
