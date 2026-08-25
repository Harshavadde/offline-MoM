import 'package:flutter/material.dart';

import 'confirm_dialog.dart';

/// Generic list-row card, originally built for anything that is a
/// Knowledge Source (a [Meeting] or a [Document]) - Phase 2B, item #6
/// ("Knowledge Source abstraction") and the QUALITY requirement "No
/// duplicate widgets" (docs/v2/implementation/03-decisions.md, ADR-028) -
/// and, since Phase 5A, reused as-is for Student Toolkit's Recent Files
/// rows too (`ToolkitFile` isn't a Knowledge Source - it's not part of the
/// searchable workspace - but the same icon/title/status/size/swipe-to-
/// delete row shape fits it exactly, and building a near-identical second
/// widget for that reason alone would itself violate "no duplicated
/// widgets").
///
/// Takes plain/primitive parameters rather than a [Meeting]/[Document]
/// directly, mirroring `AiPipelineFallback`'s established precedent
/// (lib/shared/widgets/ai_pipeline_fallback.dart) - callers translate their
/// own status enum into [statusLabel]/[statusColor]/[progress] and their own
/// pipeline-completion state into [isSummaryAvailable]/[isSearchable], so
/// this widget stays reusable for any future row type without depending on
/// `MeetingStatus`/`DocumentStatus`/etc. themselves.
class KnowledgeSourceCard extends StatelessWidget {
  const KnowledgeSourceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.updatedLabel,
    required this.statusLabel,
    required this.statusColor,
    this.progress,
    this.sizeLabel,
    this.isSummaryAvailable = false,
    this.isSearchable = false,
    this.onTap,
    this.onDelete,
    this.dismissibleKey,
    this.deleteConfirmTitle,
    this.deleteConfirmMessage,
    this.trailing,
  }) : assert(
          onDelete == null || (dismissibleKey != null && deleteConfirmTitle != null),
          'onDelete requires dismissibleKey and deleteConfirmTitle to build the swipe-to-delete confirmation',
        );

  final IconData icon;
  final String title;

  /// "Last updated" (Phase 2B Knowledge Source card requirement) - already
  /// formatted by the caller (e.g. `DateFormat.yMMMd().add_jm()`), since
  /// formatting is a display concern this widget shouldn't own.
  final String updatedLabel;

  final String statusLabel;
  final Color statusColor;

  /// Coarse pipeline progress (0.0-1.0), null once there's no more pipeline
  /// left to show progress through (ready/error) - same convention as the
  /// tiles this widget replaces.
  final double? progress;

  /// "Size" (Phase 2B card requirement) - e.g. a file size or a recording
  /// duration, already formatted by the caller. Null hides the badge.
  final String? sizeLabel;

  /// "AI Summary available" / "Indexed status" (Phase 2B card requirement) -
  /// both derived from the same pipeline milestone in this app (a meeting or
  /// document only has a summary once it has passed indexing too), so one
  /// flag covers both badges.
  final bool isSummaryAvailable;

  /// "Searchable indicator" (Phase 2B card requirement).
  final bool isSearchable;

  final VoidCallback? onTap;

  /// When provided (along with [dismissibleKey] and [deleteConfirmTitle]),
  /// the card becomes swipe-to-delete with a confirmation dialog.
  final VoidCallback? onDelete;
  final Key? dismissibleKey;
  final String? deleteConfirmTitle;
  final String? deleteConfirmMessage;

  /// Optional trailing control shown before the status chip (e.g. a
  /// meeting's favorite star) - null for Knowledge Source types that don't
  /// have one.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);
    final onDelete = this.onDelete;
    if (onDelete == null) return card;

    return Dismissible(
      key: dismissibleKey!,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      child: card,
    );
  }

  Future<bool> _confirmDelete(BuildContext context) => showDestructiveConfirmDialog(
        context,
        title: deleteConfirmTitle!,
        message: deleteConfirmMessage ?? 'This can\'t be undone.',
      );

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sizeLabel == null ? updatedLabel : '$updatedLabel · $sizeLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    if (progress case final value?) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 4,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                    if (isSummaryAvailable || isSearchable) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          if (isSummaryAvailable)
                            const _Indicator(icon: Icons.auto_awesome_rounded, label: 'Summary'),
                          if (isSearchable)
                            const _Indicator(icon: Icons.manage_search_rounded, label: 'Searchable'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
              _StatusChip(label: statusLabel, color: statusColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.primary),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
