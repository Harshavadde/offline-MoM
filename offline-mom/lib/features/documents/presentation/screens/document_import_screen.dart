import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/friendly_error.dart';
import '../providers/document_providers.dart';

/// Import an existing document (PDF/DOCX/TXT/Markdown) - mirrors
/// `import_screen.dart` exactly
/// (lib/features/import/presentation/screens/import_screen.dart), adapted
/// for [DocumentImportController] instead of `ImportController`.
class DocumentImportScreen extends ConsumerWidget {
  const DocumentImportScreen({super.key});

  static const _formats = ['PDF', 'DOCX', 'TXT', 'MD'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(documentImportControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<DocumentImportUiState>(documentImportControllerProvider, (previous, next) {
      if (next is DocumentImportSucceeded) {
        final documentId = next.documentId;
        ref.read(documentImportControllerProvider.notifier).reset();
        context.pushReplacement(RoutePaths.documentDetailsPath(documentId));
      } else if (next is DocumentImportFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(next.message))),
        );
        ref.read(documentImportControllerProvider.notifier).reset();
      }
    });

    final isProcessing = importState is DocumentImportProcessing;

    return Scaffold(
      appBar: AppBar(title: const Text('Import Document')),
      body: SafeArea(
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
                      : () => ref
                          .read(documentImportControllerProvider.notifier)
                          .importFile(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 20,
                    ),
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
                                  child: CircularProgressIndicator(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                )
                              : Icon(
                                  Icons.file_upload_outlined,
                                  size: 34,
                                  color: scheme.onPrimaryContainer,
                                ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isProcessing
                              ? 'Importing document…'
                              : 'Tap to choose a file',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isProcessing
                              ? 'Copying the file into OfflineMoMAI. This '
                                  'stays on this device.'
                              : 'Pick a PDF, Word, text or Markdown file '
                                  'from this device to read and summarize '
                                  'offline.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (!isProcessing) ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => ref
                                .read(documentImportControllerProvider.notifier)
                                .importFile(),
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
              Text(
                'Supported formats',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final format in _formats)
                    Chip(
                      label: Text(format),
                      backgroundColor: scheme.surfaceContainerHighest,
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Text is extracted and summarized entirely on this device. '
                'Nothing ever leaves this device.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
