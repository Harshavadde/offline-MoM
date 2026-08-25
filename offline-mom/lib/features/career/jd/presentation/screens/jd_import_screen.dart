import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../models/job_description.dart';
import '../../../../../shared/widgets/section_heading.dart';
import '../providers/jd_import_providers.dart';

/// Import a Job Description (PDF/DOCX/TXT/Markdown) - mirrors
/// `ResumeImportScreen`'s exact pick/review shape
/// (lib/features/career/resume/presentation/screens/resume_import_screen.dart).
/// Confirming hands the in-memory [ParsedJobDescription] to
/// `ResumeJdAnalysisScreen` via the route's `extra` - it is never written
/// to the database (see the Batch 8 report for why).
class JdImportScreen extends ConsumerWidget {
  const JdImportScreen({super.key});

  static const _formats = ['PDF', 'DOCX', 'TXT', 'MD'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(jdImportControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<JdImportUiState>(jdImportControllerProvider, (previous, next) {
      if (next is JdImportConfirmed) {
        final draft = next.draft;
        ref.read(jdImportControllerProvider.notifier).reset();
        context.pushReplacement(RoutePaths.resumeJdAnalysis, extra: draft);
      } else if (next is JdImportFailed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
        ref.read(jdImportControllerProvider.notifier).reset();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Import Job Description')),
      body: switch (state) {
        JdImportIdle() || JdImportProcessing() =>
          _PickBody(isProcessing: state is JdImportProcessing, scheme: scheme),
        JdImportReviewing(:final draft) => _ReviewBody(draft: draft),
        JdImportConfirmed() || JdImportFailed() => const SizedBox.shrink(),
      },
    );
  }
}

class _PickBody extends ConsumerWidget {
  const _PickBody({required this.isProcessing, required this.scheme});

  final bool isProcessing;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: isProcessing
                    ? null
                    : () => ref.read(jdImportControllerProvider.notifier).pickAndParse(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: isProcessing
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: CircularProgressIndicator(color: scheme.onPrimaryContainer),
                              )
                            : Icon(
                                Icons.description_outlined,
                                size: 34,
                                color: scheme.onPrimaryContainer,
                              ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isProcessing ? 'Reading the job description…' : 'Tap to choose a file',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isProcessing
                            ? 'Extracting and structuring the content on this device.'
                            : 'Pick a job description from this device - we\'ll '
                                'extract its requirements so you can compare it '
                                'against a resume.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (!isProcessing) ...[
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () =>
                              ref.read(jdImportControllerProvider.notifier).pickAndParse(),
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Choose a file'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Supported formats', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final format in JdImportScreen._formats)
                  Chip(
                    label: Text(format),
                    backgroundColor: scheme.surfaceContainerHighest,
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'The job description is read and analyzed entirely on this '
              'device. Nothing is ever uploaded or sent anywhere.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({required this.draft});

  final ParsedJobDescription draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                Text(
                  draft.title ?? 'Job description',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (draft.company != null)
                  Text(
                    draft.company!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 20),
                _DetectedListCard(label: 'Requirements', entries: draft.requirements),
                _DetectedListCard(label: 'Responsibilities', entries: draft.responsibilities),
                _DetectedListCard(label: 'Education requirements', entries: draft.educationRequirements),
                _DetectedListCard(
                  label: 'Certification requirements',
                  entries: draft.certificationRequirements,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Experience requirement', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            draft.experienceRequirement?.rawText ??
                                'No specific years-of-experience requirement detected.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (draft.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const SectionHeading('Warnings'),
                  const SizedBox(height: 8),
                  Card(
                    color: scheme.tertiaryContainer,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final warning in draft.warnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                warning,
                                style: TextStyle(color: scheme.onTertiaryContainer),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (draft.unclassifiedText.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionHeading('Could not be automatically classified'),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final text in draft.unclassifiedText) ...[
                            Text(text),
                            const Divider(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ref.read(jdImportControllerProvider.notifier).reset(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => ref.read(jdImportControllerProvider.notifier).confirm(),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectedListCard extends StatelessWidget {
  const _DetectedListCard({required this.label, required this.entries});

  final String label;
  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label (${entries.length})', style: Theme.of(context).textTheme.titleSmall),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'None detected.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                for (final entry in entries)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $entry')),
            ],
          ),
        ),
      ),
    );
  }
}
