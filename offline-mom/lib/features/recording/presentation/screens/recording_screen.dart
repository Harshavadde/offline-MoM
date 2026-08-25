import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../meetings/presentation/providers/meeting_providers.dart';
import '../providers/recording_providers.dart';

/// The live in-progress recording view: waveform, timer, editable title,
/// pause/resume/stop/mark. Navigates to Meeting Details once stopped.
class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(recordingControllerProvider);

    ref.listen<RecordingUiState>(recordingControllerProvider, (previous, next) {
      if (next is RecordingFinished) {
        final meetingId = next.meetingId;
        ref.read(recordingControllerProvider.notifier).reset();
        context.pushReplacement(RoutePaths.meetingDetailsPath(meetingId));
      }
    });

    return PopScope(
      canPop: recordingState is! RecordingInProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || recordingState is! RecordingInProgress) return;
        final shouldStop = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Stop recording?'),
            content: const Text(
              'Leaving now will stop and save the current recording.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep recording'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Stop & save'),
              ),
            ],
          ),
        );
        if (shouldStop == true) {
          await ref.read(recordingControllerProvider.notifier).stopRecording();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Recording…')),
        body: switch (recordingState) {
          RecordingInProgress(:final meetingId, :final elapsed, :final isPaused, :final amplitude, :final amplitudeHistory) =>
            _RecordingBody(
              meetingId: meetingId,
              elapsed: elapsed,
              isPaused: isPaused,
              amplitude: amplitude,
              amplitudeHistory: amplitudeHistory,
              formatElapsed: _formatElapsed,
            ),
          RecordingFailed(:final message) => EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not start recording',
              message: message,
            ),
          _ => const EmptyState(
              icon: Icons.graphic_eq_rounded,
              title: 'No active recording',
              message: 'Start a recording from the Record screen to see the '
                  'live timer and pause/resume/stop controls here.',
            ),
        },
      ),
    );
  }
}

class _RecordingBody extends ConsumerWidget {
  const _RecordingBody({
    required this.meetingId,
    required this.elapsed,
    required this.isPaused,
    required this.amplitude,
    required this.amplitudeHistory,
    required this.formatElapsed,
  });

  final int meetingId;
  final Duration elapsed;
  final bool isPaused;
  final double amplitude;
  final List<double> amplitudeHistory;
  final String Function(Duration) formatElapsed;

  Future<void> _mark(BuildContext context, WidgetRef ref) async {
    final offset = await ref.read(recordingControllerProvider.notifier).addMark();
    if (offset == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Marked at ${formatElapsed(offset)}.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(recordingControllerProvider.notifier);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 80,
                  width: 260,
                  child: _Waveform(samples: amplitudeHistory, isPaused: isPaused),
                ),
                const SizedBox(height: 24),
                Text(
                  formatElapsed(elapsed),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  isPaused ? 'Paused' : 'Recording in progress',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundIconButton(
                      icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      onTap: () =>
                          isPaused ? controller.resumeRecording() : controller.pauseRecording(),
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurface,
                      label: isPaused ? 'Resume recording' : 'Pause recording',
                    ),
                    const SizedBox(width: 20),
                    _RecordPulse(
                      active: !isPaused,
                      child: _RoundIconButton(
                        icon: Icons.stop_rounded,
                        onTap: controller.stopRecording,
                        background: scheme.error,
                        foreground: scheme.onError,
                        size: 72,
                        label: 'Stop and save recording',
                      ),
                    ),
                    const SizedBox(width: 20),
                    _RoundIconButton(
                      icon: Icons.flag_outlined,
                      onTap: () => _mark(context, ref),
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurface,
                      label: 'Mark this moment',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _EditableTitleField(meetingId: meetingId),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.label,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;

  /// Accessible name for this control (TalkBack) - required since the
  /// visible content is icon-only, and the icon alone (e.g. a pause glyph
  /// that becomes a play glyph) doesn't convey which action it performs.
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: foreground, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

/// A slow, subtle breathing scale on [child] while [active] - gives the
/// Stop button (the one control tied directly to "recording is happening
/// right now") a quiet sense of life while capture is actually in
/// progress (V2.3, Premium Product Experience: "make recording feel
/// important"). Freezes at rest scale the moment [active] flips false
/// (paused, or recording ends) rather than finishing its current cycle -
/// a paused recording should read as visibly at rest, not still pulsing.
class _RecordPulse extends StatefulWidget {
  const _RecordPulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_RecordPulse> createState() => _RecordPulseState();
}

class _RecordPulseState extends State<_RecordPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _scale =
      Tween<double>(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_RecordPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.samples, required this.isPaused});

  final List<double> samples;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isPaused ? scheme.outline : scheme.primary;
    return CustomPaint(
      painter: _WaveformPainter(samples: samples, color: color),
      size: Size.infinite,
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 40;
    final barWidth = size.width / (barCount * 1.6);
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < barCount; i++) {
      final sampleIndex = samples.length - barCount + i;
      final level = sampleIndex >= 0 ? samples[sampleIndex] : 0.0;
      final barHeight = (size.height * 0.15) + (size.height * 0.75 * level);
      final x = i * (size.width / barCount) + barWidth;
      canvas.drawLine(
        Offset(x, size.height / 2 - barHeight / 2),
        Offset(x, size.height / 2 + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.color != color;
}

class _EditableTitleField extends ConsumerStatefulWidget {
  const _EditableTitleField({required this.meetingId});

  final int meetingId;

  @override
  ConsumerState<_EditableTitleField> createState() => _EditableTitleFieldState();
}

class _EditableTitleFieldState extends ConsumerState<_EditableTitleField> {
  final _controller = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final meeting = await ref.read(meetingRepositoryProvider).getById(widget.meetingId);
    if (meeting == null) return;
    await ref.read(meetingRepositoryProvider).update(
          meeting.copyWith(title: title, updatedAt: DateTime.now()),
        );
    ref.invalidate(meetingByIdProvider(widget.meetingId));
    ref.invalidate(meetingListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final meetingAsync = ref.watch(meetingByIdProvider(widget.meetingId));
    if (!_initialized) {
      final title = meetingAsync.valueOrNull?.title;
      if (title != null) {
        _controller.text = title;
        _initialized = true;
      }
    }

    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      onEditingComplete: _save,
      decoration: InputDecoration(
        labelText: 'Meeting Title',
        suffixIcon: IconButton(
          icon: const Icon(Icons.check_rounded),
          tooltip: 'Save title',
          onPressed: _save,
        ),
      ),
    );
  }
}
