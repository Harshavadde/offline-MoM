import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/toolkit/image_compression_service.dart';
import '../../../../services/toolkit/toolkit_image_picker_service.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/image_compress_providers.dart';
import '../toolkit_error_body.dart';
import '../toolkit_snackbars.dart';

/// Compress Image (Student Toolkit, V2 Phase 5A) - pick/capture, choose a
/// preset or configure Advanced Mode, compress, preview, save/share.
/// Everything runs on-device (`ImageCompressController` -> `compute()` ->
/// `compressImage`, services/toolkit/image_compression_service.dart) - no
/// upload, no network call of any kind.
class ImageCompressScreen extends ConsumerStatefulWidget {
  const ImageCompressScreen({super.key});

  @override
  ConsumerState<ImageCompressScreen> createState() => _ImageCompressScreenState();
}

class _ImageCompressScreenState extends ConsumerState<ImageCompressScreen> {
  bool _useAdvanced = false;
  ImageCompressionPreset _preset = ImageCompressionPreset.passport;

  final _targetKbController = TextEditingController(text: '200');
  double _quality = 80;
  bool _limitResolution = true;
  final _maxWidthController = TextEditingController(text: '1600');
  final _maxHeightController = TextEditingController(text: '1600');
  ImageOutputFormat _advancedFormat = ImageOutputFormat.jpg;

  @override
  void dispose() {
    _targetKbController.dispose();
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    super.dispose();
  }

  Future<void> _runCompress() async {
    final controller = ref.read(imageCompressControllerProvider.notifier);
    if (_useAdvanced) {
      final targetKb = int.tryParse(_targetKbController.text.trim());
      final maxWidth = _limitResolution ? int.tryParse(_maxWidthController.text.trim()) : null;
      final maxHeight = _limitResolution ? int.tryParse(_maxHeightController.text.trim()) : null;
      await controller.compress(
        outputFormat: _advancedFormat,
        targetSizeBytes:
            _advancedFormat == ImageOutputFormat.jpg && targetKb != null ? targetKb * 1024 : null,
        quality: _advancedFormat == ImageOutputFormat.jpg && targetKb == null
            ? _quality.round()
            : null,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    } else {
      final spec = ImageCompressPresetSpecs.specFor(_preset);
      await controller.compress(
        outputFormat: ImageOutputFormat.jpg,
        targetSizeBytes: spec.targetSizeBytes,
        maxWidth: spec.maxWidth,
        maxHeight: spec.maxHeight,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageCompressControllerProvider);

    ref.listen<ImageCompressUiState>(imageCompressControllerProvider, (previous, next) {
      if (next is ImageCompressError && next.source == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message)),
        );
        ref.read(imageCompressControllerProvider.notifier).reset();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compress Image'),
        actions: [
          if (state is! ImageCompressEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: () => ref.read(imageCompressControllerProvider.notifier).reset(),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state) {
          ImageCompressEmpty() => _PickPrompt(
              onGallery: () => ref.read(imageCompressControllerProvider.notifier).pickFromGallery(),
              onCamera: () => ref.read(imageCompressControllerProvider.notifier).captureFromCamera(),
            ),
          ImageCompressReady(:final source) => _ConfigureBody(
              source: source,
              useAdvanced: _useAdvanced,
              onModeChanged: (v) => setState(() => _useAdvanced = v),
              preset: _preset,
              onPresetChanged: (p) => setState(() => _preset = p),
              targetKbController: _targetKbController,
              quality: _quality,
              onQualityChanged: (v) => setState(() => _quality = v),
              limitResolution: _limitResolution,
              onLimitResolutionChanged: (v) => setState(() => _limitResolution = v),
              maxWidthController: _maxWidthController,
              maxHeightController: _maxHeightController,
              advancedFormat: _advancedFormat,
              onAdvancedFormatChanged: (f) => setState(() => _advancedFormat = f),
              onCompress: _runCompress,
            ),
          ImageCompressProcessing() => _ProcessingBody(
              onCancel: () => ref.read(imageCompressControllerProvider.notifier).cancel(),
            ),
          ImageCompressDone(:final source, :final result, :final savedFile) => _ResultBody(
              source: source,
              result: result,
              saved: savedFile != null,
              onSave: () async {
                await ref.read(imageCompressControllerProvider.notifier).save();
                if (!context.mounted) return;
                showSavedToRecentFilesSnackBar(context);
              },
              onShare: () => ref.read(imageCompressControllerProvider.notifier).share(),
              onTryAgain: () => ref.read(imageCompressControllerProvider.notifier).cancel(),
            ),
          ImageCompressError(:final source, :final message) when source != null => ToolkitErrorBody(
              message: message,
              onRetry: () => ref.read(imageCompressControllerProvider.notifier).cancel(),
              onPickAgain: () => ref.read(imageCompressControllerProvider.notifier).reset(),
              pickAgainLabel: 'Pick a different image',
            ),
          ImageCompressError() => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({required this.onGallery, required this.onCamera});

  final VoidCallback onGallery;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.compress_rounded,
      title: 'Shrink a photo\'s file size',
      message: 'For passport photos, scholarship forms, exam portals and '
          'more - entirely on this device, nothing is ever uploaded.',
      actions: [
        FilledButton.icon(
          onPressed: onGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from Gallery'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onCamera,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Take a Photo'),
        ),
      ],
    );
  }
}

class _ConfigureBody extends StatelessWidget {
  const _ConfigureBody({
    required this.source,
    required this.useAdvanced,
    required this.onModeChanged,
    required this.preset,
    required this.onPresetChanged,
    required this.targetKbController,
    required this.quality,
    required this.onQualityChanged,
    required this.limitResolution,
    required this.onLimitResolutionChanged,
    required this.maxWidthController,
    required this.maxHeightController,
    required this.advancedFormat,
    required this.onAdvancedFormatChanged,
    required this.onCompress,
  });

  final PickedToolkitImage source;
  final bool useAdvanced;
  final ValueChanged<bool> onModeChanged;
  final ImageCompressionPreset preset;
  final ValueChanged<ImageCompressionPreset> onPresetChanged;
  final TextEditingController targetKbController;
  final double quality;
  final ValueChanged<double> onQualityChanged;
  final bool limitResolution;
  final ValueChanged<bool> onLimitResolutionChanged;
  final TextEditingController maxWidthController;
  final TextEditingController maxHeightController;
  final ImageOutputFormat advancedFormat;
  final ValueChanged<ImageOutputFormat> onAdvancedFormatChanged;
  final VoidCallback onCompress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              source.bytes,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Original size: ${formatFileSize(source.sizeBytes)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Presets'), icon: Icon(Icons.tune_rounded)),
              ButtonSegment(
                  value: true, label: Text('Advanced'), icon: Icon(Icons.settings_rounded)),
            ],
            selected: {useAdvanced},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
          const SizedBox(height: 16),
          if (!useAdvanced) ...[
            Text(
              ImageCompressPresetSpecs.disclaimer,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in ImageCompressionPreset.values.where((p) => p != ImageCompressionPreset.custom))
                  ChoiceChip(
                    label: Text(p.label),
                    selected: preset == p,
                    onSelected: (_) => onPresetChanged(p),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Builder(builder: (context) {
                  final spec = ImageCompressPresetSpecs.specFor(preset);
                  return Text(
                    'Target: under ${formatFileSize(spec.targetSizeBytes)}, '
                    'max ${spec.maxWidth}×${spec.maxHeight}px',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                }),
              ),
            ),
          ] else ...[
            TextField(
              controller: targetKbController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target size (KB)',
                helperText: 'Leave blank to use the quality slider instead',
              ),
            ),
            const SizedBox(height: 16),
            Text('Quality: ${quality.round()}', style: Theme.of(context).textTheme.bodyMedium),
            Slider(
              value: quality,
              min: 10,
              max: 95,
              divisions: 17,
              label: quality.round().toString(),
              onChanged: onQualityChanged,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limit resolution'),
              value: limitResolution,
              onChanged: onLimitResolutionChanged,
            ),
            if (limitResolution) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: maxWidthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max width (px)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxHeightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max height (px)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text('Output format', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final f in ImageOutputFormat.values)
                  ChoiceChip(
                    label: Text(f.extension.toUpperCase()),
                    selected: advancedFormat == f,
                    onSelected: (_) => onAdvancedFormatChanged(f),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCompress,
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
    required this.source,
    required this.result,
    required this.saved,
    required this.onSave,
    required this.onShare,
    required this.onTryAgain,
  });

  final PickedToolkitImage source;
  final ImageCompressionResult result;
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
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(result.bytes, height: 220, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sizeStat(context, 'Original', formatFileSize(result.originalSizeBytes)),
                      Icon(Icons.arrow_forward_rounded, color: scheme.onSurfaceVariant),
                      _sizeStat(context, 'Compressed', formatFileSize(result.resultSizeBytes)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (reduction >= 0 ? scheme.primaryContainer : scheme.errorContainer),
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
                  if (!result.reachedTarget) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Could not reach the exact target size without losing too much '
                            'quality - this is the closest safe result.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                  ],
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

  Widget _sizeStat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

