import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../models/toolkit_file.dart';
import '../../../../shared/widgets/entrance_fade.dart';
import '../../../../shared/widgets/inline_error_text.dart';
import '../../../../shared/widgets/section_heading.dart';
import '../providers/toolkit_providers.dart';
import '../toolkit_tool_type_icons.dart';

/// Student Toolkit home - a first-class module reachable from the app's
/// own Home screen (see `home_screen.dart`'s Knowledge Source pillars,
/// which this sits alongside as a distinct, non-Knowledge-Source entry
/// point). Image Tools shipped in V2 Phase 5A (ADR-033); Scanner and PDF
/// Tools shipped in V2 Phase 5B (ADR-034,
/// docs/v2/implementation/03-decisions.md).
///
/// Three tool sections now exist (Image Tools/Scanner/PDF Tools), each the
/// same "heading + GridView of tool cards" shape - extracted into
/// `_ToolSection` here rather than left as three copy-pasted blocks, per
/// this app's own "no duplicated widgets" discipline (the Phase 5A
/// architecture review deliberately deferred this exact extraction until
/// a second/third section actually existed to generalize from, rather
/// than abstracting from a single usage speculatively).
class StudentToolkitScreen extends ConsumerWidget {
  const StudentToolkitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final recentAsync = ref.watch(toolkitFileListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Productivity Toolkit')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Every tool below runs entirely on this device - no upload, '
                      'no internet, no ads.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _ToolSection(
              title: 'Scanner',
              tools: [
                _ToolCard(
                  icon: Icons.document_scanner_rounded,
                  label: 'Scan Document',
                  subtitle: 'Camera or gallery, multi-page',
                  onTap: () => context.push(RoutePaths.toolkitScan),
                ),
              ],
              gridColumns: 1,
            ),
            const SizedBox(height: 24),
            _ToolSection(
              title: 'Image Tools',
              tools: [
                _ToolCard(
                  icon: Icons.compress_rounded,
                  label: 'Compress Image',
                  subtitle: 'For forms & applications',
                  onTap: () => context.push(RoutePaths.toolkitCompressImage),
                ),
                _ToolCard(
                  icon: Icons.aspect_ratio_rounded,
                  label: 'Resize Image',
                  subtitle: 'By %, width or height',
                  onTap: () => context.push(RoutePaths.toolkitResizeImage),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _ToolSection(
              title: 'PDF Tools',
              tools: [
                _ToolCard(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'Compress PDF',
                  subtitle: 'Resume, exam & scholarship presets',
                  onTap: () => context.push(RoutePaths.toolkitCompressPdf),
                ),
                _ToolCard(
                  icon: Icons.call_merge_rounded,
                  label: 'Merge PDFs',
                  subtitle: 'Combine multiple files into one',
                  onTap: () => context.push(RoutePaths.toolkitMergePdf),
                ),
                _ToolCard(
                  icon: Icons.call_split_rounded,
                  label: 'Split PDF',
                  subtitle: 'Divide into separate files',
                  onTap: () => context.push(RoutePaths.toolkitSplitPdf),
                ),
                _ToolCard(
                  icon: Icons.reorder_rounded,
                  label: 'Organize Pages',
                  subtitle: 'Extract & reorder pages',
                  onTap: () => context.push(RoutePaths.toolkitOrganizePdf),
                ),
                _ToolCard(
                  icon: Icons.edit_document,
                  label: 'Edit PDF',
                  subtitle: 'Text, signatures & annotations',
                  onTap: () => context.push(RoutePaths.toolkitEditPdf),
                ),
                _ToolCard(
                  icon: Icons.hide_source_rounded,
                  label: 'Redact PDF',
                  subtitle: 'Permanently remove sensitive content',
                  onTap: () => context.push(RoutePaths.toolkitRedactPdf),
                ),
                _ToolCard(
                  icon: Icons.image_outlined,
                  label: 'Images to PDF',
                  subtitle: 'Combine photos into one PDF',
                  onTap: () => context.push(RoutePaths.toolkitImagesToPdf),
                ),
                _ToolCard(
                  icon: Icons.perm_media_outlined,
                  label: 'PDF to Images',
                  subtitle: 'Export pages as JPEG images',
                  onTap: () => context.push(RoutePaths.toolkitPdfToImages),
                ),
                _ToolCard(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'View PDF',
                  subtitle: 'Browse pages & search text',
                  onTap: () => context.push(RoutePaths.toolkitViewPdf),
                ),
                _ToolCard(
                  icon: Icons.lock_outline_rounded,
                  label: 'Protect PDF',
                  subtitle: 'Add a password & permissions',
                  onTap: () => context.push(RoutePaths.toolkitPdfProtect),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionHeading(
              'Recent Files',
              onAction: () => context.push(RoutePaths.toolkitRecentFiles),
              actionLabel: 'See All',
            ),
            const SizedBox(height: 4),
            recentAsync.when(
              loading: () => const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => InlineErrorText(err),
              data: (files) {
                if (files.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Scan a document, or compress, resize, merge, split, or '
                      'organize a file to see it here.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                final recent = files.take(3).toList();
                return Column(
                  children: [
                    for (final file in recent)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            toolkitToolTypeIcon(file.toolType),
                            color: scheme.primary,
                          ),
                          title: Text(file.title, overflow: TextOverflow.ellipsis, maxLines: 1),
                          subtitle: Text(file.toolType.label),
                          onTap: () => context.push(RoutePaths.toolkitRecentFiles),
                        ),
                      ),
                  ],
                );
              },
            ),
            recentAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (err, _) => const SizedBox.shrink(),
              data: (files) {
                final favorites = files.where((f) => f.isFavorite).take(3).toList();
                if (favorites.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    SectionHeading(
                      'Favorites',
                      onAction: () => context.push(RoutePaths.toolkitRecentFiles),
                      actionLabel: 'See All',
                    ),
                    const SizedBox(height: 4),
                    for (final file in favorites)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.star_rounded, color: scheme.primary),
                          title: Text(file.title, overflow: TextOverflow.ellipsis, maxLines: 1),
                          subtitle: Text(file.toolType.label),
                          onTap: () => context.push(RoutePaths.toolkitRecentFiles),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({required this.title, required this.tools, this.gridColumns = 2});

  final String title;
  final List<_ToolCard> tools;
  final int gridColumns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(title),
        const SizedBox(height: 10),
        // A single-column row of cards used a fixed `childAspectRatio` via
        // `GridView.count`, same as the 2-column case - but that forces
        // every card to a fixed height derived purely from its *width*,
        // with no regard for how much taller a full-width card's content
        // (icon + label + subtitle + padding) actually needs. At normal
        // phone widths this was ~10px too short (visible as Scanner's
        // "Scan Document" card overflowing in debug builds - silently
        // clipped in release), and would only get worse at a larger
        // system font size. A plain `Column` lets each card size itself
        // to its own content instead of asserting a guessed ratio.
        if (gridColumns == 1)
          Column(
            children: [
              for (final (index, tool) in tools.indexed) ...[
                if (index > 0) const SizedBox(height: 12),
                EntranceFade(delay: Duration(milliseconds: 25 * index), child: tool),
              ],
            ],
          )
        else
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: gridColumns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              for (final (index, tool) in tools.indexed)
                EntranceFade(delay: Duration(milliseconds: 25 * index), child: tool),
            ],
          ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(height: 10),
              Text(label,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
