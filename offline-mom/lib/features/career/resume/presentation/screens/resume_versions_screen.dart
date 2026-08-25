import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../models/resume_version.dart';
import '../../../../../services/resume/resume_text_export_service.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/entrance_fade.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../../../../shared/widgets/skeleton_loader.dart';
import '../../../../../shared/widgets/text_input_dialog.dart';
import '../providers/resume_editor_providers.dart';
import '../providers/resume_version_providers.dart';

const _resumeTextExportService = ResumeTextExportService();

/// Every saved version of one resume, most recent first - rename, delete,
/// or open a read-only preview of its frozen content. Saving a *new*
/// version happens from the Editor screen (it's the only place that holds
/// the live draft a version is compiled from); this screen only manages
/// versions that already exist.
class ResumeVersionsScreen extends ConsumerWidget {
  const ResumeVersionsScreen({super.key, required this.resumeId});

  final int resumeId;

  Future<void> _rename(BuildContext context, WidgetRef ref, int versionId, String currentLabel) async {
    final entered = await showTextInputDialog(
      context,
      title: 'Rename version',
      labelText: 'Version label',
      initialValue: currentLabel,
    );
    if (entered == null || entered.isEmpty || entered == currentLabel) return;
    await ref.read(resumeVersionControllerProvider(resumeId).notifier).rename(versionId, entered);
  }

  /// Replaces the resume's *live, editable* draft with this version's
  /// frozen content (see `ResumeVersionController.restoreToDraft`'s own
  /// doc comment for exactly what is and isn't restored). Confirmed first,
  /// since this is a real, meaningful side effect - it discards whatever
  /// is currently in the live draft, the same way "Delete" discards a
  /// version.
  Future<void> _restore(BuildContext context, WidgetRef ref, int versionId, String label) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Restore "$label"?',
      message: 'This replaces the resume\'s current draft with this version\'s content. '
          'The current draft is not saved as a version first.',
      confirmLabel: 'Restore',
    );
    if (!confirmed) return;

    await ref.read(resumeVersionControllerProvider(resumeId).notifier).restoreToDraft(versionId);
    if (!context.mounted) return;
    if (ref.read(resumeVersionControllerProvider(resumeId)).error != null) return;

    // The Editor screen (still on the navigation stack beneath this one)
    // needs to re-load to show the just-restored content - it never
    // re-reads on its own just because the underlying data changed.
    ref.invalidate(resumeEditorControllerProvider(resumeId));
    context.pop();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, int versionId, String label) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete "$label"?',
      message: 'This permanently deletes the saved version and its exported PDF.',
    );
    if (!confirmed) return;
    await ref.read(resumeVersionControllerProvider(resumeId).notifier).delete(versionId);
  }

  /// Shares [version]'s already-frozen `compiledSnapshot` as plain text or
  /// Markdown - no repository read beyond the version row already held by
  /// [resumeVersionListProvider], and no PDF renderer involved. Mirrors
  /// `ResumeEditorScreen._exportResumeText`'s exact `share_plus` handling
  /// for the live draft, applied here to one saved version instead.
  Future<void> _exportVersionText(BuildContext context, ResumeVersion version, bool markdown) async {
    final text = markdown
        ? _resumeTextExportService.buildMarkdown(version.compiledSnapshot)
        : _resumeTextExportService.buildPlainText(version.compiledSnapshot);
    await SharePlus.instance.share(ShareParams(text: text, subject: version.versionLabel));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionsAsync = ref.watch(resumeVersionListProvider(resumeId));
    final controllerState = ref.watch(resumeVersionControllerProvider(resumeId));
    final dateFormat = DateFormat.yMMMd().add_jm();

    ref.listen(resumeVersionControllerProvider(resumeId), (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Versions')),
      body: versionsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SkeletonCardList(),
        ),
        error: (err, _) => ErrorState(title: "Couldn't load saved versions", error: err),
        data: (versions) {
          if (versions.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'No saved versions yet',
              message: 'Use "Save version" in the Editor to freeze the '
                  'current draft into a version you can come back to.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: versions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final version = versions[index];
              return EntranceFade(
                delay: Duration(milliseconds: 20 * index),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
                    title: Text(version.versionLabel),
                    subtitle: Text(dateFormat.format(version.createdAt)),
                    onTap: () => context.push(
                      RoutePaths.resumeVersionPreviewPath(resumeId, version.id!),
                    ),
                    trailing: controllerState.isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<String>(
                            onSelected: (action) {
                              switch (action) {
                                case 'restore':
                                  _restore(context, ref, version.id!, version.versionLabel);
                                case 'rename':
                                  _rename(context, ref, version.id!, version.versionLabel);
                                case 'export_text':
                                  _exportVersionText(context, version, false);
                                case 'export_markdown':
                                  _exportVersionText(context, version, true);
                                case 'delete':
                                  _delete(context, ref, version.id!, version.versionLabel);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'restore', child: Text('Restore to draft')),
                              PopupMenuItem(value: 'rename', child: Text('Rename')),
                              PopupMenuItem(value: 'export_text', child: Text('Export as text')),
                              PopupMenuItem(
                                value: 'export_markdown',
                                child: Text('Export as Markdown'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
