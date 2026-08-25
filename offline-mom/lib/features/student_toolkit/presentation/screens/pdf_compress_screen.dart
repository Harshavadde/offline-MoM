import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/toolkit/pdf_compression_service.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/pdf_compress_providers.dart';
import '../toolkit_error_body.dart';
import '../toolkit_snackbars.dart';

/// Compress PDF (V2 Phase 5B) - mirrors `ImageCompressScreen`'s structure
/// exactly (same pick -> configure -> processing -> result -> error state
/// switch), adapted for a PDF source and named presets instead of a
/// target-KB/quality slider.
class PdfCompressScreen extends ConsumerWidget {
  const PdfCompressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfCompressControllerProvider);
    final notifier = ref.read(pdfCompressControllerProvider.notifier);

    ref.listen<PdfCompressUiState>(pdfCompressControllerProvider, (previous, next) {
      if (next is PdfCompressError && next.source == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
        notifier.reset();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compress PDF'),
        actions: [
          if (state is! PdfCompressEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: notifier.reset,
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state) {
          PdfCompressEmpty() => _PickPrompt(onPick: notifier.pickPdf),
          PdfCompressReady(:final source) =>
            _ConfigureBody(fileName: source.fileName, sizeBytes: source.sizeBytes, onCompress: notifier.compress),
          PdfCompressProcessing() => _ProcessingBody(onCancel: notifier.cancel),
          PdfCompressDone(:final result, :final savedFile) => _ResultBody(
              result: result,
              saved: savedFile != null,
              onSave: () async {
                await notifier.save();
                if (!context.mounted) return;
                showSavedToRecentFilesSnackBar(context);
              },
              onShare: notifier.share,
              onTryAgain: notifier.cancel,
            ),
          PdfCompressError(:final source, :final message) when source != null => ToolkitErrorBody(
              message: message,
              onRetry: notifier.cancel,
              onPickAgain: notifier.reset,
              pickAgainLabel: 'Pick a different PDF',
            ),
          PdfCompressError() => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.picture_as_pdf_rounded,
      title: 'Shrink a PDF\'s file size',
      message: 'For resumes, scholarship forms, exam portals and more - '
          'entirely on this device, nothing is ever uploaded.',
      actions: [
        FilledButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose a PDF'),
        ),
      ],
    );
  }
}

class _ConfigureBody extends StatefulWidget {
  const _ConfigureBody({required this.fileName, required this.sizeBytes, required this.onCompress});

  final String fileName;
  final int sizeBytes;
  final Future<void> Function(PdfCompressionPreset preset, {double? customDpi, int? customQuality}) onCompress;

  @override
  State<_ConfigureBody> createState() => _ConfigureBodyState();
}

class _ConfigureBodyState extends State<_ConfigureBody> {
  PdfCompressionPreset _preset = PdfCompressionPreset.resumeUpload;
  double _customDpi = 150;
  double _customQuality = 80;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCustom = _preset == PdfCompressionPreset.custom;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
              subtitle: Text('Original size: ${formatFileSize(widget.sizeBytes)}'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            PdfCompressPresetSpecs.disclaimer,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in PdfCompressionPreset.values)
                ChoiceChip(
                  label: Text(PdfCompressPresetSpecs.labelFor(preset)),
                  selected: _preset == preset,
                  onSelected: (_) => setState(() => _preset = preset),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isCustom) ...[
            Text('Resolution: ${_customDpi.round()} DPI', style: Theme.of(context).textTheme.bodyMedium),
            Slider(
              value: _customDpi,
              min: 72,
              max: 300,
              divisions: 19,
              label: '${_customDpi.round()} DPI',
              onChanged: (v) => setState(() => _customDpi = v),
            ),
            Text('Quality: ${_customQuality.round()}', style: Theme.of(context).textTheme.bodyMedium),
            Slider(
              value: _customQuality,
              min: 20,
              max: 95,
              divisions: 15,
              label: _customQuality.round().toString(),
              onChanged: (v) => setState(() => _customQuality = v),
            ),
          ] else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Builder(builder: (context) {
                  final spec = PdfCompressPresetSpecs.specFor(_preset);
                  return Text(
                    '${spec.dpi.round()} DPI, quality ${spec.jpegQuality}',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                }),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => widget.onCompress(
              _preset,
              customDpi: isCustom ? _customDpi : null,
              customQuality: isCustom ? _customQuality.round() : null,
            ),
            icon: const Icon(Icons.compress_rounded),
            label: const Text('Compress'),
          ),
        ],
      ),
    );
  }
}

class _ProcessingBody extends StatelessWidget {
  const _ProcessingBody({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text('Compressing…', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'This stays on your device.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.result,
    required this.saved,
    required this.onSave,
    required this.onShare,
    required this.onTryAgain,
  });

  final PdfCompressionResult result;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduction = result.originalSizeBytes > 0
        ? (1 - (result.resultSizeBytes / result.originalSizeBytes)) * 100
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _stat(context, 'Original', formatFileSize(result.originalSizeBytes)),
                      Icon(Icons.arrow_forward_rounded, color: scheme.onSurfaceVariant),
                      _stat(context, 'Compressed', formatFileSize(result.resultSizeBytes)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: reduction >= 0 ? scheme.primaryContainer : scheme.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${reduction >= 0 ? '-' : '+'}${reduction.abs().toStringAsFixed(0)}% size',
                      style: TextStyle(
                        color: reduction >= 0 ? scheme.onPrimaryContainer : scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${result.pageCount} page${result.pageCount == 1 ? '' : 's'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: saved ? null : onSave,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                saved ? Icons.check_rounded : Icons.save_alt_rounded,
                key: ValueKey(saved),
              ),
            ),
            label: Text(saved ? 'Saved' : 'Save'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share'),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onTryAgain, child: const Text('Try different settings')),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

