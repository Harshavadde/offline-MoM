import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../models/resume_block_type.dart';
import '../../../../../shared/widgets/ai_disclaimer.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../../../../shared/widgets/skeleton_loader.dart';
import '../providers/resume_suggestion_providers.dart';

/// Lists every still-pending AI suggestion for one resume and lets the
/// user accept or reject each individually (docs/v3/01-prd.md §12, §25
/// Milestone 3). Every suggestion listed here already passed generation -
/// this screen never triggers generation itself, it only reviews what
/// already exists as a `SuggestedEdit` row.
class ResumeSuggestionReviewScreen extends ConsumerWidget {
  const ResumeSuggestionReviewScreen({super.key, required this.resumeId});

  final int resumeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(suggestionReviewListProvider(resumeId));
    final actionState = ref.watch(suggestionReviewControllerProvider(resumeId));

    return Scaffold(
      appBar: AppBar(title: const Text('Review suggestions')),
      body: SafeArea(
        child: itemsAsync.when(
          loading: () => const SkeletonCardList(),
          error: (err, _) => ErrorState(title: "Couldn't load suggestions", error: err),
          data: (items) {
            if (items.isEmpty) {
              // R-11 P0 fix: this previously read as a dead end right after
              // a user tapped "Generate AI suggestions" and it legitimately
              // found nothing to suggest (a resume's skills already
              // directly matching the JD, or nothing safe to rewrite
              // without inventing content - see
              // GenerateResumeSuggestionsUseCase's own doc comment) -
              // "check back after running one" made it sound like
              // generation hadn't happened yet, when it just had and this
              // was its honest result. Explains the "why" instead.
              return const EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: 'No suggestions right now',
                message: 'This can mean your resume already closely matches the job '
                    "description, or there's nothing here to safely rewrite without "
                    'adding content that isn\'t already in your resume. Go back to the '
                    'job description analysis to review matches directly, or generate '
                    'suggestions again after updating your resume.',
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const AiDisclaimer.resume(),
                const SizedBox(height: 12),
                if (actionState.error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        actionState.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  ),
                for (final item in items)
                  _SuggestionCard(
                    resumeId: resumeId,
                    item: item,
                    isBusy: actionState.busyId == item.edit.id,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.resumeId, required this.item, required this.isBusy});

  final int resumeId;
  final SuggestionReviewItem item;
  final bool isBusy;

  String _sectionLabel(ResumeBlockType? type) {
    return switch (type) {
      ResumeBlockType.experience => 'Experience',
      ResumeBlockType.education => 'Education',
      ResumeBlockType.project => 'Project',
      ResumeBlockType.certification => 'Certification',
      ResumeBlockType.skill => 'Skill',
      ResumeBlockType.customSection => 'Section',
      null => 'Profile',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final edit = item.edit;
    final check = item.fabricationCheck;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(label: Text(_sectionLabel(edit.targetBlockType))),
                if (edit.sourceRequirement != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Addresses: ${edit.sourceRequirement}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Original text',
              child: Text(
                'Original',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            Text(edit.originalValue),
            const SizedBox(height: 12),
            Semantics(
              label: 'Suggested text',
              child: Text(
                'Suggested',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(edit.suggestedValue),
            if (!check.isSafe) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Review carefully - mentions details not found in your original text: '
                        '${[...check.newProperNouns, ...check.newNumbers].join(', ')}. This is '
                        'a best-effort check, not a guarantee.',
                        style: TextStyle(color: scheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () => ref
                          .read(suggestionReviewControllerProvider(resumeId).notifier)
                          .reject(edit.id!),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: isBusy
                      ? null
                      : () => ref
                          .read(suggestionReviewControllerProvider(resumeId).notifier)
                          .accept(edit.id!),
                  child: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
