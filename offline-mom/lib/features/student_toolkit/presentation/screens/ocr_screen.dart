import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../providers/ocr_providers.dart';
import '../toolkit_snackbars.dart';

/// Run OCR / Searchable PDF (P0-7) - a single shared progress+result screen
/// for every "make this searchable" entry point (Scanner's "Save Searchable
/// PDF", Images to PDF's "Generate Searchable PDF", View PDF's "Run OCR").
/// The session is primed by `OcrSessionController.start()` *before*
/// navigating here (mirrors `ScannerController`'s established shape) - this
/// screen is a pure view over that state, and processing begins
/// automatically, matching the spec's own flow (capture/pick -> OCR ->
/// progress -> searchable PDF -> preview -> save, with no separate
/// "configure, then press a button to start" step since there is exactly
/// one OCR language installed today).
class OcrScreen extends ConsumerWidget {
  const OcrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ocrSessionControllerProvider);
    final notifier = ref.read(ocrSessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.documentName.isEmpty ? 'Searchable PDF' : state.documentName),
      ),
      body: SafeArea(
        child: switch (state) {
          OcrSessionState(modelMissing: true) => _ModelMissingBody(),
          OcrSessionState(isBusy: true) => _ProgressBody(state: state, notifier: notifier),
          OcrSessionState(wasCancelled: true) => _CancelledBody(notifier: notifier),
          OcrSessionState(error: final e?) => _ErrorBody(message: e, notifier: notifier),
          OcrSessionState(isDone: true) => _ResultBody(state: state, notifier: notifier),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _ModelMissingBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.text_fields_rounded, size: 56),
            const SizedBox(height: 16),
            Text('OCR needs a language model', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Download the English OCR model in AI Model Manager, then come back and try again. '
              'It only needs to be downloaded once.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push(RoutePaths.aiModels),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Open AI Model Manager'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.state, required this.notifier});
  final OcrSessionState state;
  final OcrSessionController notifier;

  @override
  Widget build(BuildContext context) {
    final fraction = state.progressFraction;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${state.pagesTotal} page${state.pagesTotal == 1 ? '' : 's'} · ${state.languageDisplayName}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Text(
              state.pagesDone == 0
                  ? 'Starting…'
                  : 'Processing page ${state.pagesDone} of ${state.pagesTotal}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: fraction, minHeight: 10),
            ),
            const SizedBox(height: 8),
            Text(fraction == null ? '' : '${(fraction * 100).round()}%'),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: notifier.cancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _CancelledBody extends StatelessWidget {
  const _CancelledBody({required this.notifier});
  final OcrSessionController notifier;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_outlined, size: 56),
            const SizedBox(height: 16),
            Text('OCR cancelled', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Nothing was saved. Your original file was not changed.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: notifier.retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.notifier});
  final String message;
  final OcrSessionController notifier;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'OCR failed',
      message: message,
      actionLabel: 'Retry',
      onAction: notifier.retry,
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.state, required this.notifier});
  final OcrSessionState state;
  final OcrSessionController notifier;

  @override
  Widget build(BuildContext context) {
    final saved = state.savedFile != null;
    final bytes = state.resultBytes!;
    return Column(
      children: [
        Expanded(
          child: PdfPreview(
            build: (format) async => bytes,
            canDebug: false,
            allowPrinting: false,
            useActions: false,
            onError: (context, error) => ErrorState(title: 'Preview unavailable', error: error),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(children: [
                    Text('${state.sourcePages.length}', style: Theme.of(context).textTheme.titleMedium),
                    const Text('Pages'),
                  ]),
                  Column(children: [
                    Text(formatFileSize(bytes.lengthInBytes), style: Theme.of(context).textTheme.titleMedium),
                    const Text('PDF Size'),
                  ]),
                  Column(children: [
                    Text(state.languageDisplayName, style: Theme.of(context).textTheme.titleMedium),
                    const Text('OCR Language'),
                  ]),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: saved
                ? null
                : () async {
                    await notifier.save();
                    if (!context.mounted) return;
                    showSearchableCopyCreatedSnackBar(context);
                  },
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(saved ? Icons.check_rounded : Icons.save_alt_rounded, key: ValueKey(saved)),
            ),
            label: Text(saved ? 'Saved' : 'Save Searchable PDF'),
          ),
        ),
      ],
    );
  }
}
