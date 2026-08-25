import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/toolkit/image_resize_service.dart';
import '../../../../services/toolkit/toolkit_image_picker_service.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/image_resize_providers.dart';
import '../toolkit_error_body.dart';
import '../toolkit_snackbars.dart';

/// Resize Image (Student Toolkit, V2 Phase 5A) - pick/capture, resize by
/// percentage/width/height (with an aspect-ratio lock), optionally convert
/// format, preview, save/share. Everything on-device - see
/// `ImageCompressScreen`'s identical doc comment for the same "no upload,
/// no network" statement, which applies here unchanged.
class ImageResizeScreen extends ConsumerStatefulWidget {
  const ImageResizeScreen({super.key});

  @override
  ConsumerState<ImageResizeScreen> createState() => _ImageResizeScreenState();
}

class _ImageResizeScreenState extends ConsumerState<ImageResizeScreen> {
  ImageResizeMode _mode = ImageResizeMode.percentage;
  double _percentage = 50;
  final _widthController = TextEditingController(text: '1024');
  final _heightController = TextEditingController(text: '1024');
  bool _maintainAspectRatio = true;
  ImageResizeOutputFormat _format = ImageResizeOutputFormat.jpg;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _runResize() async {
    final controller = ref.read(imageResizeControllerProvider.notifier);
    await controller.resize(
      mode: _mode,
      outputFormat: _format,
      percentage: _mode == ImageResizeMode.percentage ? _percentage : null,
      targetWidth: _mode == ImageResizeMode.width ? int.tryParse(_widthController.text.trim()) : null,
      targetHeight:
          _mode == ImageResizeMode.height ? int.tryParse(_heightController.text.trim()) : null,
      maintainAspectRatio: _maintainAspectRatio,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageResizeControllerProvider);

    ref.listen<ImageResizeUiState>(imageResizeControllerProvider, (previous, next) {
      if (next is ImageResizeError && next.source == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
        ref.read(imageResizeControllerProvider.notifier).reset();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resize Image'),
        actions: [
          if (state is! ImageResizeEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: () => ref.read(imageResizeControllerProvider.notifier).reset(),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state) {
          ImageResizeEmpty() => _PickPrompt(
              onGallery: () => ref.read(imageResizeControllerProvider.notifier).pickFromGallery(),
              onCamera: () => ref.read(imageResizeControllerProvider.notifier).captureFromCamera(),
            ),
          ImageResizeReady(:final source) => _ConfigureBody(
              source: source,
              mode: _mode,
              onModeChanged: (m) => setState(() => _mode = m),
              percentage: _percentage,
              onPercentageChanged: (v) => setState(() => _percentage = v),
              widthController: _widthController,
              heightController: _heightController,
              maintainAspectRatio: _maintainAspectRatio,
              onMaintainAspectRatioChanged: (v) => setState(() => _maintainAspectRatio = v),
              format: _format,
              onFormatChanged: (f) => setState(() => _format = f),
              onResize: _runResize,
            ),
          ImageResizeProcessing() => _ProcessingBody(
              onCancel: () => ref.read(imageResizeControllerProvider.notifier).cancel(),
            ),
          ImageResizeDone(:final result, :final savedFile) => _ResultBody(
              result: result,
              saved: savedFile != null,
              onSave: () async {
                await ref.read(imageResizeControllerProvider.notifier).save();
                if (!context.mounted) return;
                showSavedToRecentFilesSnackBar(context);
              },
              onShare: () => ref.read(imageResizeControllerProvider.notifier).share(),
              onTryAgain: () => ref.read(imageResizeControllerProvider.notifier).cancel(),
            ),
          ImageResizeError(:final source, :final message) when source != null => ToolkitErrorBody(
              message: message,
              onRetry: () => ref.read(imageResizeControllerProvider.notifier).cancel(),
              onPickAgain: () => ref.read(imageResizeControllerProvider.notifier).reset(),
              pickAgainLabel: 'Pick a different image',
            ),
          ImageResizeError() => const SizedBox.shrink(),
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
      icon: Icons.aspect_ratio_rounded,
      title: 'Change a photo\'s dimensions',
      message: 'By percentage, width, or height - entirely on this device.',
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
    required this.mode,
    required this.onModeChanged,
    required this.percentage,
    required this.onPercentageChanged,
    required this.widthController,
    required this.heightController,
    required this.maintainAspectRatio,
    required this.onMaintainAspectRatioChanged,
    required this.format,
    required this.onFormatChanged,
    required this.onResize,
  });

  final PickedToolkitImage source;
  final ImageResizeMode mode;
  final ValueChanged<ImageResizeMode> onModeChanged;
  final double percentage;
  final ValueChanged<double> onPercentageChanged;
  final TextEditingController widthController;
  final TextEditingController heightController;
  final bool maintainAspectRatio;
  final ValueChanged<bool> onMaintainAspectRatioChanged;
  final ImageResizeOutputFormat format;
  final ValueChanged<ImageResizeOutputFormat> onFormatChanged;
  final VoidCallback onResize;

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
            child: Image.memory(source.bytes, height: 200, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Text(
            'Original size: ${formatFileSize(source.sizeBytes)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SegmentedButton<ImageResizeMode>(
            segments: const [
              ButtonSegment(value: ImageResizeMode.percentage, label: Text('%')),
              ButtonSegment(value: ImageResizeMode.width, label: Text('Width')),
              ButtonSegment(value: ImageResizeMode.height, label: Text('Height')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
          const SizedBox(height: 16),
          switch (mode) {
            ImageResizeMode.percentage => Column(
                children: [
                  Text('${percentage.round()}%', style: Theme.of(context).textTheme.titleMedium),
                  Slider(
                    value: percentage,
                    min: 10,
                    max: 200,
                    divisions: 38,
                    label: '${percentage.round()}%',
                    onChanged: onPercentageChanged,
                  ),
                ],
              ),
            ImageResizeMode.width => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: widthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Target width (px)'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Maintain aspect ratio'),
                    value: maintainAspectRatio,
                    onChanged: onMaintainAspectRatioChanged,
                  ),
                ],
              ),
            ImageResizeMode.height => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: heightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Target height (px)'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Maintain aspect ratio'),
                    value: maintainAspectRatio,
                    onChanged: onMaintainAspectRatioChanged,
                  ),
                ],
              ),
          },
          const SizedBox(height: 8),
          Text('Output format', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final f in ImageResizeOutputFormat.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: format == f,
                  onSelected: (_) => onFormatChanged(f),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onResize,
            icon: const Icon(Icons.aspect_ratio_rounded),
            label: const Text('Resize'),
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
          Text('Resizing…', style: Theme.of(context).textTheme.titleMedium),
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

  final ImageResizeResult result;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onTryAgain;

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
            child: Image.memory(result.bytes, height: 220, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${result.originalWidth}×${result.originalHeight} → '
                    '${result.width}×${result.height}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatFileSize(result.originalSizeBytes)} → '
                    '${formatFileSize(result.resultSizeBytes)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
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
}
